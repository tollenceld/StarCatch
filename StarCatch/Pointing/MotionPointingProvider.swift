import Combine
import CoreMotion
import Foundation
import simd

/// 真机指向源：CoreMotion 姿态 → 设备背面法线的 az/el + 屏幕 roll。
///
/// 使用 `.xTrueNorthZVertical` 参考系（X 指真北，需要定位服务算磁偏角）；
/// 定位不可用时降级 `.xArbitraryCorrectedZVertical` 并标记 uncalibrated。
/// 四元数经 slerp 低通（τ = Motion.pointingSmoothing）防抖。
final class MotionPointingProvider: PointingProvider {
    @Published private(set) var pointing: Pointing = .initial
    @Published private(set) var confidence: HeadingConfidence = .uncalibrated
    @Published private(set) var availability: PointingAvailability = .idle

    private let manager = CMMotionManager()
    private var smoothed = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    private var hasSample = false
    private var usingTrueNorth = false

    func start() {
        start(prefersTrueNorth: true)
    }

    /// 定位尚未授权时先使用磁北参考系；授权变化后由会话重新选择真北。
    /// 这样首次进入不会在任意参考系中假装给出可用于观测的绝对方位。
    func start(prefersTrueNorth: Bool) {
        guard manager.isDeviceMotionAvailable else {
            availability = .unavailable
            confidence = .uncalibrated
            return
        }
        manager.stopDeviceMotionUpdates()
        hasSample = false
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        // 让系统在磁场需要校准时显示标准的设备转动提示，而不是继续假装高精度。
        manager.showsDeviceMovementDisplay = true

        let frame: CMAttitudeReferenceFrame
        let availableFrames = CMMotionManager.availableAttitudeReferenceFrames()
        if prefersTrueNorth, availableFrames.contains(.xTrueNorthZVertical) {
            frame = .xTrueNorthZVertical
            usingTrueNorth = true
        } else if availableFrames.contains(.xMagneticNorthZVertical) {
            frame = .xMagneticNorthZVertical
            usingTrueNorth = false
        } else {
            frame = .xArbitraryCorrectedZVertical
            usingTrueNorth = false
        }
        confidence = .uncalibrated
        availability = .starting

        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, error in
            guard let self else { return }
            if error != nil {
                self.setConfidence(.uncalibrated)
                self.setAvailability(.unavailable)
                return
            }
            guard let motion else { return }
            self.setConfidence(Self.confidence(
                usingTrueNorth: self.usingTrueNorth,
                magneticAccuracy: motion.magneticField.accuracy
            ))
            self.ingest(motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        hasSample = false
        availability = .idle
    }

    /// 真北参考系只是能力声明；只有磁场达到中/高校准质量时才报告可靠真北。
    static func confidence(
        usingTrueNorth: Bool,
        magneticAccuracy: CMMagneticFieldCalibrationAccuracy
    ) -> HeadingConfidence {
        guard usingTrueNorth else { return .uncalibrated }
        switch magneticAccuracy {
        case .medium, .high:
            return .trueNorth
        case .uncalibrated, .low:
            return .uncalibrated
        @unknown default:
            return .uncalibrated
        }
    }

    private func setConfidence(_ value: HeadingConfidence) {
        guard confidence != value else { return }
        confidence = value
    }

    private func setAvailability(_ value: PointingAvailability) {
        guard availability != value else { return }
        availability = value
    }

    private func ingest(_ motion: CMDeviceMotion) {
        let q = motion.attitude.quaternion
        let raw = simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w)

        if hasSample {
            // slerp 低通：dt 取更新周期，τ = pointingSmoothing
            let dt = manager.deviceMotionUpdateInterval
            let alpha = 1 - exp(-dt / Motion.pointingSmoothing)
            smoothed = simd_slerp(smoothed, raw, alpha)
        } else {
            smoothed = raw
            hasSample = true
        }

        pointing = Self.pointing(from: smoothed)
        setAvailability(.tracking)
    }

    /// 姿态四元数 → Pointing。
    ///
    /// 参考系约定（xTrueNorthZVertical）：设备坐标 X 右、Y 上（竖屏顶部）、Z 出屏；
    /// 世界坐标 X 真北、Z 竖直向上（Y 由右手系定 = 西）。
    /// 举起手机"取景"时视轴是屏幕背面法线 = 设备 -Z。
    static func pointing(from q: simd_quatd) -> Pointing {
        // 设备 -Z（视轴）在世界系中的方向
        let bore = q.act(simd_double3(0, 0, -1))
        // 世界系：X 北、Y 西、Z 上 → 转 ENU（x 东 = -Y, y 北 = X, z 上 = Z）
        let east = -bore.y
        let north = bore.x
        let up = bore.z

        let azimuth = atan2(east, north)
        let elevation = asin(max(-1, min(1, up)))

        // 屏幕 roll：设备 Y 轴（屏幕上方向）投到视轴垂直平面，与"天空上方向"的夹角
        let deviceUp = q.act(simd_double3(0, 1, 0))
        let boreENU = simd_double3(east, north, up)
        let worldUp = simd_double3(0, 0, 1)
        let devUpENU = simd_double3(-deviceUp.y, deviceUp.x, deviceUp.z)
        let projUp = devUpENU - boreENU * simd_dot(devUpENU, boreENU)
        let projLen = simd_length(projUp)
        var roll = 0.0
        if projLen > 1e-6 {
            var reference = worldUp - boreENU * simd_dot(worldUp, boreENU)
            // 正对天顶/天底时，“世界向上”与视轴重合，不能再作为屏幕上方向。
            // 改用真北在视平面中的投影，避免 normalize(0) 产生 NaN 并让整片天空消失。
            if simd_length(reference) < 1e-6 {
                let worldNorth = simd_double3(0, 1, 0)
                reference = worldNorth - boreENU * simd_dot(worldNorth, boreENU)
            }
            let refUp = simd_normalize(reference)
            let pu = projUp / projLen
            let cross = simd_cross(refUp, pu)
            roll = atan2(simd_dot(cross, boreENU), simd_dot(refUp, pu))
        }

        return Pointing(azimuth: azimuth, elevation: elevation, roll: roll)
    }
}
