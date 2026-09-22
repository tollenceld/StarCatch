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
///   1. ObservationEstablishment —— 从信号到本地天空的共享空间建立
///   2. SkyView —— 主观测视图
///   3. ManualBookView —— 从设置按需打开的五页观测手册
///
/// Sky 在准备期间挂载并保持身份，镜头抵达后原位接管；后台返回不重播。
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    /// 11 MB 轨道目录必须在首帧之后于后台解析；同步构造会让系统 Launch Screen
    /// 持续占据屏幕，用户只能看到一段没有反馈的纯黑。
    @State private var session: SkySession?
    @State private var establishment = ObservationEstablishment()
    @State private var capturePrewarmTask: Task<Void, Never>?
    @StateObject private var capture = CaptureStateMachine()
    @StateObject private var clock = SkyClock()

    /// 全屏阅读阶段与天空互斥；工具面板保留其下方的天空实例。
    private enum Stage {
        case booting
        case manual
        case sky
        case privacy
    }

    /// 无论首启还是回访都先建立一个可立即绘制的启动层；目录完成后再进入业务页面。
    @State private var stage: Stage = .booting
    @State private var presentedPage: AppPageDestination?
    @State private var skyRenderingSuspended = false
    @State private var panelProgress = 0.0
    @State private var dockFrame: CGRect = .zero
    @State private var panelSourceFrame: CGRect = .zero
    @State private var panelLifecycle = UtilityPanelLifecycle()
    @State private var panelTransitionTask: Task<Void, Never>?
    @State private var settingsReturnTask: Task<Void, Never>?
    @State private var settingsReturnPending = false
    @State private var manualReturnsToSettings = false
    @AppStorage("reducedMotion") private var reducedMotion = false

    private var sceneAnimation: Animation {
        suppressMotion ? .easeOut(duration: 0.16) : Motion.sceneTransition
    }
    private var contentPageTransition: AnyTransition {
        guard !suppressMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
    private var suppressMotion: Bool { reducedMotion || systemReducedMotion || debugFlag("--previewReduceMotion") }

    private func debugFlag(_ flag: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(flag)
        #else
        false
        #endif
    }
    private var forceLegacyMaterial: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--forceLegacyMaterial")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            // 工具面板出现时保留同一个天空实例与冻结绘制表面。
            if stage == .sky || stage == .booting, let session {
                if session.catalog.objects.isEmpty {
                    CatalogUnavailableView(reason: session.catalog.loadFailureDescription)
                } else {
                    SkyView(
                        session: session,
                        capture: capture,
                        clock: clock,
                        isUtilityPagePresented: presentedPage != nil,
                        renderingSuspended: skyRenderingSuspended,
                        establishment: stage == .booting ? establishment : nil,
                        onOpenFilters: {
                            presentPage(.filters)
                        },
                        onOpenInstrument: {
                            presentPage(.settings(initialRoute: nil))
                        },
                        onOpenSystemStatus: {
                            presentPage(.settings(initialRoute: .systemStatus))
                        },
                        onOpenArchive: {
                            presentPage(.observations)
                        }
                    )
                        .transition(.identity)
                        .allowsHitTesting(stage == .sky && presentedPage == nil)
                        .accessibilityHidden(presentedPage != nil)
                }
            }

            // 手册：从设置中按需重新打开
            if stage == .manual, let session {
                ManualBookView(
                    session: session,
                    revisiting: manualReturnsToSettings
                ) {
                    let returnsToSettings = manualReturnsToSettings
                    withAnimation(sceneAnimation) {
                        stage = .sky
                    }
                    manualReturnsToSettings = false
                    if returnsToSettings {
                        reopenSettingsAfterFullScreenReturn()
                    }
                }
                .transition(contentPageTransition)
            }

            // 启动序列
            if stage == .booting, session == nil {
                OrbitalBootView(establishment: establishment)
                    .transition(.identity)
            }

            if stage == .privacy {
                PrivacyStatementView {
                    withAnimation(sceneAnimation) {
                        stage = .sky
                    }
                    reopenSettingsAfterFullScreenReturn()
                }
                .transition(contentPageTransition)
            }
        }
        .coordinateSpace(name: "appChrome")
        .onPreferenceChange(CommandDockFrameKey.self) { frame in
            if presentedPage == nil { dockFrame = frame }
        }
        .overlay {
            if stage == .sky, let destination = presentedPage, let session {
                GeometryReader { geometry in
                    let source = panelSourceFrame.width > 0 ? panelSourceFrame : CGRect(
                        x: AppChromeMetrics.edgeInset,
                        y: geometry.size.height - 8 - AppChromeMetrics.commandRailHeight,
                        width: geometry.size.width - AppChromeMetrics.edgeInset * 2,
                        height: AppChromeMetrics.commandRailHeight
                    )
                    UtilityPanelContainer(
                        progress: panelProgress,
                        source: source,
                        top: 0,
                        reducedMotion: suppressMotion,
                        interactive: panelLifecycle.phase == .open,
                        filtersActive: session.activeCatalogFilterCount > 0,
                        showsCommands: capture.phase == .exploring,
                        onDismiss: dismissPage
                    ) {
                        appPage(destination, session: session)
                    }
                }
                .transition(.identity)
            }
        }
        .task { await prepareSession() }
        .task(id: scenePhase) { await establishObservation() }
        .onChange(of: session != nil) { _, _ in synchronizeSessionActivity() }
        .task(id: stage == .sky) {
            #if DEBUG
            guard stage == .sky,
                  ProcessInfo.processInfo.arguments.contains("--previewUtilityPanels") else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                for destination: AppPageDestination in [.filters, .observations, .settings(initialRoute: nil)] {
                    guard !Task.isCancelled, scenePhase == .active, presentedPage == nil else { return }
                    presentPage(destination)
                    try await Task.sleep(for: .seconds(1.8))
                    guard !Task.isCancelled, scenePhase == .active else { return }
                    dismissPage()
                    try await Task.sleep(for: .seconds(0.8))
                }
            } catch { return }
            #endif
        }
        .onChange(of: stage) { _, newStage in
            if newStage != .sky {
                cancelPanelTransition()
                presentedPage = nil
                panelProgress = 0
                skyRenderingSuspended = false
            }
            synchronizeSessionActivity()
        }
        .onChange(of: presentedPage) { _, _ in
            synchronizeSessionActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                clock.resume()
                synchronizeSessionActivity()
                if settingsReturnPending { reopenSettingsAfterFullScreenReturn() }
            case .inactive, .background:
                establishment.pause()
                settlePanelTransition()
                settingsReturnTask?.cancel()
                session?.stop()
                clock.suspend()
            @unknown default:
                break
            }
        }
        .onDisappear {
            cancelPanelTransition()
            settingsReturnTask?.cancel()
            capturePrewarmTask?.cancel()
        }
        .environment(\.forceLegacyMaterial, forceLegacyMaterial)
        .environment(\.chromePreviewReducedMotion, debugFlag("--previewReduceMotion"))
        .environment(\.chromePreviewReducedTransparency, debugFlag("--previewReduceTransparency"))
        .environment(\.dynamicTypeSize, debugFlag("--previewLargeType") ? .accessibility3 : systemDynamicTypeSize)
    }

    @ViewBuilder
    private func appPage(
        _ destination: AppPageDestination,
        session: SkySession
    ) -> some View {
        switch destination {
        case .filters:
            CatalogFilterPage(session: session, onBack: dismissPage)

        case .observations:
            ObservationHistoryPage(session: session, onBack: dismissPage)

        case .settings(let initialRoute):
            SettingsPage(
                session: session,
                initialRoute: initialRoute,
                onBack: dismissPage,
                onOpenManual: openManualFromSettings,
                onOpenPrivacy: openPrivacyFromSettings
            )
        }
    }

    private func presentPage(_ destination: AppPageDestination) {
        guard stage == .sky, presentedPage == nil, scenePhase == .active else { return }
        panelSourceFrame = dockFrame
        panelProgress = 0
        presentedPage = destination
        skyRenderingSuspended = true
        let generation = panelLifecycle.begin(expanding: true)
        panelTransitionTask = Task { @MainActor in
            // Establish the 64pt source before the first animated transaction.
            await Task.yield()
            guard !Task.isCancelled, panelLifecycle.generation == generation else { return }
            withAnimation(DockMorphMetrics.animation(expanding: true, reduced: suppressMotion)) {
                panelProgress = 1
            }
            do { try await Task.sleep(for: .seconds(DockMorphMetrics.duration(expanding: true, reduced: suppressMotion))) }
            catch { return }
            guard !Task.isCancelled else { return }
            panelLifecycle.complete(generation: generation)
        }
    }

    private func dismissPage() {
        guard presentedPage != nil, panelLifecycle.phase == .open else { return }
        panelTransitionTask?.cancel()
        let generation = panelLifecycle.begin(expanding: false)
        skyRenderingSuspended = false
        withAnimation(DockMorphMetrics.animation(expanding: false, reduced: suppressMotion)) {
            panelProgress = 0
        }
        panelTransitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(DockMorphMetrics.duration(expanding: false, reduced: suppressMotion))) }
            catch { return }
            guard !Task.isCancelled, panelLifecycle.complete(generation: generation) else { return }
            presentedPage = nil
        }
    }

    private func cancelPanelTransition() {
        panelTransitionTask?.cancel()
        panelTransitionTask = nil
        panelLifecycle.reset()
    }

    private func settlePanelTransition() {
        panelTransitionTask?.cancel()
        panelTransitionTask = nil
        panelLifecycle.settle()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if panelLifecycle.phase == .hidden {
                presentedPage = nil
                panelProgress = 0
                skyRenderingSuspended = false
            } else if presentedPage != nil {
                panelProgress = 1
                skyRenderingSuspended = true
            }
        }
    }

    private func openManualFromSettings() {
        cancelPanelTransition()
        presentedPage = nil
        panelProgress = 0
        skyRenderingSuspended = false
        manualReturnsToSettings = true
        withAnimation(sceneAnimation) { stage = .manual }
    }

    private func openPrivacyFromSettings() {
        cancelPanelTransition()
        presentedPage = nil
        panelProgress = 0
        skyRenderingSuspended = false
        withAnimation(sceneAnimation) { stage = .privacy }
    }

    private func reopenSettingsAfterFullScreenReturn() {
        settingsReturnPending = true
        settingsReturnTask?.cancel()
        settingsReturnTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
            guard !Task.isCancelled, stage == .sky, scenePhase == .active else { return }
            settingsReturnPending = false
            presentPage(.settings(initialRoute: nil))
        }
    }

    private func synchronizeSessionActivity() {
        guard let session else { return }
        if (stage == .sky || stage == .booting), presentedPage == nil, scenePhase == .active {
            session.start()
            if stage == .sky { session.requestObserverAccess() }
        } else {
            session.stop()
        }
    }

    /// 第一帧只绘制微弱信号。轨道 JSON、SatelliteKit 对象和筛选索引全部在
    /// userInitiated 后台任务中完成，避免阻塞 SwiftUI 建立首个窗口。
    private func prepareSession() async {
        guard session == nil else { return }
        let catalog = await Task.detached(priority: .userInitiated) {
            CatalogStore()
        }.value
        guard !Task.isCancelled else { return }
        let preparedSession = SkySession(catalog: catalog)
        session = preparedSession
        synchronizeSessionActivity()
        preparedSession.observer.requestIfAuthorized()
        capturePrewarmTask = Task {
            await Task.detached(priority: .utility) {
                _ = SatelliteStoryCatalog.storyCount
                _ = SatelliteStoryCatalog.familyStoryCount
            }.value
            guard !Task.isCancelled else { return }
            await preparedSession.prewarmCapturePipeline()
        }
        // 建立空间时预热触觉管线。第一次卫星进入准星不再承担
        // UIImpactFeedbackGenerator 的冷启动成本。
        ObservationHaptics.shared.prepare()

        #if DEBUG
        applyDebugArgs()
        #endif

    }

    private func establishObservation() async {
        while !Task.isCancelled, stage == .booting {
            let previousPhase = establishment.phase
            // This task is keyed by scenePhase, so its environment is current.
            if scenePhase == .active { session?.start() }
            let hadObserver = establishment.observer != nil
            var ready = session?.ephemeris.hasUsableFrame == true
                && session?.ephemeris.frameObserver == session?.observer.coordinates
            var uptime = ProcessInfo.processInfo.systemUptime
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--previewStartupDelay"), index + 1 < arguments.count,
               let delay = Double(arguments[index + 1]) { ready = ready && establishment.elapsed >= delay }
            if let index = arguments.firstIndex(of: "--previewStartupRate"), index + 1 < arguments.count,
               let rate = Double(arguments[index + 1]) { uptime *= min(1, max(0.1, rate)) }
            #endif
            let confirmation = establishment.advance(
                at: uptime, active: scenePhase == .active,
                sessionReady: session != nil,
                frameReady: ready,
                locating: session?.observer.isLocating == true,
                coordinates: session?.observer.coordinates ?? ObserverLocation.fallback,
                failed: session?.catalog.objects.isEmpty == true,
                reduced: suppressMotion, pointing: session?.pointing ?? .initial)
            #if DEBUG
            if previousPhase != establishment.phase {
                print("[ObservationStartup] \(establishment.phase) at \(establishment.elapsed), frame: \(session?.ephemeris.hasUsableFrame == true)")
            }
            #endif
            if !hadObserver, establishment.observer != nil { session?.observer.holdForPresentation() }
            if confirmation { ObservationHaptics.shared.softImpact(intensity: 0.25) }
            if establishment.isComplete {
                session?.observer.releasePresentationHold()
                stage = .sky
                return
            }
            do { try await Task.sleep(for: .milliseconds(33)) }
            catch { return }
        }
    }

    #if DEBUG
    /// 调试参数：--skipBoot 跳过启动序列；--openFilter / --openInstrument 直接打开工具面板；
    /// --openStatus / --openObservations 直接进入状态或记录页；
    /// --seedObservations 为记录页写入一组可滚动的本地调试记录；
    /// --previewUtilityPanels 自动演示三页正常展开与收回（不模拟正文手势）；
    /// --previewLargeType / --previewReduceMotion / --previewReduceTransparency 仅覆盖调试环境，不改系统偏好；
    /// --forceManual 强制跳到手册（配合 --manualPage <n>）；
    /// --markManualSeen 强制视为已看过手册，直接进 sky；
    /// --emptySky 把模拟器初始指向移到空域；
    /// --focusVisibleObject 将模拟器准星置于当前观测时刻最高的目标；
    /// --previewSensing / --previewFocusStage / --previewLockedTarget 固定捕获层级；
    /// --profileFirstFocus 等待首批后台星历到达后再对准目标，用于性能取证且不
    /// 把调试器自己的同步全目录传播混入“第一次对焦”样本；
    /// --previewTimeScrub 持续拨动并保持天空球（仅用于视觉审计）；
    /// --previewOverviewExit 自动拨动后退出天空球；
    /// --openOverview 直接打开常驻全局星图；--openTimePanel 打开时间面板；
    /// --timeOffset <秒> 固定非 LIVE；--forceLegacyMaterial 强制旧材质回退；
    /// --previewOverviewTransform 以旋转、放大状态打开星图；
    /// --previewOverviewInteraction 固定为交互降级材质，用于确认大陆基础轮廓持续存在；
    /// --previewOverviewMode 自动演示常驻星图进入与退出；
    /// --previewReturnToLive 自动从一小时偏移回归 LIVE；
    /// --autoDismissAfter <秒> 用于验证锁定详情的叉号收束动画。
    private func applyDebugArgs() {
        guard let session else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--skipBoot") {
            if args.contains("--forceManual") {
                stage = .manual
            } else {
                stage = .sky
            }
        }
        if args.contains("--seedObservations") {
            for object in session.catalog.objects.prefix(32) {
                session.log.record(objectId: object.id, catalog: session.catalog)
            }
        }
        if args.contains("--openInstrument") {
            presentedPage = .settings(initialRoute: nil)
        } else if args.contains("--openStatus") {
            presentedPage = .settings(initialRoute: .systemStatus)
        } else if args.contains("--openObservations") {
            presentedPage = .observations
        } else if args.contains("--openFilter") {
            presentedPage = .filters
        }
        if args.contains("--openPrivacy") {
            presentedPage = nil
            stage = .privacy
        }
        if presentedPage != nil {
            let generation = panelLifecycle.begin(expanding: true)
            panelLifecycle.complete(generation: generation)
            panelProgress = 1
            skyRenderingSuspended = true
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
        if (args.contains("--focusVisibleObject")
            || args.contains("--focusFeaturedObject")
            || args.contains("--previewSensing")
            || args.contains("--previewFocusStage")
            || args.contains("--previewLockedTarget")),
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
        if let idx = args.firstIndex(of: "--autoDismissAfter"),
           idx + 1 < args.count,
           let seconds = Double(args[idx + 1]) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                capture.dismissCurrentTarget()
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
            #if DEBUG
            if let reason {
                Text(reason)
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif
            Button {
                openURL(AppLinks.support)
            } label: {
                Label("联系支持", systemImage: "arrow.up.right")
                    .font(Typography.guide.weight(.medium))
                    .foregroundStyle(Palette.signal.opacity(Palette.Level.present))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.text("support.open.hint"))
        }
        .frame(maxWidth: 300, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.voidBlack)
    }
}

#Preview {
    RootView()
}
