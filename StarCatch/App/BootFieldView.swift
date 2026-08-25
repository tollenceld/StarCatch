import SwiftUI

/// 启动页只展示真实完成的准备节点。三个布尔值按顺序由 `RootView`
/// 在目录、轨道引擎和捕获管线真正可用后更新。
struct BootPreparationState: Equatable, Sendable {
    var catalogReady = false
    var orbitEngineReady = false
    var observationModelReady = false

    static let initial = BootPreparationState()
    static let ready = BootPreparationState(
        catalogReady: true,
        orbitEngineReady: true,
        observationModelReady: true
    )

    var isReady: Bool {
        catalogReady && orbitEngineReady && observationModelReady
    }

    func isModuleReady(at index: Int) -> Bool {
        switch index {
        case 0: catalogReady
        case 1: orbitEngineReady
        case 2: observationModelReady
        default: false
        }
    }

    var activeModuleIndex: Int? {
        (0 ..< 3).first { !isModuleReady(at: $0) }
    }
}

/// 启动文字系统的纯值时间轴。
///
/// 字形注册只执行一次。数据等待时间超过 3.2 秒后保持稳定终帧，
/// 不循环、不重新黑场，也不重置已经建立的星场。
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
    static let registrationStart: TimeInterval = 0.4
    static let registrationEnd: TimeInterval = 1.8

    let elapsed: TimeInterval
    let preparation: BootPreparationState
    let handoffProgress: Double

    var registrationProgress: Double {
        Self.smoothstep(
            (elapsed - Self.registrationStart)
                / (Self.registrationEnd - Self.registrationStart)
        )
    }

    var systemPhase: SystemPhase {
        if preparation.isReady { return .ready }
        if preparation.orbitEngineReady { return .calibrating }
        if preparation.catalogReady { return .catalogSync }
        return .initializing
    }

    var readyEmphasis: Double {
        preparation.isReady ? 1 : 0
    }

    var finalFrame: Double {
        min(1, max(0, handoffProgress))
    }

    var wordmarkOpacity: Double {
        1 - Self.smoothstep(finalFrame)
    }

    func letterActivation(at index: Int) -> Double {
        let position = Double(index) / 9
        return Self.smoothstep(
            (registrationProgress - position * 0.72) / 0.2
        )
    }

    func registrationOffset(at index: Int) -> CGFloat {
        CGFloat(0.95 * (1 - letterActivation(at: index)))
    }

    func moduleActivation(at index: Int) -> Double {
        preparation.isModuleReady(at: index) ? 1 : 0
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

            SkyRenderer.drawVignette(context, size: size)
        }
        .accessibilityHidden(true)
    }
}

/// 固定在画面中央的品牌唤醒层。字号、字距和位置始终不变；只有字母注册进度
/// 与模块验证状态参与加载过程。
struct SystemWakeView: View {
    let preparation: BootPreparationState
    let handoffProgress: Double
    let suppressMotion: Bool

    @State private var startedAt = Date()

    var body: some View {
        #if DEBUG
        if let previewElapsed {
            wakeContent(
                BootVisualTimeline(
                    elapsed: previewElapsed,
                    preparation: preparation,
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
                preparation: preparation,
                handoffProgress: handoffProgress
            )
        )
    }

    private var animatedWakeContent: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { frame in
            wakeContent(
                BootVisualTimeline(
                    elapsed: frame.date.timeIntervalSince(startedAt),
                    preparation: preparation,
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
                    .padding(.bottom, 27)
                BootModuleLedger(
                    preparation: preparation,
                    timeline: timeline
                )
                .padding(.bottom, 21)
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
            HStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    registeredGlyph(
                        String(letter),
                        activation: timeline.letterActivation(at: index),
                        offset: timeline.registrationOffset(at: index)
                    )
                    .frame(width: cellWidth, height: 31)
                }
            }

            HStack(spacing: 0) {
                ForEach(0 ..< letters.count, id: \.self) { index in
                    Rectangle()
                        .fill(Palette.inkFaint.opacity(0.24 + 0.28 * timeline.letterActivation(at: index)))
                        .frame(width: cellWidth, height: 0.5)
                        .overlay(alignment: .center) {
                            Rectangle()
                                .fill(Palette.signal.opacity(0.38 * timeline.letterActivation(at: index)))
                                .frame(width: 0.5, height: 5)
                        }
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

    private func registeredGlyph(
        _ glyph: String,
        activation: Double,
        offset: CGFloat
    ) -> some View {
        let font = Font.system(size: 21, weight: .semibold, design: .monospaced)
        return ZStack {
            Text(glyph)
                .font(font)
                .foregroundStyle(Palette.inkHigh.opacity(0.12 + 0.84 * activation))

            Text(glyph)
                .font(font)
                .foregroundStyle(Palette.signal.opacity(0.24 * (1 - activation)))
                .offset(x: -offset, y: -0.35)
                .mask(alignment: .top) {
                    VStack(spacing: 5) {
                        Rectangle().frame(height: 0.8)
                        Rectangle().frame(height: 0.6)
                        Rectangle().frame(height: 0.8)
                    }
                }

            Text(glyph)
                .font(font)
                .foregroundStyle(Palette.inkMid.opacity(0.2 * (1 - activation)))
                .offset(x: offset, y: 0.45)
                .mask(alignment: .bottom) {
                    VStack(spacing: 6) {
                        Rectangle().frame(height: 0.7)
                        Rectangle().frame(height: 0.55)
                        Rectangle().frame(height: 0.7)
                    }
                }
        }
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

private struct BootModuleLedger: View {
    let preparation: BootPreparationState
    let timeline: BootVisualTimeline

    private let modules = [
        ("boot.module.catalog", "books.vertical"),
        ("boot.module.orbit_solver", "circle.dotted.and.circle"),
        ("boot.module.observation_model", "viewfinder"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(modules.enumerated()), id: \.offset) { index, module in
                HStack(spacing: 11) {
                    Image(systemName: module.1)
                        .font(.system(size: 10, weight: .light))
                        .frame(width: 16)
                    Text(L10n.text(module.0))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(statusKey(for: index))
                        .foregroundStyle(
                            preparation.isModuleReady(at: index)
                                ? Palette.signal.opacity(0.78)
                                : Palette.inkLow.opacity(0.48)
                        )
                    Image(systemName: preparation.isModuleReady(at: index) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 8, weight: .medium))
                        .frame(width: 10)
                        .foregroundStyle(
                            preparation.isModuleReady(at: index)
                                ? Palette.signal.opacity(0.82)
                                : Palette.inkFaint.opacity(0.44)
                        )
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(SupportedLanguage.current == .english ? 0.55 : 0.12)
                .foregroundStyle(Palette.inkMid.opacity(0.54 + 0.26 * timeline.moduleActivation(at: index)))
                .frame(height: 35)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Palette.inkFaint.opacity(0.22))
                        .frame(height: 0.5)
                }
            }
        }
        .frame(width: 238)
        .accessibilityHidden(true)
    }

    private func statusKey(for index: Int) -> String {
        if preparation.isModuleReady(at: index) {
            return L10n.text("boot.module.verified")
        }
        return L10n.text(
            preparation.activeModuleIndex == index
                ? "boot.module.working"
                : "boot.module.waiting"
        )
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
