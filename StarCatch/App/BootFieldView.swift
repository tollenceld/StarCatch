import SwiftUI

/// 加载期的仪器自检层。它不是装饰动画，而是把"仪器正在对准真实天空"这件事
/// 演一遍：真空 → 星野从暗处凝聚 → 一条极慢的扫描线掠过 → 中心光阑收拢成准星。
///
/// 全程无 spring、无进度条、无打字机。所有运动都是单向线性或长缓动，因此在
/// 冷启动的低帧率下也不会出现顿挫感。
struct BootFieldView: View {
    /// 0...1 由宿主推进；用同一进度驱动全部图层，保证它们始终同相。
    let progress: Double
    /// 降级模式下只画一张静态星野。
    let suppressMotion: Bool

    private static let grainCount = 190

    var body: some View {
        if suppressMotion {
            Canvas { context, size in
                draw(context, size: size, progress: 1, time: 0)
            }
            .accessibilityHidden(true)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    draw(context, size: size, progress: progress, time: time)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func draw(
        _ context: GraphicsContext,
        size: CGSize,
        progress: Double,
        time: TimeInterval
    ) {
        let p = min(1, max(0, progress))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height)

        starField(context, size: size, progress: p, time: time)
        aperture(context, center: center, radius: radius, progress: p)
        if p > 0.18, p < 0.98 {
            sweep(context, size: size, progress: p)
        }
    }

    /// 星野按各自的相位分批浮现：不是整片同时亮起，而像长曝光逐渐积累信号。
    private func starField(
        _ context: GraphicsContext,
        size: CGSize,
        progress: Double,
        time: TimeInterval
    ) {
        for index in 0 ..< Self.grainCount {
            let seed = Double(index)
            // 固定伪随机分布：同一次启动内稳定，不同位置互不相关。
            let x = fract(sin(seed * 12.9898) * 43758.5453) * size.width
            let y = fract(sin(seed * 78.233) * 26758.1234) * size.height
            let threshold = fract(sin(seed * 41.117) * 18921.7231)

            // 每颗星有自己的出现时刻，进度越过它之后才开始积累亮度。
            let local = (progress - threshold * 0.72) / 0.28
            guard local > 0 else { continue }
            let accumulation = min(1, local)

            let magnitude = fract(sin(seed * 93.981) * 31771.4412)
            let baseAlpha = magnitude > 0.93
                ? Palette.Level.faint
                : (magnitude > 0.72 ? Palette.Level.ghost : Palette.Level.ghost * 0.55)
            let radius: CGFloat = magnitude > 0.93 ? 0.95 : 0.55

            // 极缓呼吸只给最亮的少数，避免整片闪烁。
            let breath = magnitude > 0.93
                ? 1.0 + 0.16 * sin(time / 4.2 * 2 * .pi + seed)
                : 1.0

            let color: Color = magnitude > 0.93 ? Palette.inkLow : Palette.dust
            context.fill(
                Path(ellipseIn: CGRect(
                    x: x - radius, y: y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(color.opacity(baseAlpha * accumulation * breath))
            )
        }
    }

    /// 光阑：一圈极细的弧从视野外向中心收拢，收拢结束时正好留下准星的四段结构。
    private func aperture(
        _ context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        progress: Double
    ) {
        let eased = 1 - pow(1 - progress, 2.4)
        let ringRadius = radius * (0.62 - 0.42 * CGFloat(eased))
        let sweep = 26.0 + 34.0 * eased
        let alpha = (0.10 + 0.30 * eased) * min(1, progress / 0.12)

        for quadrant in 0 ..< 4 {
            let start = Angle.degrees(Double(quadrant) * 90 + 45 - sweep / 2)
            var arc = Path()
            arc.addArc(
                center: center,
                radius: ringRadius,
                startAngle: start,
                endAngle: start + .degrees(sweep),
                clockwise: false
            )
            context.stroke(
                arc,
                with: .color(Palette.inkFaint.opacity(alpha)),
                style: StrokeStyle(lineWidth: 0.5, lineCap: .butt)
            )
        }

        // 中心信号点最后出现，确认仪器已就位。
        if progress > 0.62 {
            let coreProgress = (progress - 0.62) / 0.38
            let coreRadius: CGFloat = 1.5
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - coreRadius, y: center.y - coreRadius,
                    width: coreRadius * 2, height: coreRadius * 2
                )),
                with: .color(Palette.signal.opacity(0.52 * coreProgress))
            )
        }
    }

    /// 一次性扫描线：整场只掠过一遍，两端渐弱，明确表达"已完成一次全天扫描"。
    private func sweep(_ context: GraphicsContext, size: CGSize, progress: Double) {
        let travel = (progress - 0.18) / 0.80
        let y = size.height * CGFloat(travel)
        let fade = sin(min(1, max(0, travel)) * .pi)
        let gradient = Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Palette.signal.opacity(0.20 * fade), location: 0.5),
            .init(color: .clear, location: 1),
        ])
        context.fill(
            Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: y),
                endPoint: CGPoint(x: size.width, y: y)
            )
        )
    }

    private func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}
