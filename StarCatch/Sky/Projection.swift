import CoreGraphics
import Foundation
import simd

/// 局部天空与全局轨道场共享的连续尺度规则。
///
/// 1× 以上是局部长焦；1× 到 `minimumLocalMagnification` 是扩展天空；
/// 再继续缩小只积累带阻力的全局转场进度，不继续扩大平面投影。
enum ObservationScale {
    static let minimumLocalMagnification: CGFloat = 0.52
    static let maximumLocalMagnification: CGFloat = 4
    static let overviewTransitionTravel: CGFloat = 0.22
    static let overviewCommitProgress: Double = 0.72
    static let maximumOverviewZoom: CGFloat = 1.72
    static let overviewReturnTravel: CGFloat = 0.34

    /// 局部天空与地球仪之间的唯一视觉时间轴。所有字段都由同一归一化进度
    /// 推导，避免缩放、透明度、地球尺寸和轨道点云分别使用动画而产生跳帧。
    struct TransitionVisuals: Equatable {
        let progress: Double
        let cameraRetreat: Double
        let localSkyOpacity: Double
        let localSkyScale: CGFloat
        let globeOpacity: Double
        let globeScale: CGFloat
        let globeVerticalOffset: CGFloat
        let orbitalPresence: Double
        let surfaceDetailPresence: Double
        let transitionCuePresence: Double
        let chromePresence: Double
    }

    nonisolated static func localMagnification(
        settled: CGFloat,
        gestureScale: CGFloat
    ) -> CGFloat {
        min(
            maximumLocalMagnification,
            max(minimumLocalMagnification, settled * gestureScale)
        )
    }

    nonisolated static func overviewProgress(
        settled: CGFloat,
        gestureScale: CGFloat
    ) -> Double {
        let raw = settled * gestureScale
        guard raw < minimumLocalMagnification else { return 0 }
        return eased(
            Double((minimumLocalMagnification - raw) / overviewTransitionTravel)
        )
    }

    nonisolated static func overviewReturnProgress(rawZoom: CGFloat) -> Double {
        let overshoot = max(0, rawZoom - maximumOverviewZoom)
        return eased(Double(overshoot / overviewReturnTravel))
    }

    nonisolated static func wideFieldProgress(magnification: CGFloat) -> Double {
        let span = 1 - minimumLocalMagnification
        guard span > 0 else { return 0 }
        return eased(Double((1 - magnification) / span))
    }

    nonisolated static func shouldCommit(_ progress: Double) -> Bool {
        progress >= overviewCommitProgress
    }

    nonisolated static func transitionVisuals(
        progress rawProgress: Double
    ) -> TransitionVisuals {
        let progress = min(1, max(0, rawProgress))
        let retreat = smoother(progress)
        let localPresence = 1 - eased((progress - 0.06) / 0.62)
        let globePresence = eased((progress - 0.015) / 0.64)

        // 对数插值更接近相机持续后退：大尺度阶段移动更快，临近完整地球时
        // 自然减速，不会在最后一段突然改变球体尺寸。
        let initialGlobeScale = 4.85
        let globeScale = exp(log(initialGlobeScale) * (1 - retreat))
        let remaining = 1 - retreat
        let cueIn = eased((progress - 0.05) / 0.22)
        let cueOut = 1 - eased((progress - 0.56) / 0.22)

        return TransitionVisuals(
            progress: progress,
            cameraRetreat: retreat,
            localSkyOpacity: localPresence,
            localSkyScale: CGFloat(1 - 0.17 * retreat),
            globeOpacity: globePresence,
            globeScale: CGFloat(globeScale),
            globeVerticalOffset: CGFloat(0.31 * pow(remaining, 1.28)),
            orbitalPresence: eased((progress - 0.17) / 0.63),
            surfaceDetailPresence: eased((progress - 0.29) / 0.56),
            transitionCuePresence: cueIn * cueOut,
            chromePresence: eased((progress - 0.7) / 0.27)
        )
    }

    /// 局部天空和地球使用错开的单一交叉溶解曲线：中段只允许一个空间成为
    /// 视觉主体，避免两个完整页面以高不透明度叠在一起。
    nonisolated static func globePresence(progress: Double) -> Double {
        transitionVisuals(progress: progress).globeOpacity
    }

    nonisolated static func localSkyPresence(progress: Double) -> Double {
        transitionVisuals(progress: progress).localSkyOpacity
    }

    nonisolated static func eased(_ value: Double) -> Double {
        let p = min(1, max(0, value))
        return p * p * (3 - 2 * p)
    }

    nonisolated private static func smoother(_ value: Double) -> Double {
        let p = min(1, max(0, value))
        return p * p * p * (p * (p * 6 - 15) + 10)
    }
}

/// 天球 → 屏幕投影。
///
/// gnomonic 切平面投影：把天球方向投到以设备视轴为法线的切平面上，
/// 按屏幕 roll 旋转对齐，线性映射到屏幕坐标。竖直 FOV ≈ 55°。
struct Projection {
    let pointing: Pointing
    let screenSize: CGSize
    /// 竖直视场角（弧度）。55° 贴近举起手机"取景"的直觉。
    static let baseVerticalFOV: Double = 55 * .pi / 180
    let verticalFOV: Double

    /// 同一帧会投影数千个目标。相机基向量、滚转三角函数和像素比例只与
    /// 当前指向及画布有关，因此在初始化时计算一次，不再为每颗目标重复计算。
    private let bore: simd_double3
    private let right: simd_double3
    private let up: simd_double3
    private let rollCos: Double
    private let rollSin: Double
    private let pixelScale: Double

    init(
        pointing: Pointing,
        screenSize: CGSize,
        verticalFOV: Double = Self.baseVerticalFOV
    ) {
        self.pointing = pointing
        self.screenSize = screenSize
        self.verticalFOV = verticalFOV
        bore = pointing.unitVector
        (right, up) = Self.screenBasis(for: bore)
        rollCos = cos(-pointing.roll)
        rollSin = sin(-pointing.roll)
        pixelScale = Double(screenSize.height) / 2 / tan(verticalFOV / 2)
    }

    /// 相机式倍率转视场角。使用正切关系而非直接除角度，保持真实透视比例。
    static func verticalFOV(forMagnification magnification: CGFloat) -> Double {
        let value = max(
            Double(ObservationScale.minimumLocalMagnification),
            Double(magnification)
        )
        return 2 * atan(tan(baseVerticalFOV / 2) / value)
    }

    /// 把长焦后的屏幕距离换算回 1× 下的等效角距，使捕捉环在不同倍率下
    /// 保持近似相同的屏幕半径；倍率越高，对准要求也相应更精细。
    static func captureAngle(
        for angularDistance: Double,
        magnification: CGFloat
    ) -> Double {
        let scale = max(
            Double(ObservationScale.minimumLocalMagnification),
            Double(magnification)
        )
        return atan(tan(angularDistance) * scale)
    }

    /// 渐隐区间：角距 60° 开始渐隐，70° 完全不可见。
    static let fadeStart: Double = 60 * .pi / 180
    static let fadeEnd: Double = 70 * .pi / 180

    struct Projected {
        var point: CGPoint
        /// 与视轴的角距（弧度）。
        var angularDistance: Double
        /// 视野渐隐系数 0..1（1 = 完全可见）。
        var visibility: Double
    }

    /// 屏幕中心指向目标的二维方向。可用于目标在视野外或设备背向目标时的边缘引导。
    struct ScreenDirection {
        /// 归一化屏幕向量：右为 +x，下为 +y。
        var vector: CGVector
        /// 目标与设备视轴的球面角距。
        var angularDistance: Double
    }

    /// 把一个 az/el 方向投到屏幕。返回 nil 表示在渐隐区之外。
    func project(azimuth: Double, elevation: Double) -> Projected? {
        let target = targetVector(azimuth: azimuth, elevation: elevation)
        let cosAngle = simd_dot(target, bore)
        let angle = acos(max(-1, min(1, cosAngle)))
        guard angle < Self.fadeEnd else { return nil }

        // gnomonic：切平面坐标 = 分量 / 沿视轴分量
        guard cosAngle > 1e-6 else { return nil } // 背向不投
        let x = simd_dot(target, right) / cosAngle
        let y = simd_dot(target, up) / cosAngle

        // 屏幕 roll 旋转
        let rx = x * rollCos - y * rollSin
        let ry = x * rollSin + y * rollCos

        // 线性映射：tan(FOV/2) 对应半屏高
        let px = Double(screenSize.width) / 2 + rx * pixelScale
        let py = Double(screenSize.height) / 2 - ry * pixelScale

        let visibility: Double
        if angle < Self.fadeStart {
            visibility = 1
        } else {
            visibility = 1 - (angle - Self.fadeStart) / (Self.fadeEnd - Self.fadeStart)
        }

        return Projected(
            point: CGPoint(x: px, y: py),
            angularDistance: angle,
            visibility: visibility
        )
    }

    /// 返回朝向任意目标的屏幕方向，不受 70° 点位投影视场限制。
    func screenDirection(azimuth: Double, elevation: Double) -> ScreenDirection? {
        let target = targetVector(azimuth: azimuth, elevation: elevation)
        let angle = acos(max(-1, min(1, simd_dot(target, bore))))

        let x = simd_dot(target, right)
        let y = simd_dot(target, up)
        let rx = x * rollCos - y * rollSin
        let ry = x * rollSin + y * rollCos
        let length = hypot(rx, ry)

        // 完全正对或完全背对时没有唯一的屏幕转向，交给中心点/继续转动处理。
        guard length > 1e-6 else { return nil }
        return ScreenDirection(
            vector: CGVector(dx: CGFloat(rx / length), dy: CGFloat(-ry / length)),
            angularDistance: angle
        )
    }

    /// 捕获状态机只需要目标与准星的球面角距，不需要完整屏幕坐标。单独入口避免
    /// 30Hz 捕获扫描重复执行透视映射和可见度计算。
    func angularDistance(azimuth: Double, elevation: Double) -> Double {
        acos(cosineOfAngularDistance(azimuth: azimuth, elevation: elevation))
    }

    /// 候选扫描先比较点积，只对最终最近目标执行一次 acos。数千颗目标以
    /// 30Hz 扫描时，这能显著降低主线程三角函数成本。
    func cosineOfAngularDistance(azimuth: Double, elevation: Double) -> Double {
        let target = targetVector(azimuth: azimuth, elevation: elevation)
        return max(-1, min(1, simd_dot(target, bore)))
    }

    private func targetVector(azimuth: Double, elevation: Double) -> simd_double3 {
        simd_double3(
            cos(elevation) * sin(azimuth),
            cos(elevation) * cos(azimuth),
            sin(elevation)
        )
    }

    /// 切平面基向量：right = bore × worldUp，up = right × bore。
    private static func screenBasis(
        for bore: simd_double3
    ) -> (right: simd_double3, up: simd_double3) {
        let worldUp = simd_double3(0, 0, 1)
        var right = simd_cross(bore, worldUp)
        if simd_length(right) < 1e-6 {
            // 指向天顶/天底：取北作为参考。
            right = simd_cross(bore, simd_double3(0, 1, 0))
        }
        right = simd_normalize(right)
        return (right, simd_normalize(simd_cross(right, bore)))
    }
}

/// 已锁定目标在主天空中的持续空间关系。几何计算与绘制分离，确保跨越边缘、
/// 档案附近和屏幕角落时仍使用同一套连续坐标，而不是切换成另一套导航箭头。
enum TargetRelationshipGeometry {

    struct Marker: Equatable {
        /// 画面内使用真实投影点；离开可用视场后连续钳制到边缘。
        let point: CGPoint
        /// 0 = 完整画面内标记，1 = 被边缘裁切的锁定信标。
        let edgeProgress: Double
        let isOffscreen: Bool
        /// 从边缘信标指向可用画面内部，只用于刻度朝向，不表达导航箭头。
        let inward: CGVector
    }

    struct Connection: Equatable {
        /// 目标被档案遮住时，起点退到档案外侧，避免连线穿过正文。
        let start: CGPoint
        let archiveAnchor: CGPoint
        let targetOccludedByArchive: Bool
        let length: CGFloat
    }

    /// 把目标的屏幕投影与任意方向统一为一个连续标记点。
    static func marker(
        projectedPoint: CGPoint?,
        direction: CGVector?,
        inside bounds: CGRect,
        edgeTransitionWidth: CGFloat = 28
    ) -> Marker? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        if let projectedPoint, projectedPoint.x.isFinite, projectedPoint.y.isFinite {
            let clamped = CGPoint(
                x: min(bounds.maxX, max(bounds.minX, projectedPoint.x)),
                y: min(bounds.maxY, max(bounds.minY, projectedPoint.y))
            )
            let outside = projectedPoint.x < bounds.minX
                || projectedPoint.x > bounds.maxX
                || projectedPoint.y < bounds.minY
                || projectedPoint.y > bounds.maxY
            let edgeDistance = min(
                min(clamped.x - bounds.minX, bounds.maxX - clamped.x),
                min(clamped.y - bounds.minY, bounds.maxY - clamped.y)
            )
            let edgeProgress = outside
                ? 1
                : smoothstep(
                    from: edgeTransitionWidth,
                    to: 0,
                    value: max(0, edgeDistance)
                )
            return Marker(
                point: outside ? clamped : projectedPoint,
                edgeProgress: edgeProgress,
                isOffscreen: outside,
                inward: normalizedVector(from: clamped, to: center)
            )
        }

        guard let direction, let edgePoint = edgePoint(
            direction: direction,
            inside: bounds
        ) else { return nil }
        return Marker(
            point: edgePoint,
            edgeProgress: 1,
            isOffscreen: true,
            inward: normalizedVector(from: edgePoint, to: center)
        )
    }

    /// 最近边界点保证“目标 → 锚点”的直线在抵达锚点前始终位于档案矩形外。
    /// 目标落在档案背后时，改为一段外侧短引线，正文区域内不绘制连线。
    static func connection(from target: CGPoint, to archive: CGRect) -> Connection? {
        guard archive.width > 0, archive.height > 0,
              target.x.isFinite, target.y.isFinite else { return nil }

        if archive.contains(target) {
            let left = target.x - archive.minX
            let right = archive.maxX - target.x
            let top = target.y - archive.minY
            let bottom = archive.maxY - target.y
            let minimum = min(min(left, right), min(top, bottom))

            let anchor: CGPoint
            let outward: CGVector
            if minimum == left {
                anchor = CGPoint(x: archive.minX, y: target.y)
                outward = CGVector(dx: -1, dy: 0)
            } else if minimum == right {
                anchor = CGPoint(x: archive.maxX, y: target.y)
                outward = CGVector(dx: 1, dy: 0)
            } else if minimum == top {
                anchor = CGPoint(x: target.x, y: archive.minY)
                outward = CGVector(dx: 0, dy: -1)
            } else {
                anchor = CGPoint(x: target.x, y: archive.maxY)
                outward = CGVector(dx: 0, dy: 1)
            }
            let start = CGPoint(
                x: anchor.x + outward.dx * 11,
                y: anchor.y + outward.dy * 11
            )
            return Connection(
                start: start,
                archiveAnchor: anchor,
                targetOccludedByArchive: true,
                length: 11
            )
        }

        let anchor = CGPoint(
            x: min(archive.maxX, max(archive.minX, target.x)),
            y: min(archive.maxY, max(archive.minY, target.y))
        )
        return Connection(
            start: target,
            archiveAnchor: anchor,
            targetOccludedByArchive: false,
            length: hypot(target.x - anchor.x, target.y - anchor.y)
        )
    }

    static func edgePoint(direction: CGVector, inside bounds: CGRect) -> CGPoint? {
        let length = hypot(direction.dx, direction.dy)
        guard length > 1e-6 else { return nil }
        let ux = direction.dx / length
        let uy = direction.dy / length
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let horizontal = abs(ux) > 1e-6
            ? (ux > 0 ? bounds.maxX - center.x : center.x - bounds.minX) / abs(ux)
            : .greatestFiniteMagnitude
        let vertical = abs(uy) > 1e-6
            ? (uy > 0 ? bounds.maxY - center.y : center.y - bounds.minY) / abs(uy)
            : .greatestFiniteMagnitude
        let travel = min(horizontal, vertical)
        guard travel.isFinite else { return nil }
        return CGPoint(x: center.x + ux * travel, y: center.y + uy * travel)
    }

    private static func normalizedVector(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 1e-6 else { return .zero }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    /// 支持 from > to 的反向 smoothstep。
    private static func smoothstep(from: CGFloat, to: CGFloat, value: CGFloat) -> Double {
        guard from != to else { return value >= to ? 1 : 0 }
        let t = max(0, min(1, (value - from) / (to - from)))
        return Double(t * t * (3 - 2 * t))
    }
}
