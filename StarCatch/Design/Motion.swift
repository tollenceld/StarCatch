import SwiftUI

/// StarCatch 动效规范。
///
/// 原则：操作反馈要快，场景转场要稳，仪式显影可以慢；无 spring/bounce。
enum Motion {

    /// 场景级转场：前段迅速建立层级，尾段留出柔和收束，不让二级页面显得迟滞。
    static let sceneTransition = Animation.timingCurve(0.18, 0.7, 0.2, 1, duration: 0.54)

    /// 临时界面与玻璃控件：展开快、尾段慢；收拢更果断。
    static let interfaceExpand = Animation.timingCurve(0.16, 0.76, 0.2, 1, duration: 0.36)
    static let interfaceCollapse = Animation.timingCurve(0.28, 0, 0.24, 1, duration: 0.24)
    static let interfaceCollapseDuration: Double = 0.24

    /// 镜头复位保留可读的空间运动，但不使用弹跳。
    static let fieldReset = Animation.timingCurve(0.18, 0.68, 0.2, 1, duration: 0.46)

    /// 手册页显影：阅读节奏，不让逐行 stagger 变成等待。
    static let manualReveal = Animation.timingCurve(0.32, 0, 0.2, 1, duration: 0.44)
    static let manualRevealStagger: Double = 0.035

    /// 手册段落上浮距离。
    static let archiveRise: CGFloat = 2

    /// 锁定确认先在目标处完成，再把视觉关系交给档案。外扩回声只出现一次。
    static let lockConfirmationDuration: Double = 0.72
    /// 顶部“目标锁定”只承担瞬时确认，随后收敛为锁定图标和目标编号。
    static let lockStatusHoldDuration: Double = 1.15

    /// 启动准星与主天空第一帧的交接。启动层和天空层在同一中心点短暂共存。
    static let bootHandoff = Animation.timingCurve(0.2, 0.72, 0.2, 1, duration: 0.45)

    /// 呼吸周期（锁定点位、signal 元素）：透明度 ±12%，仅此而已。
    static let breathPeriod: Double = 3.6
    static let breathAmplitude: Double = 0.12

    /// 主动归还：文字先收束，联系线向目标回撤，锁定结构最后松开。
    static let release = Animation.timingCurve(0.36, 0, 0.72, 0.24, duration: 0.86)
    static let releaseDuration: Double = 0.86

    /// 天空球跟随手指进入；松手后的镜头回退连续、可读、无弹跳。
    static let skyOverviewExit = Animation.timingCurve(0.2, 0.66, 0.22, 1, duration: 0.82)

    /// 独立全局星图是一次空间尺度切换，比时间轴预览更从容；显隐共用同一进度反向播放。
    static let skyOverviewMode = Animation.timingCurve(0.18, 0.72, 0.18, 1, duration: 0.82)
    static let skyOverviewModeDuration: Double = 0.82

    /// 用户没有越过尺度门槛时，天空穹顶带一点阻力退回最广局部视野。
    static let scaleThresholdReturn = Animation.timingCurve(0.3, 0, 0.22, 1, duration: 0.34)
    static let scaleThresholdReturnDuration: Double = 0.34

    /// 扫描（进入捕捉态一次性）：2.4s 单次。
    static let scanDuration: Double = 2.4

    /// 信号连线在锁定确认之后迅速建立，尾段缓慢抵达档案边界。
    static let signalLineGrow = Animation.timingCurve(0.18, 0.66, 0.2, 1, duration: 0.78)
    static let signalLineGrowDuration: Double = 0.78

    /// 捕捉强度低通时间常数（角距 → 亮度的平滑）。
    static let strengthSmoothing: Double = 0.3

    /// 呼吸调制系数：sin 波 → 透明度乘数。
    static func breath(at time: TimeInterval, phase: Double = 0) -> Double {
        1.0 + breathAmplitude * sin((time / breathPeriod) * 2 * .pi + phase)
    }
}

/// 局部天空、三维地球和视场复位共用的空间阻尼参数。
///
/// 速度统一使用“每秒”单位；衰减采用指数模型，因此不同刷新率下的运动距离一致。
/// 边界只衰减朝外的速度，不产生反弹，保持仪器而非游戏镜头的质量感。
enum SpatialMotion {
    static let frameInterval: TimeInterval = 1.0 / 60.0
    static let dragYawSensitivity: Double = 0.0064
    static let dragPitchSensitivity: Double = 0.0058
    static let rotationDecay: Double = 3.9
    static let scaleDecay: Double = 5.4
    static let minimumAngularVelocity: Double = 0.01
    static let minimumScaleVelocity: Double = 0.009

    nonisolated static func decayFactor(
        rate: Double,
        deltaTime: TimeInterval
    ) -> Double {
        exp(-rate * max(0, deltaTime))
    }

    nonisolated static func limitedAngularVelocity(
        pointsPerSecond: CGFloat,
        sensitivity: Double
    ) -> Double {
        min(4.2, max(-4.2, Double(pointsPerSecond) * sensitivity))
    }

    nonisolated static func boundaryVelocityScale(
        value: Double,
        velocity: Double,
        lowerBound: Double,
        upperBound: Double,
        slowZone: Double
    ) -> Double {
        let distance: Double
        if velocity > 0 {
            distance = upperBound - value
        } else if velocity < 0 {
            distance = value - lowerBound
        } else {
            return 1
        }
        let progress = min(1, max(0, distance / max(0.0001, slowZone)))
        let eased = progress * progress * (3 - 2 * progress)
        return 0.12 + 0.88 * eased
    }

    nonisolated static func projectedScale(
        current: CGFloat,
        logarithmicVelocity: Double,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        let velocity = min(1.4, max(-1.4, logarithmicVelocity))
        let projected = current * CGFloat(exp(velocity / scaleDecay))
        return min(upperBound, max(lowerBound, projected))
    }

    nonisolated static func scaleSettleDuration(
        logarithmicVelocity: Double
    ) -> TimeInterval {
        min(0.46, max(0.18, abs(logarithmicVelocity) * 0.16 + 0.18))
    }
}
