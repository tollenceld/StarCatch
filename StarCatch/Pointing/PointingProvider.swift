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
