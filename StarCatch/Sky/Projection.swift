import CoreGraphics
import Foundation
import simd

/// 天球 → 屏幕投影。
///
/// gnomonic 切平面投影：把天球方向投到以设备视轴为法线的切平面上，
/// 按屏幕 roll 旋转对齐，线性映射到屏幕坐标。竖直 FOV ≈ 55°。
struct Projection {
    var pointing: Pointing
    var screenSize: CGSize
    /// 竖直视场角（弧度）。55° 贴近举起手机"取景"的直觉。
    static let baseVerticalFOV: Double = 55 * .pi / 180
    var verticalFOV: Double = Self.baseVerticalFOV

    /// 相机式倍率转视场角。使用正切关系而非直接除角度，保持真实透视比例。
    static func verticalFOV(forMagnification magnification: CGFloat) -> Double {
        let value = max(1, Double(magnification))
        return 2 * atan(tan(baseVerticalFOV / 2) / value)
    }

    /// 把长焦后的屏幕距离换算回 1× 下的等效角距，使捕捉环在不同倍率下
    /// 保持近似相同的屏幕半径；倍率越高，对准要求也相应更精细。
    static func captureAngle(
        for angularDistance: Double,
        magnification: CGFloat
    ) -> Double {
        atan(tan(angularDistance) * max(1, Double(magnification)))
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
        let bore = pointing.unitVector
        let cosAngle = simd_dot(target, bore)
        let angle = acos(max(-1, min(1, cosAngle)))
        guard angle < Self.fadeEnd else { return nil }

        let (right, up) = screenBasis(for: bore)

        // gnomonic：切平面坐标 = 分量 / 沿视轴分量
        guard cosAngle > 1e-6 else { return nil } // 背向不投
        let x = simd_dot(target, right) / cosAngle
        let y = simd_dot(target, up) / cosAngle

        // 屏幕 roll 旋转
        let cr = cos(-pointing.roll)
        let sr = sin(-pointing.roll)
        let rx = x * cr - y * sr
        let ry = x * sr + y * cr

        // 线性映射：tan(FOV/2) 对应半屏高
        let scale = Double(screenSize.height) / 2 / tan(verticalFOV / 2)
        let px = Double(screenSize.width) / 2 + rx * scale
        let py = Double(screenSize.height) / 2 - ry * scale

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
        let bore = pointing.unitVector
        let angle = acos(max(-1, min(1, simd_dot(target, bore))))
        let (right, up) = screenBasis(for: bore)

        let x = simd_dot(target, right)
        let y = simd_dot(target, up)
        let cr = cos(-pointing.roll)
        let sr = sin(-pointing.roll)
        let rx = x * cr - y * sr
        let ry = x * sr + y * cr
        let length = hypot(rx, ry)

        // 完全正对或完全背对时没有唯一的屏幕转向，交给中心点/继续转动处理。
        guard length > 1e-6 else { return nil }
        return ScreenDirection(
            vector: CGVector(dx: CGFloat(rx / length), dy: CGFloat(-ry / length)),
            angularDistance: angle
        )
    }

    private func targetVector(azimuth: Double, elevation: Double) -> simd_double3 {
        simd_double3(
            cos(elevation) * sin(azimuth),
            cos(elevation) * cos(azimuth),
            sin(elevation)
        )
    }

    /// 切平面基向量：right = bore × worldUp，up = right × bore。
    private func screenBasis(for bore: simd_double3) -> (right: simd_double3, up: simd_double3) {
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
