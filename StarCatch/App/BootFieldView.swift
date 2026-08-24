import SwiftUI

/// 启动文字系统的纯值时间轴。
///
/// 首轮逐字完成模块确认；数据等待时间超过 3.2 秒后只以更弱的强度重复扫描，
/// 不重新黑场，也不重置已经建立的星场。
struct BootVisualTimeline: Equatable {
    enum SystemPhase: String, Equatable {
        case initializing = "INITIALIZING"
        case catalogSync = "CATALOG SYNC"
        case calibrating = "CALIBRATING"
        case ready = "READY"

        var localizedLabel: String {
            switch self {
            case .initializing: L10n.text("boot.phase.initializing")
            case .catalogSync: L10n.text("boot.phase.catalog_sync")
            case .calibrating: L10n.text("boot.phase.calibrating")
            case .ready: L10n.text("boot.phase.ready")
            }
        }
    }

    static let minimumPresentationDuration: TimeInterval = 3.2
    static let fullDuration: TimeInterval = 3.6
    static let scanStart: TimeInterval = 0.35
    static let scanEnd: TimeInterval = 2.75
    static let loopStart: TimeInterval = 0.55
    static let loopEnd: TimeInterval = 3.05
    private static let loopDuration = loopEnd - loopStart

    let elapsed: TimeInterval
    let isReady: Bool
    let handoffProgress: Double

    var phaseTime: TimeInterval {
        guard elapsed > Self.minimumPresentationDuration else {
            return max(0, elapsed)
        }
        let loop = (elapsed - Self.loopStart)
            .truncatingRemainder(dividingBy: Self.loopDuration)
        return Self.loopStart + max(0, loop)
    }

    var loopStrength: Double {
        elapsed <= Self.minimumPresentationDuration ? 1 : 0.38
    }

    var scanProgress: Double {
        Self.smoothstep(
            (phaseTime - Self.scanStart) / (Self.scanEnd - Self.scanStart)
        )
    }

    /// 信号点并非匀速穿过标题。每个字母附近有一段短暂停顿，再缓慢吸附到下一格。
    var signalProgress: Double {
        let raw = min(0.9999, max(0, scanProgress)) * 8
        let index = floor(raw)
        let local = raw - index
        let moving = Self.smoothstep((local - 0.24) / 0.62)
        return min(1, (index + moving) / 8)
    }

    var systemPhase: SystemPhase {
        if isReady { return .ready }
        if elapsed < 1.05 { return .initializing }
        if elapsed < 2.15 { return .catalogSync }
        return .calibrating
    }

    var readyEmphasis: Double {
        guard systemPhase == .ready else { return 0 }
        let readyTime = max(
            0,
            elapsed - (Self.minimumPresentationDuration - 0.18)
        )
        return 0.72 + 0.28 * Self.smoothstep(readyTime / 0.24)
    }

    var finalFrame: Double {
        min(1, max(0, handoffProgress))
    }

    var wordmarkOpacity: Double {
        1 - Self.smoothstep(finalFrame)
    }

    func letterActivation(at index: Int) -> Double {
        let position = Double(index) / 8
        let passed = Self.smoothstep((scanProgress - position + 0.035) / 0.12)
        let focus = max(0, 1 - abs(signalProgress - position) / 0.12)
        let settled = 0.18 + 0.66 * passed
        return min(1, settled + 0.22 * focus * loopStrength)
    }

    func letterBlur(at index: Int) -> CGFloat {
        let activation = letterActivation(at: index)
        return CGFloat(max(0, 0.72 * (1 - activation)))
    }

    func moduleActivation(at index: Int) -> Double {
        if systemPhase == .ready { return 1 }
        let thresholds = [0.12, 0.48, 0.78]
        guard thresholds.indices.contains(index) else { return 0 }
        return Self.smoothstep((scanProgress - thresholds[index]) / 0.18)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}

/// 与主天空共用同一枚确定性星尘种子。加载页不再绘制轨道环、目标或准星；
/// 标题退场时这片星场保持不动，主页的目录目标和仪器控件在其上自然出现。
struct BootFieldView: View {
    let timeline: BootVisualTimeline

    private let dust = StarDust()

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Palette.voidBlack)
            )

            SkyRenderer.drawDust(
                context,
                dust: dust,
                size: size,
                transform: StarDust.skyTransform(
                    pointing: .initial,
                    canvasSize: size,
                    verticalFOV: Projection.baseVerticalFOV
                )
            )

            drawLocalSignalResponse(context, size: size)
            SkyRenderer.drawVignette(context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawLocalSignalResponse(
        _ context: GraphicsContext,
        size: CGSize
    ) {
        guard timeline.finalFrame < 0.9 else { return }
        let x = size.width / 2 - 82 + 164 * CGFloat(timeline.signalProgress)
        let strength = 0.12 * timeline.loopStrength * timeline.wordmarkOpacity
        guard strength > 0.01 else { return }

        let points = [
            CGPoint(x: x - 7, y: size.height / 2 - 34),
            CGPoint(x: x + 12, y: size.height / 2 + 38),
        ]
        for (index, point) in points.enumerated() {
            let radius: CGFloat = index == 0 ? 0.72 : 0.5
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(Palette.signal.opacity(strength * (index == 0 ? 1 : 0.68)))
            )
        }
    }
}

/// 固定在画面中央的品牌唤醒层。字号、字距和位置始终不变；只有字母清晰度、
/// 信号点与副标题状态参与加载过程。
struct SystemWakeView: View {
    let isReady: Bool
    let handoffProgress: Double
    let suppressMotion: Bool

    @State private var startedAt = Date()

    var body: some View {
        #if DEBUG
        if let previewElapsed {
            wakeContent(
                BootVisualTimeline(
                    elapsed: previewElapsed,
                    isReady: isReady,
                    handoffProgress: handoffProgress
                )
            )
        } else if suppressMotion {
            staticWakeContent
        } else {
            animatedWakeContent
        }
        #else
        if suppressMotion {
            staticWakeContent
        } else {
            animatedWakeContent
        }
        #endif
    }

    private var staticWakeContent: some View {
        wakeContent(
            BootVisualTimeline(
                elapsed: BootVisualTimeline.minimumPresentationDuration,
                isReady: isReady,
                handoffProgress: handoffProgress
            )
        )
    }

    private var animatedWakeContent: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { frame in
            wakeContent(
                BootVisualTimeline(
                    elapsed: frame.date.timeIntervalSince(startedAt),
                    isReady: isReady,
                    handoffProgress: handoffProgress
                )
            )
        }
    }

    private func wakeContent(_ timeline: BootVisualTimeline) -> some View {
        ZStack {
            BootFieldView(timeline: timeline)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                wordmark(timeline)
                    .padding(.bottom, 14)
                BootModuleRail(timeline: timeline)
                    .padding(.bottom, 15)
                BootStatusText(
                    phase: timeline.systemPhase,
                    readyEmphasis: timeline.readyEmphasis
                )
            }
            .opacity(timeline.wordmarkOpacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func wordmark(_ timeline: BootVisualTimeline) -> some View {
        let letters = Array("STARCATCH")
        let titleWidth: CGFloat = 216
        let cellWidth = titleWidth / CGFloat(letters.count)

        return ZStack(alignment: .topLeading) {
            // A soft focus plane moves through the wordmark. It is deliberately
            // wider than a light streak so the result reads as optical calibration.
            LinearGradient(
                colors: [
                    .clear,
                    Palette.signal.opacity(0.035 * timeline.loopStrength),
                    Palette.signal.opacity(0.12 * timeline.loopStrength),
                    Palette.signal.opacity(0.035 * timeline.loopStrength),
                    .clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 46, height: 39)
            .blur(radius: 4)
            .offset(x: -23 + CGFloat(timeline.signalProgress) * titleWidth, y: -4)

            HStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .font(.system(size: 21, weight: .semibold, design: .monospaced))
                        .foregroundStyle(
                            Palette.inkHigh.opacity(
                                0.16 + 0.78 * timeline.letterActivation(at: index)
                            )
                        )
                        .blur(radius: timeline.letterBlur(at: index))
                        .frame(width: cellWidth, height: 31)
                }
            }

            HStack(spacing: 4) {
                ForEach(0 ..< letters.count, id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= Int(timeline.signalProgress * 8.01)
                                ? Palette.signal.opacity(0.58 * timeline.loopStrength)
                                : Palette.inkFaint.opacity(0.25)
                        )
                        .frame(width: cellWidth - 4, height: index == Int(timeline.signalProgress * 8.01) ? 1.4 : 0.55)
                }
            }
            .frame(width: titleWidth)
            .offset(y: 36)

            calibrationBracket(leading: true)
                .offset(x: -13, y: 7)
            calibrationBracket(leading: false)
                .offset(x: titleWidth + 7, y: 7)
        }
        .frame(width: titleWidth, height: 42, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("StarCatch")
    }

    private func calibrationBracket(leading: Bool) -> some View {
        Path { path in
            if leading {
                path.move(to: CGPoint(x: 5, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 17))
                path.addLine(to: CGPoint(x: 5, y: 17))
            } else {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 5, y: 0))
                path.addLine(to: CGPoint(x: 5, y: 17))
                path.addLine(to: CGPoint(x: 0, y: 17))
            }
        }
        .stroke(Palette.inkFaint.opacity(0.42), lineWidth: 0.55)
        .frame(width: 5, height: 17)
    }

    #if DEBUG
    private var previewElapsed: TimeInterval? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--previewBootTime"),
              index + 1 < arguments.count else {
            return nil
        }
        return TimeInterval(arguments[index + 1])
    }
    #endif
}

private struct BootModuleRail: View {
    let timeline: BootVisualTimeline

    private let keys = [
        "boot.module.catalog",
        "boot.module.orbit",
        "boot.module.attitude",
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Palette.inkFaint.opacity(0.48), lineWidth: 0.55)
                        Circle()
                            .fill(Palette.signal.opacity(0.82))
                            .padding(2.2)
                            .opacity(timeline.moduleActivation(at: index))
                    }
                    .frame(width: 7, height: 7)

                    Text(L10n.text(key))
                        .lineLimit(1)
                }
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(SupportedLanguage.current == .english ? 0.65 : 0.2)
                .foregroundStyle(
                    Palette.inkLow.opacity(0.35 + 0.38 * timeline.moduleActivation(at: index))
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 244, height: 16)
        .accessibilityHidden(true)
    }
}

private struct BootStatusText: View {
    let phase: BootVisualTimeline.SystemPhase
    let readyEmphasis: Double

    @State private var displayedPhase: BootVisualTimeline.SystemPhase = .initializing
    @State private var phaseVisible = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(
                    displayedPhase == .ready
                        ? Palette.signal.opacity(0.76 + 0.18 * readyEmphasis)
                        : Palette.inkLow.opacity(0.54)
                )
                .frame(width: 3.5, height: 3.5)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + 2
                }
            Text(L10n.text("boot.system.title"))
            Text("·")
                .foregroundStyle(Palette.inkFaint.opacity(0.62))
            Text(displayedPhase.localizedLabel)
                .opacity(phaseVisible ? 1 : 0)
                .offset(y: phaseVisible ? 0 : 1)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(SupportedLanguage.current == .english ? 0.72 : 0.18)
        .foregroundStyle(
            Palette.inkLow.opacity(
                displayedPhase == .ready
                    ? 0.58 + 0.26 * readyEmphasis
                    : 0.52
            )
        )
        .frame(minWidth: 220, minHeight: 18, alignment: .center)
        .onAppear { displayedPhase = phase }
        .onChange(of: phase) { _, next in
            guard next != displayedPhase else { return }
            withAnimation(.easeOut(duration: 0.1)) {
                phaseVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                displayedPhase = next
                withAnimation(.easeOut(duration: 0.14)) {
                    phaseVisible = true
                }
            }
        }
        .accessibilityLabel(
            L10n.format("boot.system.accessibility", phase.localizedLabel)
        )
    }
}
