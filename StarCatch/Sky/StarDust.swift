import CoreGraphics
import Foundation

/// 确定性伪随机星尘场。
///
/// 星尘不是天文星表 —— 它是背景介质，最暗层的"假星点"。
/// 位置生成一次即固定（种子确定），渲染时整层缓慢平移并按指向做微视差。
struct StarDust {

    struct Grain {
        /// 归一化位置（0..1 平铺空间）。
        let position: CGPoint
        /// 半径 pt（0.4 ~ 1.1）。
        let radius: CGFloat
        /// 基础透明度（0.15 ~ 0.7，作用于 Palette.dust）。
        let alpha: Double
        /// 呼吸相位偏移，让少数颗粒有极慢的明暗起伏。
        let phase: Double
        /// 视差深度（0 = 无视差，1 = 最大视差）。
        let depth: CGFloat
    }

    let grains: [Grain]

    init(count: Int = 220, seed: UInt64 = 0x5EED_50AC) {
        var rng = SplitMix64(seed: seed)
        grains = (0 ..< count).map { _ in
            Grain(
                position: CGPoint(x: rng.nextUnit(), y: rng.nextUnit()),
                radius: 0.5 + 0.9 * pow(rng.nextUnit(), 2.2), // 大颗粒稀少
                alpha: 0.3 + 0.7 * pow(rng.nextUnit(), 1.6),
                phase: rng.nextUnit() * 2 * .pi,
                depth: 0.3 + 0.7 * rng.nextUnit()
            )
        }
    }

    /// 计算某颗粒在给定时刻/画布尺寸/视差偏移下的屏幕位置。
    /// 平铺空间比画布各向大 1.4 倍，漂移与视差后按模回绕。
    func screenPosition(
        of grain: Grain,
        time: TimeInterval,
        canvasSize: CGSize,
        parallax: CGPoint = .zero
    ) -> CGPoint {
        let tileW = canvasSize.width * 1.4
        let tileH = canvasSize.height * 1.4
        let driftX = CGFloat(time) * Motion.dustDrift * 0.35
        let driftY = CGFloat(time) * Motion.dustDrift

        var x = grain.position.x * tileW + driftX + parallax.x * grain.depth
        var y = grain.position.y * tileH + driftY + parallax.y * grain.depth
        x = x.truncatingRemainder(dividingBy: tileW)
        y = y.truncatingRemainder(dividingBy: tileH)
        if x < 0 { x += tileW }
        if y < 0 { y += tileH }
        // 平铺空间居中对齐画布
        return CGPoint(x: x - (tileW - canvasSize.width) / 2,
                       y: y - (tileH - canvasSize.height) / 2)
    }
}

/// SplitMix64 —— 可复现的轻量伪随机源。
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<1 的均匀分布。
    mutating func nextUnit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}
