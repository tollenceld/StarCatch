import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 主渲染视图：TimelineView + Canvas，30fps。
/// 完整层序：星尘 → 拖影 → 轨迹弧 → 点位/刻度环/扫描 → vignette → 锁定信标 → 十字丝 → 微型标签 → 颗粒 shader。
///
/// 两个观测维度：主天空负责指向与自动锁定，全局星图中的 TimeDial 负责选择观测时刻。
/// 非 LIVE 时全部对象按观测时刻推算；拨动时间时点位留下拖影 —— 时间方向的视觉痕迹。
struct SkyView: View {
    @ObservedObject var session: SkySession
    @ObservedObject var capture: CaptureStateMachine
    @ObservedObject var clock: SkyClock
    /// 工具面板暂停采样与绘制，但保留同一个绘制表面和最后观测时刻。
    var isUtilityPagePresented = false
    var renderingSuspended = false
    var onStoryPresentationChanged: (Bool) -> Void = { _ in }
    /// 设置与观测档案由上层负责呈现；观测记录同时作为底部控制栏的稳定入口，
    /// 目标卡仍可按内容直接进入深度档案。
    var onOpenFilters: () -> Void = {}
    var onOpenInstrument: () -> Void = {}
    var onOpenSystemStatus: () -> Void = {}
    var onOpenArchive: () -> Void = {}
    var initialOverviewPresented: Bool = false
    var onInitialOverviewHandled: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var platformReducedMotion
    @Environment(\.chromePreviewReducedMotion) private var previewReducedMotion
    private var systemReducedMotion: Bool { platformReducedMotion || previewReducedMotion }
    @AppStorage("reducedMotion") private var reducedMotion = false
    @AppStorage("grainEnabled") private var grainEnabled = true

    private let dust = StarDust()
    /// 时间偏移会高频发布；这些引用必须跨 View 值重建持久存在。
    @State private var startDate = Date()
    @State private var frozenFrameDate: Date?
    @StateObject private var screenTrails = TrailStore()
    /// 常驻星图使用较长但有界的缓存；10fps 采样，最多约 9 秒光轨。
    @StateObject private var overviewTrails = TrailStore(
        lifetime: 9,
        maximumPointsPerObject: 90,
        minimumPointDistance: 0.08
    )
    @StateObject private var overviewAmbientTrails = TrailStore(
        lifetime: OverviewAmbientTrailPolicy.lifetime,
        maximumPointsPerObject: OverviewAmbientTrailPolicy.maximumPointCount,
        minimumPointDistance: 0
    )
    @State private var viewportSize: CGSize = .zero
    /// 局部天空与全局轨道使用互斥模式。缩放手势只在当前模式内部工作，
    /// 只有入口按钮和返回按钮能够改变模式。
    @State private var presentationMode: SkyPresentationMode = .local
    @State private var persistentOverviewProgress: Double = 0
    @State private var globalEntryGateProgress: Double = 0
    @State private var globalEntryArmed = false
    @State private var globalEntryHapticSent = false
    @State private var overviewEntryPointing: Pointing?
    @State private var overviewCelestialFrame: CelestialViewFrame?
    @State private var overviewInteractionActive = false
    @State private var overviewIdleBeganAt: Date?
    @State private var transientOverlay: SkyTransientOverlay?
    @State private var lastOverviewTrailSample: TimeInterval = -.infinity
    @State private var lastCaptureSample: TimeInterval = -.infinity
    @State private var lastAcquisitionPulse: Date?
    @State private var fieldMagnification: CGFloat = 1
    @State private var settledFieldMagnification: CGFloat = 1
    @State private var fieldMagnificationActive = false
    @State private var fieldScaleGestureSample: CGFloat = 1
    @State private var fieldScaleGestureSampleDate = Date.distantPast
    @State private var fieldScaleLogarithmicVelocity: Double = 0
    @State private var presentedStoryObjectID: String?
    @State private var presentedPassForecast: PassForecast?
    @State private var engagedPreciseEphemeris: Ephemeris?
    @State private var engagedInsight: SatelliteInsightSnapshot?

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }
    private var fieldVerticalFOV: Double {
        Projection.verticalFOV(forMagnification: fieldMagnification)
    }
    private var wideFieldProgress: Double {
        ObservationScale.wideFieldProgress(magnification: fieldMagnification)
    }
    private var overviewTransitionVisuals: ObservationScale.TransitionVisuals {
        ObservationScale.transitionVisuals(progress: overviewPresentationProgress)
    }
    private var persistentOverviewPresented: Bool {
        presentationMode.presentsOverview
    }
    private var overviewCommitted: Bool {
        presentationMode.presentsOverview
    }
    private var overviewTransitioning: Bool {
        presentationMode.isTransitioning
    }
    private var localChromePresence: Double {
        let wideReduction = 1 - 0.46 * wideFieldProgress
        return wideReduction * (1 - overviewPresentationProgress)
    }
    private var localSkyPresence: Double {
        overviewTransitionVisuals.localSkyOpacity
    }
    private var localSkyScale: CGFloat {
        guard !suppressMotion else { return 1 }
        return overviewTransitionVisuals.localSkyScale
            * GlobalEntryGatePolicy.elasticScale(
                progress: globalEntryGateProgress
            )
    }
    private var localFieldResetAvailable: Bool {
        return !clock.isScrubbing
            && !fieldMagnificationActive
            && abs(fieldMagnification - 1) > 0.015
    }
    private var chromeState: SkyChromeState {
        SkyChromeState(
            presentationMode: presentationMode,
            capturePhase: capture.phase,
            localFieldResetAvailable: localFieldResetAvailable
        )
    }
    /// 全局空间已经成为视觉主体后才交接顶部与底部控件。直接入口也沿用同一阈值，
    /// 避免按钮先切换、地球随后才出现。
    private var overviewChromeVisible: Bool {
        presentationMode.presentsOverview && overviewPresentationProgress > 0.58
    }

    private var renderingSurface: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: renderingSuspended)) { timeline in
                let frameDate = frozenFrameDate ?? timeline.date
                let time = frameDate.timeIntervalSince(startDate)
                let obsTime = clock.observationTime(realNow: frameDate)

                ZStack(alignment: .topLeading) {
                    canvasLayer(time: time, observation: obsTime)
                        .contentShape(Rectangle())
                        .scaleEffect(localSkyScale)
                        .opacity(localSkyPresence)
                    crosshairLayer
                        .opacity(localChromePresence)
                    targetMicroLabelLayer(observation: obsTime)
                        .opacity(localChromePresence)
                    if clock.isLive {
                        guideLayer
                            .opacity(localChromePresence)
                    }
                    timeOverviewLayer(time: time, observation: obsTime)
                }
                .colorEffect(
                    ShaderLibrary.grain(
                        .float(Float(suppressMotion ? 0 : time)),
                        .float(grainEnabled ? 0.024 : 0)
                    )
                )
                .onChange(of: timeline.date) { _, frameDate in
                    guard !renderingSuspended else { return }
                    updateFrame(
                        at: frameDate,
                        observationTime: obsTime,
                        viewport: geo.size
                    )
                }
            }
            .onAppear { viewportSize = geo.size }
            .onChange(of: geo.size) { _, size in viewportSize = size }
        }
    }

    private var interactionSurface: some View {
        renderingSurface
        .ignoresSafeArea()
        .background(Palette.voidBlack)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(fieldMagnificationGesture)
        .overlay { transientDismissLayer }
        .overlay(alignment: .top) {
            pointingReadout
                // 顶部功能翼必须和灵动岛共享同一条水平轴；默认 overlay 会从
                // 安全区下缘开始布局，结果看起来仍是一条岛下工具栏。
                .ignoresSafeArea(edges: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomControlBand
        }
        .overlay {
            satelliteStoryLayer
        }
        .accessibilityAction(.escape) {
            if capture.isLocked, presentedStoryObjectID == nil {
                dismissLockedTarget()
            } else if presentationMode == .global,
                      presentedStoryObjectID == nil {
                exitOverviewToLocal()
            }
        }
    }

    var body: some View {
        interactionSurface
        .onChange(of: renderingSuspended, initial: true) { _, suspended in
            frozenFrameDate = suspended ? Date() : nil
        }
        .onAppear {
            EarthCoastlineStore.shared.prepare()
            if initialOverviewPresented {
                presentationMode = .global
                persistentOverviewProgress = 1
                overviewEntryPointing = session.pointing
                overviewCelestialFrame = makeCelestialViewFrame()
                overviewIdleBeganAt = Date()
                onInitialOverviewHandled()
            }
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--previewFocusStage")
                || arguments.contains("--previewLockedTarget")
                || arguments.contains("--previewSensing") {
                capture.cancelAcquisition()
            }
            if arguments.contains("--openObservationWing") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1600))
                    transientOverlay = .observationStatus
                }
            } else if arguments.contains("--openDirectionWing") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1600))
                    transientOverlay = .direction
                }
            }
            if arguments.contains("--filterObservation") {
                session.toggleCatalogFilter(.humanScience)
            }
            if let transitionArgument = arguments.first(where: {
                $0.hasPrefix("--previewOverviewProgress=")
            }), let progress = Double(
                transitionArgument.replacingOccurrences(
                    of: "--previewOverviewProgress=",
                    with: ""
                )
            ) {
                fieldMagnification = ObservationScale.minimumLocalMagnification
                settledFieldMagnification = fieldMagnification
                presentationMode = progress >= 1 ? .global : .enteringGlobal
                persistentOverviewProgress = min(1, max(0, progress))
                overviewEntryPointing = session.pointing
                overviewCelestialFrame = makeCelestialViewFrame()
            } else if arguments.contains("--openOverview") {
                presentationMode = .global
                persistentOverviewProgress = 1
                overviewEntryPointing = session.pointing
                overviewCelestialFrame = makeCelestialViewFrame()
                overviewIdleBeganAt = Date()
            } else if arguments.contains("--previewWideField") {
                fieldMagnification = 0.66
                settledFieldMagnification = fieldMagnification
            } else if arguments.contains("--previewScaleThreshold")
                        || arguments.contains("--previewGlobalEntry") {
                fieldMagnification = ObservationScale.minimumLocalMagnification
                settledFieldMagnification = fieldMagnification
                globalEntryArmed = true
            } else if arguments.contains("--previewOverviewMode") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(550))
                    globalEntryArmed = true
                    togglePersistentOverview()
                    try? await Task.sleep(for: .milliseconds(2400))
                    togglePersistentOverview()
                }
            }
            if arguments.contains("--openSatelliteStory") {
                presentedStoryObjectID = session.catalog.objects.first(where: {
                    $0.id == "hst"
                })?.id
                onStoryPresentationChanged(presentedStoryObjectID != nil)
            }
            #endif
        }
        .task(id: capture.engagedObjectId) {
            await prepareEngagedTargetData(for: capture.engagedObjectId)
        }
        .task(id: presentedStoryObjectID) {
            await preparePresentedForecast(for: presentedStoryObjectID)
        }
        .onChange(of: capture.phase) { _, newPhase in
            switch newPhase {
            case .acquiring:
                dismissTransientOverlay()
                lastAcquisitionPulse = Date()
                acquisitionEntryHaptic()
            case .locked(let objectId):
                lockedAt = Date()
                hasEverLocked = true
                lastAcquisitionPulse = nil
                lockHaptic()
                let observation = clock.observationTime()
                let ephemeris = engagedPreciseEphemeris
                    ?? session.ephemeris.cachedPreciseEphemeris(
                        objectId,
                        at: observation,
                        live: clock.isLive
                    )
                    ?? session.ephemeris.cachedEphemeris(
                        objectId,
                        at: observation,
                        live: clock.isLive
                    )
                session.log.record(
                    objectId: objectId,
                    catalog: session.catalog,
                    observationTime: observation,
                    ephemeris: ephemeris
                )
            case .exploring:
                lockedAt = nil
                lastAcquisitionPulse = nil
            case .dismissing:
                lastAcquisitionPulse = nil
            }
        }
        .onChange(of: capture.acquisitionProgress) { _, progress in
            updateAcquisitionHaptic(progress: progress)
        }
        .onChange(of: capture.engagedObjectId) { _, _ in
            overviewTrails.clear()
            lastOverviewTrailSample = -.infinity
        }
        .onChange(of: clock.offset) { _, _ in
            if clock.isScrubbing, viewportSize != .zero {
                updateOverviewTrails(
                    at: Date(),
                    forceRecording: persistentOverviewPresented
                )
            }
        }
        .onChange(of: clock.isScrubbing) { wasScrubbing, isScrubbing in
            if !wasScrubbing, isScrubbing {
                screenTrails.clear()
            }
        }
        .onChange(of: presentationMode) { oldMode, newMode in
            dismissTransientOverlay()
            session.setOverviewPropagationActive(
                newMode.presentsOverview || globalEntryArmed
            )
            if !oldMode.presentsOverview, newMode.presentsOverview {
                overviewTrails.clear()
                overviewAmbientTrails.clear()
                screenTrails.clear()
                lastOverviewTrailSample = -.infinity
            }
            if newMode == .global {
                overviewIdleBeganAt = Date()
            } else if newMode != .enteringGlobal {
                overviewAmbientTrails.clear()
                overviewIdleBeganAt = nil
            }
        }
        .onChange(of: globalEntryArmed) { _, armed in
            session.setOverviewPropagationActive(
                presentationMode.presentsOverview || armed
            )
        }
        .onChange(of: session.catalogScope) { _, _ in
            capture.cancelAcquisition()
            screenTrails.clear()
            overviewTrails.clear()
            overviewAmbientTrails.clear()
        }
        .onChange(of: session.catalogFilters) { _, _ in
            capture.cancelAcquisition()
            screenTrails.clear()
            overviewTrails.clear()
            overviewAmbientTrails.clear()
        }
        .onChange(of: isUtilityPagePresented) { _, presented in
            if presented {
                dismissTransientOverlay()
            } else {
                capture.resumeSampling()
                lastCaptureSample = -.infinity
            }
        }
    }

    /// 帧循环只发布低频状态；Canvas 绘制本身保持无副作用。
    private func updateFrame(
        at frameDate: Date,
        observationTime: Date,
        viewport: CGSize
    ) {
        let frameTime = frameDate.timeIntervalSince(startDate)
        if !clock.isLive {
            session.ephemeris.prepareSnapshot(at: observationTime)
        }
        if (persistentOverviewPresented || clock.isScrubbing),
           viewportSize != .zero,
           frameTime - lastOverviewTrailSample >= 0.1 {
            lastOverviewTrailSample = frameTime
            updateOverviewTrails(
                at: frameDate,
                forceRecording: persistentOverviewPresented
            )
        }

        guard !isUtilityPagePresented,
              !clock.isScrubbing,
              presentationMode == .local,
              frameTime - lastCaptureSample
                >= CaptureStateMachine.samplingInterval
        else { return }
        lastCaptureSample = frameTime
        #if DEBUG
        // 视觉回归的感应态在状态机第一次进入 acquiring 后冻结；普通调试与发布路径
        // 仍按真实驻留时间推进，不引入第二份捕获事实。
        if ProcessInfo.processInfo.arguments.contains("--previewSensing"),
           capture.isAcquiring {
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--previewFocusStage"),
           capture.isAcquiring,
           capture.acquisitionProgress >= 0.72 {
            return
        }
        #endif
        let sample: CaptureSample
        switch session.pointingAvailability {
        case .tracking, .manual:
            sample = captureSample(at: observationTime, in: viewport)
        case .idle, .starting, .unavailable:
            // 初始 Pointing 是占位方向；传感器尚未给出第一帧时不能误识别目标。
            sample = CaptureSample(nearest: nil, trackedDistance: nil)
        }
        capture.update(
            nearest: sample.nearest,
            trackedDistance: sample.trackedDistance,
            now: frameDate
        )
    }

    /// 进入感应范围先给一次轻而清晰的接触感，表示准星已经吸附到真实目标。
    private func acquisitionEntryHaptic() {
        ObservationHaptics.shared.softImpact(intensity: 0.28)
    }

    /// 捕获环收缩时，脉冲间隔随进度缩短；亮度和触觉使用同一进度源。
    private func updateAcquisitionHaptic(progress: Double) {
        guard capture.isAcquiring else { return }
        let now = Date()
        let p = min(1, max(0, progress))
        // 最后一拍留给完成反馈，避免两个触觉在同一帧叠加。
        guard p < 0.98 else { return }
        let interval = 0.52 - 0.36 * pow(p, 0.78)
        if let lastAcquisitionPulse,
           now.timeIntervalSince(lastAcquisitionPulse) < interval { return }
        lastAcquisitionPulse = now
        ObservationHaptics.shared.softImpact(intensity: 0.2 + 0.28 * p)
    }

    /// 自动锁定与捕获环闭合共用一次明确的刚性确认。
    private func lockHaptic() {
        ObservationHaptics.shared.rigidImpact(intensity: 0.86)
    }

    /// 叉号与 VoiceOver Escape 共用同一个关闭入口。
    private func dismissLockedTarget() {
        guard capture.isLocked else { return }
        ObservationHaptics.shared.softImpact(intensity: 0.32)
        capture.dismissCurrentTarget()
    }

    private func handleStatusWingTap() {
        guard !overviewCommitted, !archivePresentationReady else { return }
        toggleTransientOverlay(.observationStatus)
    }

    // MARK: - 底部观测动作 / 全局常驻时间标尺

    /// 地球保持既有场景进度；只有下缘仪器表面从四槽基座长成时间标尺。
    private var bottomControlBand: some View {
        ZStack(alignment: .bottom) {
            if presentationMode.presentsOverview {
                GlobalDockMorph(
                    progress: overviewPresentationProgress,
                    reducedMotion: suppressMotion,
                    interactive: presentationMode == .global,
                    clock: clock,
                    filtersActive: session.activeCatalogFilterCount > 0
                )
                    .padding(.horizontal, AppChromeMetrics.edgeInset)
                    .padding(.bottom, 8)
                    .transition(.identity)
            }

            if presentationMode == .local {
                Group {
                    if chromeState.dockMode == .targetSummary,
                       let id = capture.engagedObjectId,
                       let object = session.catalog.objectsByID[id] {
                        lockedSummaryCard(object: object, objectID: id)
                    } else {
                        localCommandColumn
                    }
                }
                .transition(.identity)
            }
        }
        .animation(
            suppressMotion ? .easeOut(duration: 0.14) : Motion.interfaceExpand,
            value: chromeState
        )
        .zIndex(2)
    }

    private func lockedSummaryCard(
        object: CatalogObject,
        objectID: String
    ) -> some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !isDismissing
            )
        ) { timeline in
            ArchiveOverlay(
                object: object,
                ephemeris: engagedDisplayEphemeris(for: objectID),
                dismissalProgress: dismissalPresentationProgress(at: timeline.date),
                onOpenArchive: {
                    if object.hasDeepArchive {
                        presentDeepArchive(for: object)
                    } else {
                        onOpenArchive()
                    }
                },
                onDismiss: dismissLockedTarget
            )
        }
        .id(objectID)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var localCommandColumn: some View {
        VStack(spacing: 10) {
            if chromeState.resetAction == .localField {
                FieldOfViewResetControl(action: resetLocalFieldOfView)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .opacity(isUtilityPagePresented ? 0 : 1)
            }

            SkyCommandDock(
                state: chromeState,
                filtersActive: session.activeCatalogFilterCount > 0,
                globalEntryEmphasized: globalEntryArmed,
                onOpenFilters: openFilters,
                onOpenObservations: openObservations,
                onEnterGlobal: enterGlobalOverview,
                onOpenSettings: openInstrument,
                showsSurface: !isUtilityPagePresented
            )
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: CommandDockFrameKey.self,
                        value: geometry.frame(in: .named("appChrome"))
                    )
                }
            }
        }
        .padding(.horizontal, AppChromeMetrics.edgeInset)
        .padding(.bottom, 8)
    }

    private func presentDeepArchive(for object: CatalogObject) {
        guard object.hasDeepArchive else { return }
        ObservationHaptics.shared.softImpact(intensity: 0.5)
        withAnimation(
            suppressMotion
                ? .easeOut(duration: 0.12)
                : .easeOut(duration: 0.24)
        ) {
            presentedStoryObjectID = object.id
            onStoryPresentationChanged(true)
        }
    }

    private func openFilters() {
        dismissTransientOverlay()
        ObservationHaptics.shared.selectionChanged()
        onOpenFilters()
    }

    private func openInstrument() {
        dismissTransientOverlay()
        ObservationHaptics.shared.selectionChanged()
        onOpenInstrument()
    }

    private func openObservations() {
        dismissTransientOverlay()
        ObservationHaptics.shared.selectionChanged()
        onOpenArchive()
    }

    private func returnToLiveFromOverview() {
        guard !clock.isReturningToLive else { return }
        // 只保留这一次回归生成的轨迹，避免与上一次拖动残影混在一起。
        screenTrails.clear()
        overviewTrails.clear()
        overviewAmbientTrails.clear()
        ObservationHaptics.shared.mediumImpact(intensity: 0.82)
        clock.returnToLive()
    }

    private func resetLocalFieldOfView() {
        ObservationHaptics.shared.lightImpact(intensity: 0.68)

        fieldMagnificationActive = false
        settledFieldMagnification = ObservationScale.defaultLocalMagnification
        globalEntryArmed = false
        globalEntryGateProgress = 0
        globalEntryHapticSent = false
        persistentOverviewProgress = 0
        overviewEntryPointing = nil
        overviewCelestialFrame = nil
        withAnimation(Motion.fieldReset) {
            fieldMagnification = ObservationScale.defaultLocalMagnification
        }
    }

    /// 顶部临时仪表仍可点击天空收起；稳定目标摘要只能使用自身叉号关闭。
    @ViewBuilder
    private var transientDismissLayer: some View {
        if transientOverlay != nil {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissTransientOverlay()
                }
                .accessibilityHidden(true)
        }
    }

    private func dismissTransientOverlay() {
        guard transientOverlay != nil else { return }
        withAnimation(
            suppressMotion ? .easeOut(duration: 0.12) : Motion.interfaceCollapse
        ) {
            transientOverlay = nil
        }
    }

    private func togglePersistentOverview() {
        switch presentationMode {
        case .local:
            enterGlobalOverview()
        case .global:
            exitOverviewToLocal()
        case .enteringGlobal, .exitingGlobal:
            break
        }
    }

    private var overviewModeAnimation: Animation {
        suppressMotion ? .easeOut(duration: 0.16) : Motion.skyOverviewMode
    }

    private var overviewModeDuration: Double {
        suppressMotion ? 0.16 : Motion.skyOverviewModeDuration
    }

    private func enterGlobalOverview() {
        guard presentationMode == .local else { return }
        ObservationHaptics.shared.mediumImpact(intensity: 0.72)
        globalEntryArmed = false
        globalEntryGateProgress = 0
        globalEntryHapticSent = false
        overviewEntryPointing = session.pointing
        overviewCelestialFrame = makeCelestialViewFrame()
        overviewAmbientTrails.clear()
        overviewIdleBeganAt = nil
        persistentOverviewProgress = 0
        presentationMode = .enteringGlobal
        dismissTransientOverlay()
        DispatchQueue.main.async {
            withAnimation(overviewModeAnimation) {
                persistentOverviewProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + overviewModeDuration) {
                guard presentationMode == .enteringGlobal else { return }
                presentationMode = .global
            }
        }
    }

    private func exitOverviewToLocal() {
        guard presentationMode == .global else { return }
        presentationMode = .exitingGlobal
        globalEntryArmed = false
        globalEntryGateProgress = 0
        globalEntryHapticSent = false
        if !clock.isLive {
            returnToLiveFromOverview()
        }
        settledFieldMagnification = ObservationScale.defaultLocalMagnification
        withAnimation(overviewModeAnimation) {
            persistentOverviewProgress = 0
            fieldMagnification = ObservationScale.defaultLocalMagnification
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + overviewModeDuration) {
            guard presentationMode == .exitingGlobal,
                  persistentOverviewProgress < 0.001
            else { return }
            presentationMode = .local
            overviewEntryPointing = nil
            overviewCelestialFrame = nil
            overviewAmbientTrails.clear()
            overviewInteractionActive = false
            overviewIdleBeganAt = nil
        }
    }

    private func makeCelestialViewFrame() -> CelestialViewFrame {
        CelestialViewFrame(
            pointing: session.pointing,
            observer: session.observer.coordinates,
            observation: clock.observationTime(realNow: Date())
        )
    }

    private func setOverviewInteractionActive(_ active: Bool) {
        guard overviewInteractionActive != active else { return }
        if active { dismissTransientOverlay() }
        overviewInteractionActive = active
        overviewAmbientTrails.clear()
        overviewIdleBeganAt = active ? nil : Date()
    }

    private func globalEntryThresholdHaptic() {
        ObservationHaptics.shared.rigidImpact(intensity: 0.38)
    }

    // MARK: - 指向读数

    /// 本地天空继续围绕灵动岛显示状态翼；全球轨道改用安全区下方的整条模式栏。
    @ViewBuilder
    private var pointingReadout: some View {
        if overviewChromeVisible {
            globalOrbitReadout
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            localPointingReadout
                .transition(.opacity)
        }
    }

    private var globalOrbitReadout: some View {
        GeometryReader { geo in
            let islandMetrics = DynamicIslandWingMetrics(viewportSize: geo.size)
            let safeTop = islandMetrics.usesIslandLayout
                ? islandMetrics.islandCenterY
                    + SkyTopBarMetrics.controlHeight / 2
                    + 10
                : max(8, geo.safeAreaInsets.top + 8)
            GlobalOrbitHeader(
                timeLabel: clock.isLive ? "LIVE" : clock.offsetLabel,
                onBack: exitOverviewToLocal
            )
            .padding(.horizontal, AppChromeMetrics.edgeInset)
            .padding(.top, safeTop)
        }
        .animation(
            suppressMotion ? .easeOut(duration: 0.14) : Motion.interfaceExpand,
            value: clock.isLive
        )
    }

    /// 顶部信息围绕灵动岛分成状态翼与姿态翼；展开内容仍留在观测空间内。
    private var localPointingReadout: some View {
        GeometryReader { geo in
            let islandMetrics = DynamicIslandWingMetrics(viewportSize: geo.size)
            let islandLayout = islandMetrics.usesIslandLayout
            ZStack(alignment: .topLeading) {
                SkyStatusIndicator(
                    mode: statusMode,
                    azimuth: statusAzimuth,
                    elevation: statusElevation,
                    presence: statusPresence,
                    activation: statusActivation,
                    updatesPaused: renderingSuspended,
                    islandLayout: islandLayout,
                    islandGapWidth: islandMetrics.islandGapWidth,
                    islandStatusWingWidth: islandMetrics.statusWingWidth,
                    islandDirectionWingWidth: islandMetrics.directionWingWidth,
                    wingHeight: islandMetrics.wingHeight,
                    wingCornerRadius: islandMetrics.wingCornerRadius,
                    onStatusTap: {
                        handleStatusWingTap()
                    },
                    onDirectionTap: { toggleTransientOverlay(.direction) }
                )
                .frame(
                    width: geo.size.width,
                    height: SkyTopBarMetrics.controlHeight
                )

                if let panel = transientOverlay {
                    let panelWidth = min(260, geo.size.width - 36)
                    let sourceCenterX = topPanelCenterX(
                        panel,
                        viewportWidth: geo.size.width,
                        metrics: islandMetrics
                    )
                    let centerX = min(
                        geo.size.width - AppChromeMetrics.edgeInset - panelWidth / 2,
                        max(AppChromeMetrics.edgeInset + panelWidth / 2, sourceCenterX)
                    )
                    topDetailPanel(
                        panel,
                        width: panelWidth,
                        cornerRadius: islandMetrics.wingCornerRadius
                    )
                        .offset(
                            x: centerX - panelWidth / 2,
                            y: SkyTopBarMetrics.controlHeight + SkyTopBarMetrics.expandedGap
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(
                .top,
                islandLayout ? islandMetrics.topPadding : max(4, geo.safeAreaInsets.top)
            )
            .animation(
                suppressMotion ? .easeOut(duration: 0.14) : Motion.interfaceExpand,
                value: transientOverlay
            )
        }
    }

    private func topPanelCenterX(
        _ panel: SkyTransientOverlay,
        viewportWidth: CGFloat,
        metrics: DynamicIslandWingMetrics
    ) -> CGFloat {
        let width = panel == .observationStatus
            ? metrics.statusWingWidth
            : metrics.directionWingWidth
        if metrics.usesIslandLayout {
            let offset = metrics.islandGapWidth / 2 + width / 2
            return viewportWidth / 2 + (panel == .observationStatus ? -offset : offset)
        }
        return panel == .observationStatus
            ? SkyTopBarMetrics.outerMargin + width / 2
            : viewportWidth - SkyTopBarMetrics.outerMargin - width / 2
    }

    /// 捕获中的事件状态优先于非阻断式环境提示，确保顶部与准星、卡片说同一种语言。
    private var statusMode: SkyStatusIndicator.Mode {
        if session.pointingAvailability == .unavailable {
            return .degraded(reason: L10n.text("sky.degraded.pointing"))
        }
        if archivePresentationReady,
           let id = capture.engagedObjectId,
           let object = session.catalog.objectsByID[id] {
            return .locked(identifier: object.cosparId, confirmedAt: lockedAt)
        }
        if capture.isAcquiring {
            return capture.acquisitionProgress < 0.28 ? .sensing : .focusing
        }
        if let reason = pointingStatusLabel {
            return .degraded(reason: reason)
        }
        return .observing
    }

    private var statusAzimuth: String {
        let az = session.pointing.azimuth * 180 / .pi
        let azNorm = az < 0 ? az + 360 : az
        return String(format: "AZ %03.0f°", azNorm)
    }

    private var statusElevation: String {
        let el = session.pointing.elevation * 180 / .pi
        return String(format: "EL %+03.0f°", el)
    }

    /// 锁定后指示器后退，把第一视觉权重让给目标档案；但绝不完全消失。
    private var statusPresence: Double {
        if overviewCommitted { return 1 }
        if archivePresentationReady { return 0.72 }
        if capture.isAcquiring { return 0.9 }
        return max(0.54, 0.86 - 0.32 * overviewPresentationProgress)
    }

    private var statusActivation: Double {
        if isDismissing {
            return 1 - dismissalPresentationProgress(at: frozenFrameDate ?? Date())
        }
        if archivePresentationReady { return 1 }
        if capture.isAcquiring { return capture.acquisitionProgress }
        return 0
    }

    private func toggleTransientOverlay(_ overlay: SkyTransientOverlay) {
        ObservationHaptics.shared.selectionChanged()
        let next = SkyTransientOverlay.toggled(
            from: transientOverlay,
            requested: overlay
        )
        let expanding = next != nil
        withAnimation(
            suppressMotion
                ? .easeOut(duration: 0.14)
                : (expanding ? Motion.interfaceExpand : Motion.interfaceCollapse)
        ) {
            transientOverlay = next
        }
    }

    private func topDetailPanel(
        _ panel: SkyTransientOverlay,
        width: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        let metrics = topPanelMetrics(for: panel)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    panel == .observationStatus
                        ? L10n.text("sky.panel.observation")
                        : L10n.text("sky.panel.direction")
                )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkHigh.opacity(0.94))
                Text(
                    panel == .observationStatus
                        ? L10n.text("sky.panel.tag.system")
                        : L10n.text("sky.panel.tag.attitude")
                )
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(Palette.inkLow.opacity(0.68))
            }
            .padding(.bottom, 8)

            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                topMetric(metric.0, metric.1)
                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(Palette.inkFaint.opacity(0.18))
                        .frame(height: 0.5)
                }
            }

            if panel == .direction {
                Text(directionGuidance)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Palette.inkLow.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Button(action: openFullInstrumentStatus) {
                HStack(spacing: 5) {
                    Text(
                        panel == .observationStatus
                            ? L10n.text("sky.panel.status")
                            : L10n.text("sky.panel.calibration")
                    )
                        .font(.system(size: 10.5, weight: .medium))
                    Spacer(minLength: 2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Palette.inkHigh.opacity(0.86))
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Palette.inkFaint.opacity(0.2))
                    .frame(height: 0.5)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 8)
        .frame(width: width, alignment: .leading)
        .background(
            Palette.voidBlack.opacity(0.12),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .modifier(
            SkyWingSurfaceModifier(
                cornerRadius: cornerRadius,
                interactive: true
            )
        )
    }

    private func topPanelMetrics(for panel: SkyTransientOverlay) -> [(String, String)] {
        switch panel {
        case .observationStatus:
            [
                (L10n.text("sky.metric.attitude"), pointingAvailabilityText),
                (L10n.text("sky.metric.heading_reference"), headingConfidenceText),
                (
                    L10n.text("sky.metric.location"),
                    session.observer.coordinates.assumed
                        ? L10n.text("sky.value.assumed")
                        : L10n.text("sky.value.live")
                ),
                (
                    L10n.text("sky.metric.orbit_age"),
                    L10n.format("sky.value.days", session.tleAgeDays)
                ),
            ]
        case .direction:
            [
                (L10n.text("sky.metric.azimuth"), statusAzimuth.replacingOccurrences(of: "AZ ", with: "")),
                (L10n.text("sky.metric.altitude"), statusElevation.replacingOccurrences(of: "EL ", with: "")),
                (L10n.text("sky.metric.field"), String(format: "%.1f×", Double(fieldMagnification))),
                (L10n.text("sky.metric.accuracy"), headingConfidenceText),
            ]
        }
    }

    private func topMetric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(Palette.inkLow.opacity(0.72))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.inkHigh.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(height: 32)
    }

    private func openFullInstrumentStatus() {
        dismissTransientOverlay()
        onOpenSystemStatus()
    }

    private var pointingAvailabilityText: String {
        switch session.pointingAvailability {
        case .idle: L10n.text("sky.value.idle")
        case .starting: L10n.text("sky.value.starting")
        case .tracking: L10n.text("sky.value.tracking")
        case .manual: L10n.text("sky.value.manual")
        case .unavailable: L10n.text("sky.value.unavailable")
        }
    }

    private var headingConfidenceText: String {
        switch session.confidence {
        case .trueNorth: L10n.text("sky.value.true_north")
        case .uncalibrated: L10n.text("sky.value.uncalibrated")
        case .manual: L10n.text("sky.value.simulated")
        }
    }

    private var directionGuidance: String {
        session.confidence == .uncalibrated
            ? L10n.text("sky.panel.direction.uncalibrated")
            : L10n.text("sky.panel.direction.guidance")
    }

    /// 只有会影响“这些点是否真的在你所指天空中”的降级才常驻提示；正常真北、
    /// 真实坐标和新鲜目录下不增加任何界面噪声。
    private var pointingStatusLabel: String? {
        // 降级说明现在是用户最先读到的一行字，因此用可直接理解的中文，
        // 并只保留最重要的一条：同时罗列多项会让顶部重新变成一串噪声。
        switch session.pointingAvailability {
        case .unavailable:
            return L10n.text("sky.degraded.pointing")
        case .manual:
            return nil
        case .idle, .starting, .tracking:
            if session.confidence == .uncalibrated {
                return L10n.text("sky.degraded.uncalibrated")
            }
        }
        if session.observer.coordinates.assumed {
            return L10n.text("sky.degraded.location_assumed")
        }
        if session.observer.coordinates.horizontalAccuracyMeters > 2_000 {
            return L10n.text("sky.degraded.location_accuracy")
        }
        if session.tleAgeDays > 14 {
            return L10n.format("sky.degraded.orbit_age", session.tleAgeDays)
        }
        return nil
    }

    private struct CaptureSample {
        var nearest: (objectId: String, angularDistance: Double)?
        var trackedDistance: Double?
    }

    /// 同一次投影同时提供“准星最近对象”和“当前感应对象自己的距离”。后者让临时
    /// 经过的更近点位不会抢走正在收缩的锁定环。
    private func captureSample(at observation: Date, in size: CGSize) -> CaptureSample {
        let projection = Projection(
            pointing: session.pointing,
            screenSize: size,
            verticalFOV: fieldVerticalFOV
        )
        var nearestID: String?
        var nearestCosine = -1.0
        var trackedCosine: Double?
        let trackedID = capture.trackedObjectId
        let fadeEndCosine = cos(Projection.fadeEnd)

        func consider(_ object: CatalogObject) {
            guard let eph = session.ephemeris.cachedEphemeris(
                object.id,
                at: observation,
                live: clock.isLive
            ),
                  eph.elevation > 0
            else { return }
            let cosine = projection.cosineOfAngularDistance(
                azimuth: eph.azimuth,
                elevation: eph.elevation
            )
            guard cosine > fadeEndCosine else { return }
            if object.id == trackedID {
                trackedCosine = cosine
            }

            if cosine > nearestCosine {
                nearestCosine = cosine
                nearestID = object.id
            }
        }

        // 主天空里的每一个点都是一个真实目录对象，捕获也直接使用同一批对象。
        // 状态机的 trackedDistance 会保持当前目标粘性，邻近星座成员不会造成闪换。
        for object in session.displayObjects {
            consider(object)
        }
        let nearest = nearestID.map { id in
            (
                objectId: id,
                angularDistance: Projection.captureAngle(
                    for: acos(nearestCosine),
                    magnification: fieldMagnification
                )
            )
        }
        let trackedDistance = trackedCosine.map {
            Projection.captureAngle(
                for: acos($0),
                magnification: fieldMagnification
            )
        }
        return CaptureSample(nearest: nearest, trackedDistance: trackedDistance)
    }

    /// 锁定结构、顶部信号和档案外壳共享同一建立进度，避免各自使用不一致的动画时钟。
    private func lockPresentationProgress(at date: Date) -> Double {
        guard let lockedAt else { return 0 }
        let raw = min(1, max(0, date.timeIntervalSince(lockedAt) / Motion.lockConfirmationDuration))
        return 1 - pow(1 - raw, 3)
    }

    /// 叉号关闭时，档案、目标结构与顶部反馈共用一段短促的收束进度。
    private func dismissalPresentationProgress(at date: Date) -> Double {
        guard case .dismissing(_, let startedAt) = capture.phase else { return 0 }
        let raw = min(
            1,
            max(0, date.timeIntervalSince(startedAt) / Motion.interfaceCollapseDuration)
        )
        return raw * raw * (3 - 2 * raw)
    }

    private func unitSmoothstep(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func relationshipBounds(in size: CGSize) -> CGRect {
        CGRect(
            x: 22,
            y: 72,
            width: max(1, size.width - 44),
            height: max(1, size.height - 72 - 142)
        )
    }

    private struct RelationshipTarget {
        let projected: Projection.Projected?
        let marker: TargetRelationshipGeometry.Marker
    }

    private func relationshipTarget(
        objectID: String,
        observation: Date,
        in size: CGSize
    ) -> RelationshipTarget? {
        guard let eph = session.ephemeris.cachedEphemeris(
            objectID,
            at: observation,
            live: clock.isLive
        ) else { return nil }
        let projection = Projection(
            pointing: session.pointing,
            screenSize: size,
            verticalFOV: fieldVerticalFOV
        )
        let projected = projection.project(
            azimuth: eph.azimuth,
            elevation: eph.elevation
        )
        let direction = projection.screenDirection(
            azimuth: eph.azimuth,
            elevation: eph.elevation
        )?.vector
        guard let marker = TargetRelationshipGeometry.marker(
            projectedPoint: projected?.point,
            direction: direction,
            inside: relationshipBounds(in: size)
        ) else { return nil }
        return RelationshipTarget(projected: projected, marker: marker)
    }

    /// 时间采样属于帧更新，不属于 Canvas 绘制副作用。
    private func updateOverviewTrails(
        at frameDate: Date,
        forceRecording: Bool = false
    ) {
        let observation = clock.observationTime(realNow: frameDate)
        let positions: [String: SIMD3<Double>]
        if let objectID = capture.engagedObjectId,
           let ephemeris = session.ephemeris.cachedEphemeris(
               objectID,
               at: observation,
               live: clock.isLive
           ) {
            positions = [objectID: ephemeris.orbitalPosition]
        } else {
            positions = [:]
        }

        overviewTrails.updateSpatial(
            offset: clock.offset,
            positions: positions,
            frameTime: frameDate.timeIntervalSince(startDate),
            forceRecording: forceRecording
        )

        let ambientAllowed = OverviewAmbientTrailPolicy.shouldRender(
            isLive: clock.isLive,
            isScrubbing: clock.isScrubbing,
            interactionActive: overviewInteractionActive,
            isTransitioning: overviewTransitioning,
            suppressMotion: suppressMotion
        )
        guard ambientAllowed,
              let idleBeganAt = overviewIdleBeganAt,
              frameDate.timeIntervalSince(idleBeganAt)
                >= OverviewAmbientTrailPolicy.idleDelay
        else {
            overviewAmbientTrails.clear()
            return
        }

        var ambientPositions: [String: SIMD3<Double>] = [:]
        ambientPositions.reserveCapacity(session.overviewTrailObjects.count)
        for object in session.overviewTrailObjects {
            if let ephemeris = session.ephemeris.cachedEphemeris(
                object.id,
                at: observation,
                live: true
            ) {
                ambientPositions[object.id] = ephemeris.orbitalPosition
            }
        }
        overviewAmbientTrails.updateSpatial(
            offset: 0,
            positions: ambientPositions,
            frameTime: frameDate.timeIntervalSince(startDate),
            forceRecording: true
        )
    }

    // MARK: - 时间镜头

    /// 单一进度同时驱动底层收束与天空球显现，避免多个动画源互相竞争。
    private var easedScrubProgress: Double {
        let p = min(1, max(0, clock.scrubPresentationProgress))
        return p * p * (3 - 2 * p)
    }

    private var overviewPresentationProgress: Double {
        max(persistentOverviewProgress, easedScrubProgress)
    }

    @ViewBuilder
    private func timeOverviewLayer(time: TimeInterval, observation: Date) -> some View {
        if persistentOverviewPresented {
            let progress = overviewPresentationProgress
            let globePresence = ObservationScale.globePresence(
                progress: progress
            )
            SkyOverviewView(
                session: session,
                clock: clock,
                observation: observation,
                frameTime: time,
                motionTime: suppressMotion ? 0 : time,
                trails: overviewTrails,
                ambientTrails: overviewAmbientTrails,
                ambientTrailsVisible: OverviewAmbientTrailPolicy.shouldRender(
                    isLive: clock.isLive,
                    isScrubbing: clock.isScrubbing,
                    interactionActive: overviewInteractionActive,
                    isTransitioning: overviewTransitioning,
                    suppressMotion: suppressMotion
                ),
                focusedObjectId: capture.engagedObjectId,
                transitionProgress: progress,
                entryPointing: overviewEntryPointing,
                celestialFrame: overviewCelestialFrame,
                transitionMotionEnabled: !suppressMotion,
                interactive: presentationMode.ownsGlobalInteraction,
                onInteractionStateChanged: setOverviewInteractionActive
            )
            .opacity(globePresence)
            .transition(
                suppressMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .identity,
                        removal: .opacity
                    )
            )
            .allowsHitTesting(
                presentationMode.ownsGlobalInteraction
            )
        }
    }

    // MARK: - Canvas 层

    @ViewBuilder
    private func canvasLayer(time: TimeInterval, observation: Date) -> some View {
        Canvas { context, size in
            let frameDate = startDate.addingTimeInterval(time)
            let lockProgress = lockPresentationProgress(at: frameDate)
            let dismissalProgress = dismissalPresentationProgress(at: frameDate)
            // REDUCED MOTION：冻结呼吸/漂移的时间轴（点位仍随指向移动）
            let motionTime = reducedMotion || systemReducedMotion ? 0 : time
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Palette.voidBlack)
            )

            let pointing = session.pointing
            let dustTransform = StarDust.skyTransform(
                pointing: pointing,
                canvasSize: size,
                verticalFOV: fieldVerticalFOV
            )
            SkyRenderer.drawDust(
                context,
                dust: dust,
                size: size,
                transform: dustTransform
            )

            // 全景已完全覆盖屏幕时，底层只保留可用于退场交叉溶解的介质背景；
            // 不再重复投影同一批 16k 目标。进出动画的中间区间仍完整绘制主天空。
            if overviewPresentationProgress > 0.985 {
                SkyRenderer.drawVignette(context, size: size)
                return
            }

            let projection = Projection(
                pointing: pointing,
                screenSize: size,
                verticalFOV: fieldVerticalFOV
            )
            let live = clock.isLive
            let engagedId = capture.engagedObjectId
            let engagedObject = engagedId.flatMap { session.catalog.objectsByID[$0] }
            let focusedFamily = engagedObject?.family
            // 投影所有对象（LIVE 用插值，非 LIVE 按观测时刻直算）
            var projected: [(
                object: CatalogObject,
                proj: Projection.Projected,
                magnitude: SkyRenderer.StarMagnitude
            )] = []
            let recordsScreenPositions = clock.isReturningToLive
            var screenPositions: [String: CGPoint] = [:]
            projected.reserveCapacity(max(64, session.displayObjects.count / 3))
            if recordsScreenPositions {
                screenPositions.reserveCapacity(
                    max(64, session.displayObjects.count / 3)
                )
            }
            // 避开灵动岛/顶部读数与底部时间坐标仪。
            let cueBounds = relationshipBounds(in: size)
            let relationship: RelationshipTarget?
            if let engagedId,
               capture.isAcquiring || capture.isLocked || isDismissing {
                relationship = relationshipTarget(
                    objectID: engagedId,
                    observation: observation,
                    in: size
                )
            } else {
                relationship = nil
            }
            @MainActor func projectObject(_ object: CatalogObject) {
                guard let eph = session.ephemeris.cachedEphemeris(object.id, at: observation, live: live),
                      eph.elevation > 0 else { return }

                if let proj = projection.project(azimuth: eph.azimuth, elevation: eph.elevation) {
                    let magnitude = StarMagnitudeScale.magnitude(
                        rangeKm: eph.rangeKm,
                        elevation: eph.elevation,
                        isCurated: object.isCurated || object.isFeatured
                    )
                    projected.append((object, proj, magnitude))
                    if recordsScreenPositions {
                        screenPositions[object.id] = proj.point
                    }
                }
            }
            for object in session.displayObjects {
                projectObject(object)
            }

            // 时间拖影：offset 变化时记录，停止后消散
            if !clock.isScrubbing,
               recordsScreenPositions || !screenTrails.isEmpty {
                screenTrails.update(
                    offset: clock.offset,
                    positions: screenPositions,
                    frameTime: time,
                    forceRecording: clock.isReturningToLive
                )
            }
            if !clock.isScrubbing, !screenTrails.isEmpty {
                for (object, _, _) in projected {
                    guard let pts = screenTrails.trails[object.id] else { continue }
                    SkyRenderer.drawTrail(
                        context,
                        points: pts,
                        frameTime: time,
                        tint: object.identityTint,
                        intensity: clock.isReturningToLive ? 0.96 : 0.55,
                        maximumSegmentLength: clock.isReturningToLive ? 60 : 44
                    )
                }
            }

            let strength = capture.strength
            let widePointScale = CGFloat(1 - 0.28 * wideFieldProgress)
            let widePointOpacity = 1 - 0.14 * wideFieldProgress

            // 轨迹弧（锁定/关闭消隐中的对象；观测时刻为中心 ±3min）
            if let id = engagedId, archivePresentationReady {
                let points = session.tracks.track(
                    for: id, observer: session.observer.coordinates, at: observation
                )
                var past: [CGPoint] = []
                var future: [CGPoint] = []
                for tp in points {
                    guard let proj = projection.project(
                        azimuth: tp.azimuth, elevation: tp.elevation
                    ) else { continue }
                    if tp.offset <= 0 { past.append(proj.point) }
                    if tp.offset >= 0 { future.append(proj.point) }
                }
                SkyRenderer.drawTrack(
                    context,
                    pastPoints: past,
                    futurePoints: future,
                    alpha: strength * (1 - 0.42 * wideFieldProgress)
                )
            }

            // 星野按星等分档批量绘制：亮度差建立深度，类别色只留在最亮档的外晕。
            // 图层数由档位数决定，与目标数量无关。
            let localFocusPoint = relationship?.projected?.point
            let localFocusProgress = archivePresentationReady
                ? 1
                : (capture.isAcquiring ? capture.acquisitionProgress : 0)
            var categoryTiers: [
                CatalogCategory: [SkyRenderer.StarMagnitude: [SkyRenderer.SatellitePoint]]
            ] = [:]
            var familyTiers: [
                CatalogFamily: [SkyRenderer.StarMagnitude: [SkyRenderer.SatellitePoint]]
            ] = [:]
            var focusedNeighborTiers: [
                SkyRenderer.StarMagnitude: [SkyRenderer.SatellitePoint]
            ] = [:]
            categoryTiers.reserveCapacity(CatalogCategory.allCases.count)
            familyTiers.reserveCapacity(CatalogFamily.allCases.count)
            for (object, proj, magnitude) in projected
            where object.id != engagedId
                && !object.isCurated
                && !object.isFeatured {
                let sample = SkyRenderer.SatellitePoint(
                    point: proj.point,
                    seed: object.noradId,
                    signature: SkyRenderer.satelliteSignature(for: object)
                )
                if capture.isAcquiring,
                   !archivePresentationReady,
                   let localFocusPoint,
                   pow(proj.point.x - localFocusPoint.x, 2)
                    + pow(proj.point.y - localFocusPoint.y, 2) < 72 * 72 {
                    focusedNeighborTiers[magnitude, default: []].append(sample)
                    continue
                }
                if let family = object.family {
                    familyTiers[family, default: [:]][magnitude, default: []].append(sample)
                } else {
                    categoryTiers[object.category, default: [:]][magnitude, default: []]
                        .append(sample)
                }
            }
            for category in CatalogCategory.allCases {
                guard let tiers = categoryTiers[category] else { continue }
                SkyRenderer.drawStarField(
                    context,
                    tiers: tiers,
                    tint: category.tint,
                    opacity: widePointOpacity,
                    visualScale: widePointScale
                )
            }
            // 大型星座整体后退一档；锁定其中一颗时，同网络的其他节点轻微前移，
            // 让"这是一片网络"这件事自己显现，而不用额外图例说明。
            for family in CatalogFamily.allCases {
                guard let tiers = familyTiers[family] else { continue }
                let emphasized = family == focusedFamily
                SkyRenderer.drawStarField(
                    context,
                    tiers: tiers,
                    tint: family.tint,
                    opacity: (emphasized ? 0.92 : 0.62) * widePointOpacity,
                    emphasis: emphasized ? 1.08 : 0.86,
                    visualScale: widePointScale
                )
            }
            SkyRenderer.drawFocusedNeighbors(
                context,
                tiers: focusedNeighborTiers,
                progress: localFocusProgress
            )

            // 精选与当前捕捉对象保留呼吸、光晕和刻度细节。
            for (object, proj, magnitude) in projected {
                let isEngaged = object.id == engagedId
                guard isEngaged
                    || object.isFeatured
                    || (object.isCurated && object.family == nil)
                else { continue }
                let tint = object.identityTint
                // 未参与捕获的精选目标仍按自身星等呈现，不因"可读"就统一提亮 ——
                // 否则档案覆盖率会变成一层与天文无关的亮度图案。
                let magnitudeFloor = 0.16 + 0.16 * Double(magnitude.rawValue)
                let brightness: Double
                if isEngaged {
                    brightness = (0.3 + 0.7 * strength) * proj.visibility
                } else {
                    brightness = magnitudeFloor * proj.visibility
                }
                SkyRenderer.drawTarget(
                    context,
                    at: proj.point,
                    brightness: brightness * (1 - 0.22 * wideFieldProgress),
                    tint: tint,
                    time: motionTime,
                    breathPhase: Double(object.id.hashValue % 628) / 100.0,
                    focusProgress: isEngaged
                        ? (archivePresentationReady ? 1 : capture.acquisitionProgress)
                        : 0,
                    locked: isEngaged && archivePresentationReady,
                    breathes: isEngaged,
                    haloStrength: (isEngaged ? 1 : 0.34)
                        * (1 - 0.38 * wideFieldProgress),
                    visualScale: widePointScale
                )

                if isEngaged && capture.isAcquiring && !archivePresentationReady {
                    let progress = capture.acquisitionProgress
                    let presence = max(0.24, strength)
                    SkyRenderer.drawAcquisitionRing(
                        context,
                        at: proj.point,
                        progress: progress,
                        presence: presence,
                        inward: CGVector(
                            dx: size.width / 2 - proj.point.x,
                            dy: size.height / 2 - proj.point.y
                        ),
                        tint: tint
                    )
                    SkyRenderer.drawFocusField(
                        context,
                        around: proj.point,
                        progress: progress,
                        tint: tint
                    )
                }
            }

            // 锁定目标离开视野后只保留这一枚暖色信标；浏览态不再显示候选箭头。
            if let id = engagedId,
               archivePresentationReady,
               let object = session.catalog.objectsByID[id],
               let relationship {
                let marker = relationship.marker
                let dismissalVisibility = 1 - unitSmoothstep(dismissalProgress)
                SkyRenderer.drawLockedMarker(
                    context,
                    at: marker.point,
                    edgeProgress: marker.edgeProgress,
                    inward: marker.inward,
                    clippedTo: cueBounds,
                    tint: object.identityTint,
                    time: motionTime,
                    confirmationProgress: lockProgress,
                    dismissalProgress: dismissalProgress,
                    showsDirectionCue: marker.isOffscreen,
                    alpha: isDismissing ? dismissalVisibility : max(0.76, strength)
                )
            }

            SkyRenderer.drawVignette(context, size: size)
        }
    }

    /// 准星始终保持在观测层，不因底部摘要出现而降权或失焦。
    private var crosshairLayer: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let targetPoint = capture.engagedObjectId.flatMap { id in
                relationshipTarget(
                    objectID: id,
                    observation: clock.observationTime(),
                    in: size
                )?.projected?.point
            }
            let response = targetPoint.map {
                CGVector(dx: $0.x - center.x, dy: $0.y - center.y)
            } ?? .zero
            let focusProgress = archivePresentationReady
                ? 1
                : (capture.isAcquiring ? capture.acquisitionProgress : 0)
            SkyRenderer.drawCrosshair(
                context,
                center: center,
                emphasis: capture.isAcquiring
                    ? capture.strength
                    : 0,
                focusProgress: focusProgress,
                response: response,
                locked: archivePresentationReady,
                presence: 1
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - 档案层

    @ViewBuilder
    private var satelliteStoryLayer: some View {
        if let id = presentedStoryObjectID,
           let object = session.catalog.objectsByID[id],
           let presentation = object.deepArchivePresentation() {
           SatelliteStoryView(
                object: object,
                story: presentation.story,
                ephemeris: engagedDisplayEphemeris(for: id),
                insight: engagedInsight?.objectID == id ? engagedInsight : nil,
                forecast: presentedPassForecast?.objectID == id
                    ? presentedPassForecast
                    : nil,
                onDismiss: {
                    withAnimation(
                        suppressMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22)
                    ) {
                        presentedStoryObjectID = nil
                        onStoryPresentationChanged(false)
                    }
                }
            )
            .transition(
                suppressMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
            )
            .zIndex(20)
        }
    }

    /// 感应阶段只在目标附近放一条识别信息；完成识别或锁定后让位给底部摘要。
    @ViewBuilder
    private func targetMicroLabelLayer(observation: Date) -> some View {
        GeometryReader { geo in
            if capture.isAcquiring,
               !archivePresentationReady,
               let id = capture.engagedObjectId,
               let object = session.catalog.objectsByID[id],
               let point = relationshipTarget(
                    objectID: id,
                    observation: observation,
                    in: geo.size
                )?.projected?.point {
                let labelWidth: CGFloat = 188
                // 标签从目标朝屏幕内侧展开：左半边向右，右半边向左。
                let placeOnRight = point.x < geo.size.width / 2
                let horizontalGap: CGFloat = 20
                let proposedX = placeOnRight
                    ? point.x + horizontalGap
                    : point.x - labelWidth - horizontalGap
                let x = min(max(12, proposedX), geo.size.width - labelWidth - 12)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let nearCrosshair = hypot(point.x - center.x, point.y - center.y) < 48
                let proposedY: CGFloat = {
                    if point.y < 132 { return point.y + 12 }
                    if point.y > geo.size.height - 205 { return point.y - 39 }
                    if nearCrosshair { return point.y + 20 }
                    return point.y - 14
                }()
                let y = min(max(96, proposedY), geo.size.height - 184)
                let labelEdgeX = placeOnRight ? x : x + labelWidth
                let labelEdgeY = y + 13.5
                let targetEdgeX = point.x + (placeOnRight ? 6 : -6)

                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: targetEdgeX, y: point.y))
                        path.addLine(
                            to: CGPoint(
                                x: targetEdgeX + (placeOnRight ? 7 : -7),
                                y: point.y
                            )
                        )
                        path.addLine(to: CGPoint(x: labelEdgeX, y: labelEdgeY))
                    }
                    .stroke(
                        object.identityTint.opacity(0.54),
                        style: StrokeStyle(lineWidth: 0.55, lineCap: .round, lineJoin: .round)
                    )

                    TargetMicroLabel(
                        object: object,
                        ephemeris: session.ephemeris.cachedEphemeris(
                            id,
                            at: observation,
                            live: clock.isLive
                        )
                    )
                    .frame(width: labelWidth)
                    .offset(x: x, y: y)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .opacity(0.36 + 0.64 * capture.acquisitionProgress)
                .id(id)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .allowsHitTesting(false)
        .animation(
            suppressMotion ? .easeOut(duration: 0.1) : Motion.interfaceExpand,
            value: capture.engagedObjectId
        )
    }

    /// 感应阶段在后台准备锁定后才需要的精确速度和轨迹。任务 id 随目标变化，
    /// 用户移开准星后旧结果不会写回新目标。
    private func prepareEngagedTargetData(for objectID: String?) async {
        engagedPreciseEphemeris = nil
        engagedInsight = nil
        guard let objectID else { return }
        let observation = clock.observationTime()
        let live = clock.isLive
        session.tracks.prepareTrack(
            for: objectID,
            observer: session.observer.coordinates,
            at: observation
        )
        async let preciseTask = session.ephemeris.preparePreciseEphemeris(
            objectID,
            at: observation,
            live: live
        )
        async let insightTask = session.insights.insight(
            for: objectID,
            observer: session.observer.coordinates,
            at: observation
        )
        let (precise, insight) = await (preciseTask, insightTask)
        guard !Task.isCancelled,
              capture.engagedObjectId == objectID
        else { return }
        engagedPreciseEphemeris = precise
        engagedInsight = insight
    }

    /// Full-day propagation belongs to the reading surface, not first focus.
    /// The task modifier cancels this work as soon as the archive closes or the
    /// selected target changes.
    private func preparePresentedForecast(for objectID: String?) async {
        presentedPassForecast = nil
        guard let objectID else { return }
        let forecast = await session.insights.forecast(
            for: objectID,
            observer: session.observer.coordinates,
            at: clock.observationTime()
        )
        guard !Task.isCancelled, presentedStoryObjectID == objectID else { return }
        presentedPassForecast = forecast
    }

    /// 方位、距离和高度跟随批量 LIVE 帧平滑更新；精确速度使用感应阶段的后台
    /// 结果。这样卡片既保持实时，也不会每个 4 秒缓存桶在主线程重新传播。
    private func engagedDisplayEphemeris(for objectID: String) -> Ephemeris? {
        let observation = clock.observationTime()
        guard var current = session.ephemeris.cachedEphemeris(
            objectID,
            at: observation,
            live: clock.isLive
        ) else {
            return engagedPreciseEphemeris
        }
        if let precise = engagedPreciseEphemeris,
           precise.objectId == objectID {
            current.velocityKmS = precise.velocityKmS
            current.altitudeKm = precise.altitudeKm
        }
        return current
    }

    private var isDismissing: Bool {
        if case .dismissing = capture.phase { return true }
        return false
    }

    /// 摘要只在自动锁定完成后显示，并在叉号触发的短收束期间保持同一对象。
    private var archivePresentationReady: Bool {
        capture.isLocked || isDismissing
    }

    // MARK: - 引导层

    @State private var lockedAt: Date?
    @AppStorage("hasEverLocked") private var hasEverLocked = false
    @State private var guideVisible = false

    @ViewBuilder
    private var guideLayer: some View {
        if !hasEverLocked {
            VStack {
                Spacer()
                Text(L10n.text("guide.capture.auto", table: "SatelliteText"))
                    .font(Typography.guide)
                    .tracking(Typography.guideTracking)
                    .foregroundStyle(Palette.inkLow.opacity(guideVisible ? Palette.Level.present : 0))
                    .animation(.easeOut(duration: 2.4), value: guideVisible)
                    .padding(.bottom, 190)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .task {
                try? await Task.sleep(for: .seconds(6))
                if !hasEverLocked { guideVisible = true }
            }
        }
    }

    // MARK: - 拖拽（模拟器指向）

    @State private var lastTranslation = CGSize.zero

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard !overviewCommitted else { return }
                guard !fieldMagnificationActive else { return }
                guard let manual = session.manualProvider else { return }
                if lastTranslation == .zero {
                    dismissTransientOverlay()
                }
                let scale = max(
                    ObservationScale.minimumLocalMagnification,
                    fieldMagnification
                )
                let delta = CGSize(
                    width: (value.translation.width - lastTranslation.width) / scale,
                    height: (value.translation.height - lastTranslation.height) / scale
                )
                lastTranslation = value.translation
                manual.drag(translation: delta)
            }
            .onEnded { value in
                guard !overviewCommitted else {
                    lastTranslation = .zero
                    return
                }
                lastTranslation = .zero
                guard !fieldMagnificationActive else { return }
                let scale = max(
                    ObservationScale.minimumLocalMagnification,
                    fieldMagnification
                )
                session.manualProvider?.endDrag(velocity: CGSize(
                    width: value.velocity.width / scale,
                    height: value.velocity.height / scale
                ))
            }
    }

    /// 统一尺度手势：先在局部天空 0.52×…4× 内连续缩放；越过最广视场后，
    /// 多余行程转换为带阻力的全局转场进度。松手未越阈值会退回局部天空。
    private var fieldMagnificationGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard presentationMode == .local, !clock.isScrubbing else { return }
                if !fieldMagnificationActive {
                    if !globalEntryArmed {
                        globalEntryHapticSent = false
                    }
                    dismissTransientOverlay()
                    fieldScaleGestureSample = value
                    fieldScaleGestureSampleDate = Date()
                    fieldScaleLogarithmicVelocity = 0
                } else {
                    let now = Date()
                    let deltaTime = now.timeIntervalSince(
                        fieldScaleGestureSampleDate
                    )
                    if deltaTime > 0.008,
                       fieldScaleGestureSample > 0,
                       value > 0 {
                        let instantaneous = log(
                            Double(value / fieldScaleGestureSample)
                        ) / deltaTime
                        fieldScaleLogarithmicVelocity =
                            fieldScaleLogarithmicVelocity * 0.62
                            + instantaneous * 0.38
                        fieldScaleGestureSample = value
                        fieldScaleGestureSampleDate = now
                    }
                }
                fieldMagnificationActive = true
                fieldMagnification = ObservationScale.localMagnification(
                    settled: settledFieldMagnification,
                    gestureScale: value
                )
                let gateProgress = GlobalEntryGatePolicy.progress(
                    settled: settledFieldMagnification,
                    gestureScale: value
                )
                globalEntryGateProgress = gateProgress

                if globalEntryArmed,
                   GlobalEntryGatePolicy.shouldDismiss(
                       magnification: fieldMagnification
                   ) {
                    withAnimation(Motion.interfaceCollapse) {
                        globalEntryArmed = false
                    }
                    globalEntryHapticSent = false
                } else if GlobalEntryGatePolicy.shouldArm(progress: gateProgress),
                          !globalEntryArmed {
                    globalEntryArmed = true
                    if !globalEntryHapticSent {
                        globalEntryHapticSent = true
                        globalEntryThresholdHaptic()
                    }
                }
            }
            .onEnded { _ in
                guard fieldMagnificationActive else { return }
                fieldMagnificationActive = false
                let projected = SpatialMotion.projectedScale(
                    current: fieldMagnification,
                    logarithmicVelocity: fieldScaleLogarithmicVelocity,
                    lowerBound: ObservationScale.minimumLocalMagnification,
                    upperBound: ObservationScale.maximumLocalMagnification
                )
                let target: CGFloat = abs(
                    projected - ObservationScale.defaultLocalMagnification
                ) < 0.055
                    ? ObservationScale.defaultLocalMagnification
                    : projected
                settledFieldMagnification = target
                if GlobalEntryGatePolicy.shouldDismiss(magnification: target) {
                    globalEntryArmed = false
                    globalEntryHapticSent = false
                }
                withAnimation(
                    suppressMotion
                        ? .easeOut(duration: 0.12)
                        : .timingCurve(
                            0.18,
                            0.72,
                            0.2,
                            1,
                            duration: SpatialMotion.scaleSettleDuration(
                                logarithmicVelocity: fieldScaleLogarithmicVelocity
                            )
                        )
                ) {
                    fieldMagnification = target
                    globalEntryGateProgress = 0
                }
            }
    }
}

#Preview {
    SkyView(session: SkySession(), capture: CaptureStateMachine(), clock: SkyClock())
}
