import CoreGraphics
import Foundation

/// 确定性伪随机星尘场。
///
/// 星尘不是天文星表 —— 它是背景介质，最暗层的"假星点"。
/// 位置生成一次即固定（种子确定），主天空中以光学视场尺度跟随设备指向，
/// 不使用深度视差，因此任何可见点都会随相机转动移出屏幕。
struct StarDust {

    private static let tileScale: CGFloat = 1.55
    /// 水平一周铺设 9 个稳定星场块，既接近 55° 视场的光学位移，
    /// 又保证方位角在 ±π 回绕时图案无缝连续。
    private static let horizontalCycleCount: CGFloat = 9

    struct SkyTransform {
        let offset: CGPoint
        let rotationCos: CGFloat
        let rotationSin: CGFloat

        static let identity = SkyTransform(
            offset: .zero,
            rotationCos: 1,
            rotationSin: 0
        )
    }

    struct Grain {
        /// 归一化位置（0..1 平铺空间）。
        let position: CGPoint
        /// 半径 pt（0.4 ~ 1.1）。
        let radius: CGFloat
        /// 基础透明度（0.15 ~ 0.7，作用于 Palette.dust）。
        let alpha: Double
        /// 保留的稳定相位，可供未来局部响应使用；普通观测中不驱动整层呼吸。
        let phase: Double
    }

    let grains: [Grain]

    init(count: Int = 150, seed: UInt64 = 0x5EED_50AC) {
        var rng = SplitMix64(seed: seed)
        grains = (0 ..< count).map { _ in
            Grain(
                position: CGPoint(x: rng.nextUnit(), y: rng.nextUnit()),
                radius: 0.5 + 0.9 * pow(rng.nextUnit(), 2.2), // 大颗粒稀少
                alpha: 0.3 + 0.7 * pow(rng.nextUnit(), 1.6),
                phase: rng.nextUnit() * 2 * .pi
            )
        }
    }

    /// 将当前设备指向转换为整层星场的光学位移。转换每帧只计算一次，
    /// 150 颗点仍使用同一批 Canvas 绘制，不增加图层数。
    static func skyTransform(
        pointing: Pointing,
        canvasSize: CGSize,
        verticalFOV: Double
    ) -> SkyTransform {
        let tileWidth = canvasSize.width * tileScale
        let horizontalScale = tileWidth * horizontalCycleCount / (2 * .pi)
        let verticalScale = canvasSize.height / 2
            / CGFloat(tan(verticalFOV / 2))
        return SkyTransform(
            offset: CGPoint(
                x: -CGFloat(pointing.azimuth) * horizontalScale,
                y: CGFloat(pointing.elevation) * verticalScale
            ),
            rotationCos: CGFloat(cos(-pointing.roll)),
            rotationSin: CGFloat(sin(-pointing.roll))
        )
    }

    /// 计算某颗粒在平铺星场中的屏幕位置。所有颗粒共用同一个变换，
    /// 不再用不同 depth 制造看似黏在玻璃上的慢速点。
    func screenPosition(
        of grain: Grain,
        canvasSize: CGSize,
        transform: SkyTransform = .identity
    ) -> CGPoint {
        let tileW = canvasSize.width * Self.tileScale
        let tileH = canvasSize.height * Self.tileScale

        var x = grain.position.x * tileW + transform.offset.x
        var y = grain.position.y * tileH + transform.offset.y
        x = x.truncatingRemainder(dividingBy: tileW)
        y = y.truncatingRemainder(dividingBy: tileH)
        if x < 0 { x += tileW }
        if y < 0 { y += tileH }
        // 平铺空间居中对齐画布，再以准星为中心应用设备 roll。
        let unrotated = CGPoint(
            x: x - (tileW - canvasSize.width) / 2,
            y: y - (tileH - canvasSize.height) / 2
        )
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let dx = unrotated.x - center.x
        let dy = unrotated.y - center.y
        return CGPoint(
            x: center.x + dx * transform.rotationCos - dy * transform.rotationSin,
            y: center.y + dx * transform.rotationSin + dy * transform.rotationCos
        )
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
