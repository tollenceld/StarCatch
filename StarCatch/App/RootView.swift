import SwiftUI

/// 沉浸式天空页顶部仪器栏的共同几何基准。
/// 左右入口与中央指向读数共享同一触控行，避免各自用 padding 猜测位置。
enum SkyTopBarMetrics {
    static let safeAreaSpacing: CGFloat = 4
    static let controlHeight: CGFloat = 44
}

/// 顶层视图。三段流程：
///
///   1. BootSequenceView —— 一次仪器上电（首启约 6 秒，可轻触直达观测）
///   2. ManualBookView —— 仅首启，逐页翻阅的观测手册（约 5 页）
///   3. SkyView —— 主观测视图
///
/// 首启是一次完整的仪式：Boot 淡出直接进入 Manual，Manual 最后一页收束
/// 直接进入 Sky，全程无跳跃、无自动弹窗。老用户 Boot → Sky。
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @StateObject private var session = SkySession()
    @StateObject private var capture = CaptureStateMachine()
    @StateObject private var clock = SkyClock()

    /// 三段流程的枚举，取代原来分散的 booted / panelPresented 布尔。
    private enum Stage {
        case booting
        case manual
        case sky
        case privacy
    }

    @State private var stage: Stage = .booting
    @State private var instrumentPresented = false
    @AppStorage("manualSeen") private var manualSeen = false
    @AppStorage("reducedMotion") private var reducedMotion = false

    private var sceneAnimation: Animation {
        reducedMotion || systemReducedMotion ? .easeOut(duration: 0.16) : Motion.sceneTransition
    }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            // 天空：只在 sky 阶段显示
            if stage == .sky, !instrumentPresented {
                if session.catalog.objects.isEmpty {
                    CatalogUnavailableView()
                } else {
                    SkyView(session: session, capture: capture, clock: clock)
                        .transition(.opacity)
                        .overlay(alignment: .topTrailing) { sysEntry }
                }
            }

            // 手册：仅首启，Boot 之后进入
            if stage == .manual {
                ManualBookView(session: session) {
                    manualSeen = true
                    withAnimation(sceneAnimation) { stage = .sky }
                }
                .transition(.opacity)
            }

            // 启动序列
            if stage == .booting {
                BootSequenceView(session: session, compact: manualSeen) { interrupted in
                    withAnimation(sceneAnimation) {
                        if interrupted {
                            manualSeen = true
                            stage = .sky
                        } else {
                            stage = manualSeen ? .sky : .manual
                        }
                    }
                }
                .transition(.opacity)
            }

            if stage == .privacy {
                PrivacyStatementView {
                    withAnimation(sceneAnimation) { stage = .sky }
                }
                .transition(.opacity)
            }

            // 仪器参数面板
            if stage == .sky, instrumentPresented {
                InstrumentPanel(
                    presented: $instrumentPresented,
                    session: session,
                    onOpenManual: {
                        withAnimation(sceneAnimation) {
                            instrumentPresented = false
                            stage = .manual
                        }
                    },
                    onOpenPrivacy: {
                        withAnimation(sceneAnimation) {
                            instrumentPresented = false
                            stage = .privacy
                        }
                    }
                )
                    .transition(.opacity)
            }
        }
        .onAppear {
            session.start()
            #if DEBUG
            applyDebugArgs()
            #endif
        }
        .onChange(of: stage) { _, newStage in
            if newStage == .sky { session.requestObserverAccess() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                session.start()
                if stage == .sky { session.requestObserverAccess() }
            case .inactive, .background:
                session.stop()
            @unknown default:
                break
            }
        }
    }

    #if DEBUG
    /// 调试参数：--skipBoot 跳过启动序列；--openInstrument 直接展开仪器面板；
    /// --forceManual 强制跳到手册（配合 --manualPage <n>）；
    /// --markManualSeen 强制视为已看过手册，直接进 sky；
    /// --emptySky 把模拟器初始指向移到空域；
    /// --focusVisibleObject 将模拟器准星置于当前观测时刻最高的目标；
    /// --previewTimeScrub 持续拨动并保持天空球（仅用于视觉审计）；
    /// --previewOverviewExit 自动拨动后退出天空球；
    /// --openOverview 直接打开常驻全局星图；
    /// --previewOverviewTransform 以旋转、放大状态打开星图；
    /// --previewOverviewMode 自动演示常驻星图进入与退出；
    /// --previewReturnToLive 自动从一小时偏移回归 LIVE；
    /// --autoReleaseAfter <秒> 用于验证完整锁定/释放动画。
    private func applyDebugArgs() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--markManualSeen") { manualSeen = true }
        if args.contains("--skipBoot") {
            if args.contains("--forceManual") {
                stage = .manual
            } else {
                stage = manualSeen ? .sky : .manual
            }
        }
        if args.contains("--openInstrument") {
            instrumentPresented = true
        }
        if args.contains("--openPrivacy") {
            instrumentPresented = false
            stage = .privacy
        }
        if args.contains("--emptySky") {
            session.manualProvider?.drag(translation: CGSize(width: -800, height: -100))
        }
        // --timeOffset <秒>：直接拨动观测时钟（验证非 LIVE 视觉）
        if let idx = args.firstIndex(of: "--timeOffset"),
           idx + 1 < args.count,
           let seconds = Double(args[idx + 1]) {
            clock.scrub(by: seconds)
        }
        if args.contains("--focusVisibleObject"), let manual = session.manualProvider {
            let observation = clock.observationTime()
            // 与主天空实际参与捕捉的采样集合保持一致，避免调试时对准了被收束的星座节点。
            let target = session.displayObjects
                .compactMap { object -> Ephemeris? in
                    session.ephemeris.ephemeris(
                        object.id,
                        at: observation,
                        live: clock.isLive
                    )
                }
                .filter { $0.elevation > -0.1 }
                .max { $0.elevation < $1.elevation }
            if let target {
                manual.focusForPreview(
                    azimuth: target.azimuth,
                    elevation: target.elevation
                )
            }
        }
        if args.contains("--previewTimeScrub") {
            clock.updateScrubPresentation(translationPoints: 72)
            Task { @MainActor in
                for _ in 0 ..< 36 {
                    clock.scrub(by: 90)
                    try? await Task.sleep(for: .milliseconds(45))
                }
            }
        }
        if args.contains("--previewOverviewExit") {
            clock.updateScrubPresentation(translationPoints: 72)
            Task { @MainActor in
                for _ in 0 ..< 16 {
                    clock.scrub(by: 120)
                    try? await Task.sleep(for: .milliseconds(45))
                }
                try? await Task.sleep(for: .milliseconds(420))
                withAnimation(Motion.skyOverviewExit) {
                    clock.endScrubPresentation()
                }
            }
        }
        if args.contains("--previewReturnToLive") {
            clock.scrub(by: 3600)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                clock.returnToLive()
            }
        }
        if let idx = args.firstIndex(of: "--autoReleaseAfter"),
           idx + 1 < args.count,
           let seconds = Double(args[idx + 1]) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                capture.releaseSignal()
            }
        }
    }
    #endif

    /// 右上角微型仪器端口。视觉直径克制，触控区域仍保持 44pt。
    private var sysEntry: some View {
        Button {
            withAnimation(sceneAnimation) { instrumentPresented = true }
        } label: {
            ZStack {
                Circle()
                    .fill(Palette.voidBlack.opacity(0.9))
                Circle()
                    .stroke(Palette.inkFaint.opacity(0.72), lineWidth: 0.65)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                Circle()
                    .fill(Palette.signal.opacity(0.9))
                    .frame(width: 2.5, height: 2.5)
                    .offset(x: 10, y: -10)
            }
            .frame(width: 30, height: 30)
            .frame(
                width: SkyTopBarMetrics.controlHeight,
                height: SkyTopBarMetrics.controlHeight
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .safeAreaPadding(.top, SkyTopBarMetrics.safeAreaSpacing)
        .safeAreaPadding(.trailing, 8)
        .accessibilityLabel("打开仪器状态与设置")
        .accessibilityHint("进入设置、观测记录与帮助")
    }
}

private struct CatalogUnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CATALOG OFFLINE")
                .font(Typography.objectName)
                .tracking(Typography.objectNameTracking)
                .foregroundStyle(Palette.signal.opacity(Palette.Level.full))
            Text("轨道目录未能载入。请重新安装应用；若问题持续，请联系支持。")
                .font(Typography.poetic)
                .lineSpacing(Typography.poeticLineSpacing)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
        }
        .frame(maxWidth: 300, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.voidBlack)
    }
}

#Preview {
    RootView()
}
