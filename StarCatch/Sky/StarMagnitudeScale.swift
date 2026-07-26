import Foundation

/// 星等判定：把真实的轨道几何翻译成屏幕上的亮度差。
///
/// 设计意图是"透镜"而不是图例 —— 用户看到的密度来自数千个几乎不可见的暗点，
/// 而可辨认的亮点必须是少数。因此判定完全由物理量驱动（距离为主、仰角次之），
/// 不由类别或星座决定；类别只影响那一层极弱的外晕颜色。
enum StarMagnitudeScale {

    /// LEO 近距离目标约 400–1200km，GEO 约 36000km。距离跨两个数量级，
    /// 所以用对数刻度而不是线性刻度，否则整片 GEO 带会塌进同一档。
    private static let nearRangeKm: Double = 700
    private static let farRangeKm: Double = 40000

    /// 归一化视亮度 0..1。距离越近越亮；接近地平线时因大气路径与遮挡感而压暗。
    static func brightness(rangeKm: Double, elevation: Double) -> Double {
        let clampedRange = min(max(rangeKm, nearRangeKm), farRangeKm)
        let logNear = log(nearRangeKm)
        let logFar = log(farRangeKm)
        // 1 = 最近，0 = 最远。
        let distanceTerm = 1 - (log(clampedRange) - logNear) / (logFar - logNear)

        // 地平线附近压暗，天顶不加成：只做衰减，避免整片天空整体变亮。
        let degrees = elevation * 180 / .pi
        let horizonTerm = min(1, max(0.35, degrees / 22))

        return min(1, max(0, distanceTerm * horizonTerm))
    }

    /// 亮度 → 四档星等。阈值刻意偏高：只有最亮的少数目标能进入 mid / bright，
    /// 天空的大部分保持在 faint 底噪层。
    static func magnitude(
        rangeKm: Double,
        elevation: Double,
        isCurated: Bool
    ) -> SkyRenderer.StarMagnitude {
        let value = brightness(rangeKm: rangeKm, elevation: elevation)

        // 有可读档案的目标至少进入 low，保证"能点开的东西看得见"。
        let floor: SkyRenderer.StarMagnitude = isCurated ? .low : .faint

        let tier: SkyRenderer.StarMagnitude
        switch value {
        case 0.78...: tier = .bright
        case 0.56 ..< 0.78: tier = .mid
        case 0.30 ..< 0.56: tier = .low
        default: tier = .faint
        }

        return tier.rawValue >= floor.rawValue ? tier : floor
    }
}
