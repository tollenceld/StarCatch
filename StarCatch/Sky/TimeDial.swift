import SwiftUI

/// 时间坐标仪 —— 仅在全局星图下缘出现的时间观测模块。
///
/// 水平拖动改变观测时刻：向左回溯，向右抵达未来。中央读针固定，刻度与整片天空
/// 随时间移动。LIVE 下永久保留低强度拖动提示；“返回此刻”由时间轴上方的独立
/// 悬浮控制承担，避免把关键动作塞进刻度读数。
struct TimeDial: View {
    @ObservedObject var clock: SkyClock

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    /// 每 pt 对应的秒数。12s/pt：满屏一拖约 ±80 分钟，配合惯性可达数小时。
    static let secondsPerPoint: Double = 12

    /// 刻度间隔（秒）：细刻度 5 分钟，主刻度 30 分钟。
    private static let minorTick: Double = 300
    private static let majorTick: Double = 1800
    private static let accessibilityStep: TimeInterval = 30 * 60

    @AppStorage("timeDialHasInteracted") private var hasInteracted = false
    @State private var dragging = false
    @State private var lastDragX: CGFloat = 0

    var body: some View {
        VStack(spacing: 2) {
            readout
            ruler
                .frame(height: 44)
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)
        .padding(.bottom, 4)
        .background {
            LinearGradient(
                colors: [
                    Palette.voidBlack.opacity(0.84),
                    Palette.voidBlack.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    Palette.inkFaint.opacity(
                        dragging || !clock.isLive ? 0.54 : Palette.Level.functionalDivider
                    )
                )
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        // 时间轴位于天空拖拽层之上，优先接收横向手势，避免被“移动准星”吞掉。
        .highPriorityGesture(dragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间坐标")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("左右拖动时间，或上下轻扫调整三十分钟")
        .accessibilityAdjustableAction { direction in
            markInteracted()
            switch direction {
            case .increment:
                clock.scrub(by: Self.accessibilityStep)
            case .decrement:
                clock.scrub(by: -Self.accessibilityStep)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: "返回此刻") {
            returnToLive()
        }
        .animation(.easeOut(duration: 0.8), value: clock.isLive)
        .animation(.easeOut(duration: 0.8), value: hasInteracted)
    }

    // MARK: - 紧凑读数

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            dragHint

            Spacer(minLength: 6)

            Text("完整范围  ±24H")
                .font(Typography.statusTag)
                .tracking(0.7)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                .lineLimit(1)

            Spacer(minLength: 6)

            timeStatus
        }
        .frame(minHeight: 20)
    }

    private var timeStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Palette.signal.opacity(clock.isLive ? 0.76 : 0.46))
                .frame(width: 4, height: 4)

            Text(clock.relativeOffsetLabel)
                .font(Typography.statusTag)
                .tracking(clock.isLive ? Typography.statusTagTracking : 0.7)
                .foregroundStyle(
                    (clock.isLive ? Palette.inkMid : Palette.signal)
                        .opacity(clock.isLive ? Palette.Level.present : 0.82)
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var dragHint: some View {
        HStack(spacing: 5) {
            Text("‹")
            Text(hasInteracted ? "拖动" : "拖动时间")
            Text("›")
        }
        .font(Typography.statusTag)
        .tracking(Typography.statusTagTracking)
        .foregroundStyle(
            Palette.inkLow.opacity(
                hasInteracted ? Palette.Level.readableSecondary : Palette.Level.present
            )
        )
        .allowsHitTesting(false)
    }

    private var accessibilityValue: String {
        clock.isLive ? "实时，\(clock.utcLabel())" : "\(clock.offsetLabel)，\(clock.utcLabel())"
    }

    // MARK: - 刻度

    private var ruler: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let baselineY = size.height * 0.61
            let pxPerSecond = 1.0 / Self.secondsPerPoint
            let shift = clock.offset * pxPerSecond
            let halfWindow = Double(size.width) / 2 * Self.secondsPerPoint
            let activity: Double = clock.isLive && !dragging ? 0.9 : 1.0

            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: baselineY))
            baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
            context.stroke(
                baseline,
                with: .color(Palette.inkLow.opacity(0.46 * activity)),
                style: StrokeStyle(lineWidth: 0.72, lineCap: .round)
            )

            var t = floor((clock.offset - halfWindow) / Self.minorTick) * Self.minorTick
            while t <= clock.offset + halfWindow {
                let x = midX + (t * pxPerSecond - shift)
                let isMajor = t.truncatingRemainder(dividingBy: Self.majorTick) == 0
                let height: CGFloat = isMajor ? 25 : 13
                let alpha = (isMajor ? 0.82 : 0.62) * activity
                let tint = isMajor ? Palette.inkMid : Palette.inkLow
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: baselineY - height / 2))
                tick.addLine(to: CGPoint(x: x, y: baselineY + height / 2))
                context.stroke(
                    tick,
                    with: .color(tint.opacity(alpha)),
                    style: StrokeStyle(lineWidth: isMajor ? 0.86 : 0.66, lineCap: .round)
                )
                t += Self.minorTick
            }

            // LIVE 零点会随时间偏移离开中央，作为回到现实的空间参照。
            let zeroX = midX - shift
            if zeroX >= -4, zeroX <= size.width + 4 {
                var zero = Path()
                zero.move(to: CGPoint(x: zeroX, y: baselineY - 15))
                zero.addLine(to: CGPoint(x: zeroX, y: baselineY + 15))
                context.stroke(
                    zero,
                    with: .color(Palette.signal.opacity(0.62 * activity)),
                    style: StrokeStyle(lineWidth: 0.78, lineCap: .round)
                )
            }

            // 固定读针与菱形读数点：这是可调仪器，而非装饰性分隔线。
            var needle = Path()
            needle.move(to: CGPoint(x: midX, y: baselineY - 19))
            needle.addLine(to: CGPoint(x: midX, y: baselineY + 19))
            context.stroke(
                needle,
                with: .color(Palette.inkHigh.opacity(clock.isLive ? 0.66 : 0.84)),
                style: StrokeStyle(lineWidth: 1.05, lineCap: .round)
            )

            let handleRect = CGRect(
                x: midX - 7,
                y: baselineY - 7,
                width: 14,
                height: 14
            )
            context.stroke(
                Path(ellipseIn: handleRect),
                with: .color(Palette.signal.opacity(clock.isLive ? 0.34 : 0.46)),
                style: StrokeStyle(lineWidth: 0.72)
            )

            var marker = Path()
            marker.move(to: CGPoint(x: midX, y: baselineY - 5))
            marker.addLine(to: CGPoint(x: midX + 5, y: baselineY))
            marker.addLine(to: CGPoint(x: midX, y: baselineY + 5))
            marker.addLine(to: CGPoint(x: midX - 5, y: baselineY))
            marker.closeSubpath()
            context.fill(marker, with: .color(Palette.signal.opacity(0.82)))
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                let halfWindow = Double(proxy.size.width) / 2 * Self.secondsPerPoint
                let scale = scaleWindowLabel(seconds: halfWindow)
                HStack {
                    Text("可见 −\(scale)")
                    Spacer()
                    Text("+\(scale) 可见")
                }
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Palette.inkLow.opacity(0.68))
                .padding(.horizontal, 2)
                .allowsHitTesting(false)
            }
        }
    }

    private func scaleWindowLabel(seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes == 0 ? "\(hours) H" : "\(hours)H \(minutes)M"
        }
        return "\(totalMinutes) MIN"
    }

    // MARK: - 拖动

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    lastDragX = 0
                    clock.cancelMomentum()
                    markInteracted()
                }
                // 镜头进度直接跟手，不再等待 offset 触发条件视图替换。
                clock.updateScrubPresentation(
                    translationPoints: Double(value.translation.width)
                )
                let deltaX = value.translation.width - lastDragX
                lastDragX = value.translation.width
                // 方向与屏幕语义一致：左 = 过去，右 = 未来。
                clock.scrub(by: Double(deltaX) * Self.secondsPerPoint)
            }
            .onEnded { value in
                dragging = false
                lastDragX = 0
                let shouldSnapToLive = abs(clock.offset) < 90
                withAnimation(overviewExitAnimation) {
                    if shouldSnapToLive {
                        clock.returnToLive()
                    } else {
                        clock.endScrubPresentation()
                    }
                }
                if !shouldSnapToLive {
                    clock.endScrub(
                        velocitySecondsPerSecond: Double(value.velocity.width) * Self.secondsPerPoint
                    )
                }
            }
    }

    private func markInteracted() {
        if !hasInteracted { hasInteracted = true }
    }

    private var overviewExitAnimation: Animation {
        reducedMotion || systemReducedMotion
            ? .easeOut(duration: 0.16)
            : Motion.skyOverviewExit
    }

    private func returnToLive() {
        withAnimation(overviewExitAnimation) {
            clock.returnToLive()
        }
    }
}
