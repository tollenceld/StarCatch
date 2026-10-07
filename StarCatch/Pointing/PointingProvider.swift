import Combine
import Foundation
import simd

/// 设备指向：方位角/仰角（弧度）+ 屏幕 roll。
struct Pointing: Equatable {
    /// 方位角，弧度，0 = 真北，顺时针（东 = π/2）。
    var azimuth: Double
    /// 仰角，弧度，0 = 地平线，π/2 = 天顶。
    var elevation: Double
    /// 屏幕 roll，弧度 —— 设备绕视轴的旋转，用于对齐投影的"上"方向。
    var roll: Double

    /// 指向的 ENU 单位向量（x=东, y=北, z=上）。
    var unitVector: simd_double3 {
        simd_double3(
            cos(elevation) * sin(azimuth),
            cos(elevation) * cos(azimuth),
            sin(elevation)
        )
    }

    /// 初始指向：东南方中仰角 —— 北斗 G8 附近（模拟器演示锁定链路）。
    static let initial = Pointing(azimuth: 141.1 * .pi / 180, elevation: 34.5 * .pi / 180, roll: 0)

    var cameraRotation: simd_quatd {
        let forward = unitVector
        let (right, up) = Projection.screenBasis(for: forward)
        let screenRight = right * cos(roll) + up * sin(roll)
        let screenUp = up * cos(roll) - right * sin(roll)
        return simd_quatd(simd_double3x3(columns: (screenRight, screenUp, -forward)))
    }

    static func fromCameraRotation(_ rotation: simd_quatd) -> Pointing {
        let forward = rotation.act(simd_double3(0, 0, -1))
        let screenRight = rotation.act(simd_double3(1, 0, 0))
        let (right, up) = Projection.screenBasis(for: forward)
        return Pointing(azimuth: atan2(forward.x, forward.y),
                        elevation: asin(min(1, max(-1, forward.z))),
                        roll: atan2(simd_dot(screenRight, up), simd_dot(screenRight, right)))
    }
}

/// 指向精度/校准状态 —— 暴露成仪器叙事的一部分。
enum HeadingConfidence: Equatable {
    case trueNorth       // 真北参考系正常
    case uncalibrated    // 降级：任意参考系（HEADING: UNCALIBRATED）
    case manual          // 模拟器/手动指向模式
}

/// 指向服务是否真的在产出数据。`HeadingConfidence` 只描述方位参考系质量，
/// 不能区分“正在等待首帧”和“传感器已经失败”。
enum PointingAvailability: Equatable {
    case idle
    case starting
    case tracking
    case manual
    case unavailable
}

/// 指向源协议：真机 CoreMotion 或模拟器手势。
protocol PointingProvider: ObservableObject {
    var pointing: Pointing { get }
    var confidence: HeadingConfidence { get }
    func start()
    func stop()
}

/// Display navigation is independent of the sensor. A live device sample must never
/// move a manually browsed sky, but remains available as the destination of a return.
struct SkyPointingNavigation {
    enum Mode: Equatable { case following, browsing, returning }

    let deviceDriven: Bool
    private(set) var mode: Mode
    private(set) var pointing: Pointing = .initial
    private(set) var availability: PointingAvailability = .idle
    private var devicePointing: Pointing?
    private var browseReference: Pointing?
    private var returnOrigin: Pointing?
    private var returnStarted: TimeInterval = 0
    static let returnDuration = Motion.fieldResetDuration

    var canSampleCapture: Bool {
        mode != .returning && (!deviceDriven || mode == .browsing || availability == .tracking)
    }

    init(deviceDriven: Bool) {
        self.deviceDriven = deviceDriven
        mode = deviceDriven ? .following : .browsing
        availability = deviceDriven ? .idle : .manual
    }

    mutating func ingestDevice(_ sample: Pointing, availability: PointingAvailability) {
        self.availability = availability
        devicePointing = availability == .tracking ? sample : nil
        if mode == .following, availability == .tracking { pointing = sample }
    }

    mutating func ingestManual(_ sample: Pointing) {
        if mode == .browsing { pointing = sample }
    }

    /// Returns the exact display pose used to seed the drag provider, including roll.
    mutating func beginBrowsing() -> Pointing {
        if browseReference == nil { browseReference = pointing }
        mode = .browsing
        returnOrigin = nil
        return pointing
    }

    @discardableResult
    mutating func recenter(at time: TimeInterval, reducedMotion: Bool) -> Bool {
        guard let target = target else { return false }
        if reducedMotion {
            pointing = target
            mode = deviceDriven ? .following : .browsing
            browseReference = nil
            returnOrigin = nil
        } else {
            returnOrigin = pointing
            returnStarted = time
            mode = .returning
        }
        return true
    }

    mutating func advance(at time: TimeInterval) {
        guard mode == .returning, let origin = returnOrigin else { return }
        guard let target else {
            // A sensor failure cannot hand the camera back to an obsolete pose.
            mode = .browsing
            returnOrigin = nil
            return
        }
        let progress = min(1, max(0, (time - returnStarted) / Self.returnDuration))
        let eased = progress * progress * (3 - 2 * progress)
        pointing = Self.interpolate(origin, target, progress: eased)
        if progress >= 1 {
            mode = deviceDriven ? .following : .browsing
            returnOrigin = nil
            browseReference = nil
        }
    }

    private var target: Pointing? {
        deviceDriven ? devicePointing : (browseReference ?? .initial)
    }

    /// Interpolating camera bases preserves roll and takes the short route across
    /// north. Unlike azimuth interpolation it remains well defined at the zenith.
    static func interpolate(_ from: Pointing, _ to: Pointing, progress: Double) -> Pointing {
        if progress <= 0 { return from }
        if progress >= 1 { return to }
        return Pointing.fromCameraRotation(simd_slerp(from.cameraRotation, to.cameraRotation, progress))
    }
}
