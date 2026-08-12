import SwiftUI

/// 沉浸式天空页顶部仪器栏的共同几何基准。
/// 左右入口与中央指向读数共享同一触控行，避免各自用 padding 猜测位置。
enum SkyTopBarMetrics {
    static let safeAreaSpacing: CGFloat = 4
    static let controlHeight = AppChromeMetrics.controlHeight
    static let visualHeight = AppChromeMetrics.wingVisualHeight
    static let outerMargin = AppChromeMetrics.topEdgeInset
    static let expandedGap: CGFloat = 4
}

/// 顶层视图。核心流程：
///
///   1. BootSequenceView —— 仅首次启动的简短产品说明与明确进入动作
///   2. SkyView —— 主观测视图
///   3. ManualBookView —— 从设置按需打开的五页观测手册
///
/// 首启由用户明确进入天空；回访用户由极简品牌准备层直接进入 Sky。
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    /// 11 MB 轨道目录必须在首帧之后于后台解析；同步构造会让系统 Launch Screen
    /// 持续占据屏幕，用户只能看到一段没有反馈的纯黑。
    @State private var session: SkySession?
    @StateObject private var capture = CaptureStateMachine()
    @StateObject private var clock = SkyClock()

    /// 三段流程的枚举，取代原来分散的 booted / panelPresented 布尔。
    private enum Stage {
        case booting
        case manual
        case sky
        case privacy
    }

    /// 无论首启还是回访都先建立一个可立即绘制的启动层；目录完成后再进入业务页面。
    @State private var stage: Stage = .booting
    @State private var instrumentPresented = false
    @State private var instrumentDestination: InstrumentPanel.Destination = .settings
    @State private var overviewRequested = false
    @State private var manualReturnsToInstrument = false
    @State private var satelliteStoryPresented = false
    @AppStorage("manualSeen") private var manualSeen = false
    @AppStorage("reducedMotion") private var reducedMotion = false

    private var sceneAnimation: Animation {
        reducedMotion || systemReducedMotion ? .easeOut(duration: 0.16) : Motion.sceneTransition
    }
    private var contentPageTransition: AnyTransition {
        guard !reducedMotion, !systemReducedMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            // 天空：只在 sky 阶段显示
            if stage == .sky, !instrumentPresented, let session {
                if session.catalog.objects.isEmpty {
                    CatalogUnavailableView(reason: session.catalog.loadFailureDescription)
                } else {
                    SkyView(
                        session: session,
                        capture: capture,
                        clock: clock,
                        onStoryPresentationChanged: { presented in
                            satelliteStoryPresented = presented
                        },
                        onOpenInstrument: {
                            instrumentDestination = .settings
                            withAnimation(sceneAnimation) { instrumentPresented = true }
                        },
                        onOpenSystemStatus: {
                            instrumentDestination = .systemStatus
                            withAnimation(sceneAnimation) { instrumentPresented = true }
                        },
                        onOpenArchive: {
                            instrumentDestination = .observations
                            withAnimation(sceneAnimation) { instrumentPresented = true }
                        },
                        initialOverviewPresented: overviewRequested,
                        onInitialOverviewHandled: { overviewRequested = false }
                    )
                        .transition(.opacity)
                }
            }

            // 手册：从设置中按需重新打开
            if stage == .manual, let session {
                ManualBookView(
                    session: session,
                    revisiting: manualReturnsToInstrument
                ) {
                    manualSeen = true
                    let returnsToInstrument = manualReturnsToInstrument
                    withAnimation(sceneAnimation) {
                        stage = .sky
                        instrumentPresented = returnsToInstrument
                    }
                    manualReturnsToInstrument = false
                }
                .transition(contentPageTransition)
            }

            // 启动序列
            if stage == .booting {
                if manualSeen {
                    StartupLoadingView(isReady: session != nil) {
                        withAnimation(
                            reducedMotion || systemReducedMotion
                                ? .easeOut(duration: 0.16)
                                : Motion.bootHandoff
                        ) {
                            stage = .sky
                        }
                    }
                        .transition(.opacity)
                } else {
                    BootSequenceView(isReady: session != nil) { interrupted in
                        withAnimation(sceneAnimation) {
                            if interrupted {
                                manualSeen = true
                                stage = .sky
                            } else {
                                stage = .manual
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }

            if stage == .privacy {
                PrivacyStatementView {
                    withAnimation(sceneAnimation) {
                        stage = .sky
                        instrumentPresented = true
                    }
                }
                .transition(contentPageTransition)
            }

            // 仪器参数面板
            if stage == .sky, instrumentPresented, let session {
                InstrumentPanel(
                    presented: $instrumentPresented,
                    session: session,
                    initialDestination: instrumentDestination,
                    onOpenOverview: {
                        overviewRequested = true
                        withAnimation(sceneAnimation) { instrumentPresented = false }
                    },
                    onOpenManual: {
                        withAnimation(sceneAnimation) {
                            manualReturnsToInstrument = true
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
                    .transition(contentPageTransition)
            }
        }
        .task { await prepareSession() }
        .onChange(of: stage) { _, newStage in
            guard let session else { return }
            if newStage == .sky {
                session.start()
                session.requestObserverAccess()
            } else {
                satelliteStoryPresented = false
                session.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                clock.resume()
                if stage == .sky, let session {
                    session.start()
                    session.requestObserverAccess()
                }
            case .inactive, .background:
                session?.stop()
                clock.suspend()
            @unknown default:
                break
            }
        }
    }

    /// 第一帧只绘制启动品牌信息。轨道 JSON、SatelliteKit 对象和筛选索引全部在
    /// userInitiated 后台任务中完成，避免阻塞 SwiftUI 建立首个窗口。
    private func prepareSession() async {
        guard session == nil else { return }
        let catalog = await Task.detached(priority: .userInitiated) {
            let catalog = CatalogStore()
            // 深度档案索引约 9 MB；在启动叙事期间完成首次映射与解码，避免用户
            // 第一次进入感应/筛选路径时触发静态库初始化。
            _ = SatelliteStoryCatalog.storyCount
            _ = SatelliteStoryCatalog.familyStoryCount
            return catalog
        }.value
        guard !Task.isCancelled else { return }

        let preparedSession = SkySession(catalog: catalog)
        await preparedSession.prewarmCapturePipeline()
        guard !Task.isCancelled else { return }
        session = preparedSession
        // 启动文字仍在屏幕上时预热触觉管线。第一次卫星进入准星不再承担
        // UIImpactFeedbackGenerator 的冷启动成本。
        ObservationHaptics.shared.prepare()

        #if DEBUG
        applyDebugArgs()
        #endif

    }

    #if DEBUG
    /// 调试参数：--skipBoot 跳过启动序列；--openInstrument 直接展开仪器面板；
    /// --forceManual 强制跳到手册（配合 --manualPage <n>）；
    /// --markManualSeen 强制视为已看过手册，直接进 sky；
    /// --emptySky 把模拟器初始指向移到空域；
    /// --focusVisibleObject 将模拟器准星置于当前观测时刻最高的目标；
    /// --profileFirstFocus 等待首批后台星历到达后再对准目标，用于性能取证且不
    /// 把调试器自己的同步全目录传播混入“第一次对焦”样本；
    /// --previewTimeScrub 持续拨动并保持天空球（仅用于视觉审计）；
    /// --previewOverviewExit 自动拨动后退出天空球；
    /// --openOverview 直接打开常驻全局星图；
    /// --previewOverviewTransform 以旋转、放大状态打开星图；
    /// --previewOverviewMode 自动演示常驻星图进入与退出；
    /// --previewReturnToLive 自动从一小时偏移回归 LIVE；
    /// --autoReleaseAfter <秒> 用于验证完整锁定/释放动画。
    private func applyDebugArgs() {
        guard let session else { return }
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
        if (args.contains("--focusVisibleObject") || args.contains("--focusFeaturedObject")),
           let manual = session.manualProvider {
            let observation = clock.observationTime()
            // 与主天空实际参与捕捉的采样集合保持一致，避免调试时对准了被收束的星座节点。
            let candidates = args.contains("--focusFeaturedObject")
                ? session.displayObjects.filter(\.isFeatured)
                : session.displayObjects
            let target = candidates
                .compactMap { object -> Ephemeris? in
                    session.ephemeris.ephemeris(
                        object.id,
                        at: observation,
                        live: clock.isLive
                    )
                }
                .filter { $0.elevation > 0 }
                .max { $0.elevation < $1.elevation }
            if let target {
                manual.focusForPreview(
                    azimuth: target.azimuth,
                    elevation: target.elevation
                )
            }
        }
        if args.contains("--profileFirstFocus"), let manual = session.manualProvider {
            Task { @MainActor in
                // 等待首批 utility 星历提交；只读批量缓存，不触发同步 SGP4。
                try? await Task.sleep(for: .milliseconds(1_500))
                let observation = clock.observationTime()
                let target = session.displayObjects
                    .compactMap { object in
                        session.ephemeris.cachedEphemeris(
                            object.id,
                            at: observation,
                            live: clock.isLive
                        )
                    }
                    .filter { $0.elevation > 0 }
                    .max { $0.elevation < $1.elevation }
                if let target {
                    manual.focusForPreview(
                        azimuth: target.azimuth,
                        elevation: target.elevation
                    )
                }
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
}

private struct CatalogUnavailableView: View {
    let reason: String?

    @Environment(\.openURL) private var openURL

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
            if let reason {
                Text(reason)
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                openURL(AppLinks.support)
            } label: {
                Label("联系支持", systemImage: "arrow.up.right")
                    .font(Typography.guide.weight(.medium))
                    .foregroundStyle(Palette.signal.opacity(Palette.Level.present))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开 StarCatch 支持页面")
        }
        .frame(maxWidth: 300, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.voidBlack)
    }
}

#Preview {
    RootView()
}
