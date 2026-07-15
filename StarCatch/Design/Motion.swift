import SwiftUI

/// StarCatch 动效规范。
///
/// 原则：操作反馈要快，场景转场要稳，仪式显影可以慢；无 spring/bounce。
enum Motion {

    /// 场景级转场：前段迅速建立层级，尾段留出柔和收束，不让二级页面显得迟滞。
    static let sceneTransition = Animation.timingCurve(0.18, 0.7, 0.2, 1, duration: 0.54)
    static let sceneTransitionDuration: Double = 0.54

    /// 临时界面与玻璃控件：展开快、尾段慢；收拢更果断。
    static let interfaceExpand = Animation.timingCurve(0.16, 0.76, 0.2, 1, duration: 0.36)
    static let interfaceExpandDuration: Double = 0.36
    static let interfaceCollapse = Animation.timingCurve(0.28, 0, 0.24, 1, duration: 0.24)
    static let interfaceCollapseDuration: Double = 0.24

    /// 镜头复位保留可读的空间运动，但不使用弹跳。
    static let fieldReset = Animation.timingCurve(0.18, 0.68, 0.2, 1, duration: 0.46)

    /// 手册页显影：阅读节奏，不让逐行 stagger 变成等待。
    static let manualReveal = Animation.timingCurve(0.32, 0, 0.2, 1, duration: 0.44)
    static let manualRevealDuration: Double = 0.44
    static let manualRevealStagger: Double = 0.035

    /// 启动页文字需要快速建立完整构图；停留负责从容，显影本身不制造等待。
    static let bootReveal = Animation.timingCurve(0.22, 0.72, 0.16, 1, duration: 0.36)
    static let bootRevealDuration: Double = 0.36

    /// 点位渐显（进入视野）：1.6s easeOut，绝不 pop。
    static let dotAppear = Animation.easeOut(duration: 1.6)
    static let dotAppearDuration: Double = 1.6

    /// 档案文字浮现：每行 1.2s，纯 fade + 2pt 上浮。不做打字机/乱码解算。
    static let archiveLine = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 1.2)
    static let archiveLineDuration: Double = 1.2
    /// 行间 stagger。
    static let archiveStagger: Double = 0.18
    /// 上浮距离。
    static let archiveRise: CGFloat = 2

    /// 锁定确认先在目标处完成，再把视觉关系交给档案。外扩回声只出现一次。
    static let lockConfirmationDuration: Double = 0.72

    /// 档案外壳先建立边界，正文随后快速、逐层显影。
    static let archiveSurface = Animation.timingCurve(0.18, 0.72, 0.2, 1, duration: 0.48)
    static let archiveSurfaceDuration: Double = 0.48
    static let archiveContentDelay: Double = 0.10
    static let archiveRevealLine = Animation.timingCurve(0.2, 0.68, 0.2, 1, duration: 0.62)
    static let archiveRevealDuration: Double = 0.62
    static let archiveRevealStagger: Double = 0.045

    /// 档案消隐：从末行向首行果断收束，必须早于 releasing 结束。
    static let archiveDismissLine = Animation.timingCurve(0.42, 0, 0.78, 0.22, duration: 0.34)
    static let archiveDismissDuration: Double = 0.34
    static let archiveDismissStagger: Double = 0.012
    static let archiveLineCount = 11

    /// 呼吸周期（锁定点位、signal 元素）：透明度 ±12%，仅此而已。
    static let breathPeriod: Double = 3.6
    static let breathAmplitude: Double = 0.12

    /// 星尘漂移速度（pt/s），持续线性。
    static let dustDrift: CGFloat = 0.8

    /// 主动归还：文字先收束，联系线向目标回撤，锁定结构最后松开。
    static let release = Animation.timingCurve(0.36, 0, 0.72, 0.24, duration: 0.86)
    static let releaseDuration: Double = 0.86

    /// 天空球跟随手指进入；松手后的镜头回退连续、可读、无弹跳。
    static let skyOverviewExit = Animation.timingCurve(0.2, 0.66, 0.22, 1, duration: 0.82)

    /// 独立全局星图是一次空间尺度切换，比时间轴预览更从容；显隐共用同一进度反向播放。
    static let skyOverviewMode = Animation.timingCurve(0.24, 0.06, 0.18, 1, duration: 1.02)
    static let skyOverviewModeDuration: Double = 1.02

    /// 扫描（进入捕捉态一次性）：2.4s 单次。
    static let scanDuration: Double = 2.4

    /// 信号连线在锁定确认之后迅速建立，尾段缓慢抵达档案边界。
    static let signalLineGrow = Animation.timingCurve(0.18, 0.66, 0.2, 1, duration: 0.78)
    static let signalLineGrowDuration: Double = 0.78

    /// 捕捉强度低通时间常数（角距 → 亮度的平滑）。
    static let strengthSmoothing: Double = 0.3

    /// 姿态 slerp 低通时间常数。
    static let pointingSmoothing: Double = 0.15

    /// 呼吸调制系数：sin 波 → 透明度乘数。
    static func breath(at time: TimeInterval, phase: Double = 0) -> Double {
        1.0 + breathAmplitude * sin((time / breathPeriod) * 2 * .pi + phase)
    }
}
