import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 主渲染视图：TimelineView + Canvas，30fps。
/// 完整层序：星尘 → 拖影 → 轨迹弧 → 点位/刻度环/扫描 → vignette → 锁定信标 → 十字丝 → 微型标签 → 颗粒 shader。
///
/// 两个观测维度：主天空负责指向与明确捕获，全局星图中的 TimeDial 负责选择观测时刻。
/// 非 LIVE 时全部对象按观测时刻推算；拨动时间时点位留下拖影 —— 时间方向的视觉痕迹。
struct SkyView: View {
    @ObservedObject var session: SkySession
    @ObservedObject var capture: CaptureStateMachine
    @ObservedObject var clock: SkyClock
    var onStoryPresentationChanged: (Bool) -> Void = { _ in }
    /// 设置与观测档案由上层负责呈现；档案的常驻入口统一收进设置页，
    /// 目标卡仍可按内容直接进入深度档案。
    var onOpenInstrument: () -> Void = {}
    var onOpenSystemStatus: () -> Void = {}
    var onOpenArchive: () -> Void = {}
    var initialOverviewPresented: Bool = false
    var onInitialOverviewHandled: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @AppStorage("grainEnabled") private var grainEnabled = true

    private let dust = StarDust()
    /// 时间偏移会高频发布；这些引用必须跨 View 值重建持久存在。
    @State private var startDate = Date()
    @StateObject private var screenTrails = TrailStore()
    /// 常驻星图使用较长但有界的缓存；10fps 采样，最多约 9 秒光轨。
    @StateObject private var overviewTrails = TrailStore(
        lifetime: 9,
        maximumPointsPerObject: 90,
        minimumPointDistance: 0.08
    )
    @State private var viewportSize: CGSize = .zero
    /// `presented` 表示全局图层已经插入；`committed` 表示控制权已经完成交接。
    /// 临界区只改变同一个图层的进度，不交换两棵页面树。
    @State private var persistentOverviewPresented = false
    @State private var overviewCommitted = false
    @State private var persistentOverviewProgress: Double = 0
    @State private var overviewTransitioning = false
    @State private var overviewReturnGestureActive = false
    @State private var overviewThresholdHapticSent = false
    @State private var overviewEntryPointing: Pointing?
    /// 进入全局前的局部倍率。返回时同步恢复，避免地球淡出后突然落在 0.52× 广角。
    @State private var overviewEntryMagnification: CGFloat?
    @State private var filterExpanded = false
    @State private var topPanel: TopPanel?
    /// 锁定事实与详情可见性相互独立：收起摘要不会释放目标。
    @State private var lockedDetailPresented = true
    /// 阅读面板拥有独立于准星捕获状态的短期记忆。默认识别离开阈值后，状态机可以
    /// 立即恢复探索，但卡片仍保留一小段时间，避免手持抖动打断阅读。
    @State private var retainedDetailObjectID: String?
    @State private var detailGraceDeadline: Date?
    @State private var detailPinnedByInteraction = false
    /// 设置关闭时只做随准星出现/消失的即时识别；开启后才呈现底部确认控件。
    @AppStorage("captureConfirmationEnabled") private var captureConfirmationEnabled = false
    @State private var lastOverviewTrailSample: TimeInterval = -.infinity
    @State private var lastCaptureSample: TimeInterval = -.infinity
    @State private var lastAcquisitionPulse: Date?
    @State private var fieldMagnification: CGFloat = 1
    @State private var settledFieldMagnification: CGFloat = 1
    @State private var fieldMagnificationActive = false
    @State private var fieldScaleGestureSample: CGFloat = 1
    @State private var fieldScaleGestureSampleDate = Date.distantPast
    @State private var fieldScaleLogarithmicVelocity: Double = 0
    @State private var overviewScaleModified = false
    @State private var overviewResetRequest = 0
    @State private var presentedStoryObjectID: String?
    @State private var engagedPreciseEphemeris: Ephemeris?

    private enum TopPanel: Equatable {
        case observation
        case direction
    }

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }
    private var fieldVerticalFOV: Double {
        Projection.verticalFOV(forMagnification: fieldMagnification)
    }
    private var wideFieldProgress: Double {
        ObservationScale.wideFieldProgress(magnification: fieldMagnification)
    }
    private var localChromePresence: Double {
        let wideReduction = 1 - 0.46 * wideFieldProgress
        return wideReduction * (1 - overviewPresentationProgress)
    }
    private var localBottomPresence: Double {
        ObservationScale.eased(
            (0.72 - overviewPresentationProgress) / 0.5
        )
    }
    private var localSkyPresence: Double {
        ObservationScale.localSkyPresence(
            progress: overviewPresentationProgress
        )
    }
    private var scaleResetAvailable: Bool {
        if overviewCommitted {
            return overviewScaleModified && !overviewTransitioning
        }
        return !clock.isScrubbing
            && !fieldMagnificationActive
            && abs(fieldMagnification - 1) > 0.015
    }
    /// 全局空间已经成为视觉主体后才交接顶部与底部控件。直接入口也沿用同一阈值，
    /// 避免按钮先切换、地球随后才出现。
    private var overviewChromeVisible: Bool {
        overviewCommitted && overviewPresentationProgress > 0.58
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSince(startDate)
                let obsTime = clock.observationTime(realNow: timeline.date)

                ZStack(alignment: .topLeading) {
                    canvasLayer(time: time, observation: obsTime)
                        .contentShape(Rectangle())
                        .scaleEffect(
                            suppressMotion
                                ? 1
                                : 0.9 + 0.1 * localSkyPresence
                        )
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
                    scaleTransitionCueLayer
                }
                .colorEffect(
                    ShaderLibrary.grain(
                        .float(Float(suppressMotion ? 0 : time)),
                        .float(grainEnabled ? 0.024 : 0)
                    )
                )
                .onChange(of: timeline.date) { _, frameDate in
                    let frameTime = frameDate.timeIntervalSince(startDate)
                    if !clock.isLive {
                        session.ephemeris.prepareSnapshot(at: obsTime)
                    }
                    if (persistentOverviewPresented || clock.isScrubbing),
                       viewportSize != .zero,
                       frameTime - lastOverviewTrailSample >= 0.1 {
                        lastOverviewTrailSample = frameTime
                        updateOverviewTrails(
                            at: frameDate,
                            in: viewportSize,
                            forceRecording: persistentOverviewPresented
                        )
                    }

                    // 状态机在视图更新之后驱动，不在 Canvas 绘制闭包里发布状态。
                    // 全览拖动中冻结捕捉；镜头回到天空后，无论 LIVE 或历史时刻都恢复观测。
                    if !clock.isScrubbing,
                       !overviewCommitted,
                       frameTime - lastCaptureSample >= 0.1 {
                        lastCaptureSample = frameTime
                        let sample = captureSample(at: obsTime, in: geo.size)
                        capture.update(
                            nearest: sample.nearest,
                            trackedDistance: sample.trackedDistance,
                            captureEnabled: captureConfirmationEnabled,
                            now: frameDate
                        )
                    }
                }
            }
            .onAppear { viewportSize = geo.size }
            .onChange(of: geo.size) { _, size in viewportSize = size }
        }
        .ignoresSafeArea()
        .background(Palette.voidBlack)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(fieldMagnificationGesture)
        .simultaneousGesture(lockedTargetTapGesture)
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
        .appEdgeBackGesture(
            enabled: overviewChromeVisible
                && presentedStoryObjectID == nil
        ) {
            exitOverviewToLocal()
        }
        .onAppear {
            EarthCoastlineStore.shared.prepare()
            if initialOverviewPresented {
                persistentOverviewPresented = true
                overviewCommitted = true
                persistentOverviewProgress = 1
                overviewEntryPointing = session.pointing
                overviewEntryMagnification = 1
                onInitialOverviewHandled()
            }
            if !captureConfirmationEnabled {
                if capture.isLocked {
                    requestRelease()
                } else {
                    capture.returnToExploring()
                }
            }
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--previewFocusStage") {
                captureConfirmationEnabled = true
                capture.returnToExploring()
            }
            if arguments.contains("--openFilter") {
                // 镜片只属于探索层。模拟器默认指向常常正好落在目标上，
                // 先让自动识别完成，再展开镜片，避免 acquiring / locked 的
                // 正常收拢逻辑在调试截图前把它立刻关回去。
                capture.returnToExploring()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1800))
                    filterExpanded = true
                }
            }
            if arguments.contains("--openObservationWing") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1600))
                    topPanel = .observation
                }
            } else if arguments.contains("--openDirectionWing") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1600))
                    topPanel = .direction
                }
            }
            if arguments.contains("--filterObservation") {
                session.toggleCatalogFilter(.humanScience)
            }
            if arguments.contains("--previewLockedTarget") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1400))
                    if capture.isAcquiring {
                        _ = capture.confirmAcquisition()
                    }
                }
            }
            if arguments.contains("--openOverview") {
                persistentOverviewPresented = true
                overviewCommitted = true
                persistentOverviewProgress = 1
                overviewEntryPointing = session.pointing
                overviewEntryMagnification = 1
            } else if arguments.contains("--previewWideField") {
                fieldMagnification = 0.66
                settledFieldMagnification = fieldMagnification
            } else if arguments.contains("--previewScaleThreshold") {
                fieldMagnification = ObservationScale.minimumLocalMagnification
                settledFieldMagnification = fieldMagnification
                fieldMagnificationActive = true
                persistentOverviewPresented = true
                overviewCommitted = false
                persistentOverviewProgress = 0.58
                overviewEntryPointing = session.pointing
                overviewEntryMagnification = 1
            } else if arguments.contains("--previewOverviewMode") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(550))
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
        .task(id: detailGraceDeadline) {
            guard let deadline = detailGraceDeadline else { return }
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(remaining * 1_000_000_000)
                )
            }
            guard !Task.isCancelled,
                  TargetDetailRetentionPolicy.shouldDismiss(
                      now: Date(),
                      deadline: detailGraceDeadline,
                      isPinned: detailPinnedByInteraction,
                      isCaptureActive: archivePresentationReady
                  )
            else { return }
            dismissRetainedDetail()
        }
        .onChange(of: capture.phase) { oldPhase, newPhase in
            switch newPhase {
            case .acquiring:
                withAnimation(Motion.interfaceCollapse) { topPanel = nil }
                lastAcquisitionPulse = Date()
                acquisitionEntryHaptic()
            case .locked(let objectId):
                lockedAt = Date()
                presentDetail(for: objectId)
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
                if oldPhase.isReleasing {
                    // 主动解除锁定是明确退出，不保留已经失效的摘要。
                    dismissRetainedDetail()
                } else {
                    beginDetailGracePeriod()
                }
            case .releasing:
                lastAcquisitionPulse = nil
                releaseHintVisible = false
            }
        }
        .onChange(of: capture.acquisitionProgress) { _, progress in
            updateAcquisitionHaptic(progress: progress)
        }
        .onChange(of: capture.recognitionReady) { _, ready in
            if ready, let objectID = capture.engagedObjectId {
                lockedAt = Date()
                presentDetail(for: objectID)
                hasEverLocked = true
                recognitionCompleteHaptic()
            }
        }
        .onChange(of: capture.replacementObjectId) { _, objectID in
            guard objectID != nil else { return }
            lastAcquisitionPulse = Date()
            acquisitionEntryHaptic()
        }
        .onChange(of: capture.replacementProgress) { _, progress in
            updateAcquisitionHaptic(progress: progress)
        }
        .onChange(of: clock.offset) { _, _ in
            if clock.isScrubbing, viewportSize != .zero {
                updateOverviewTrails(
                    at: Date(),
                    in: viewportSize,
                    forceRecording: persistentOverviewPresented
                )
            }
        }
        .onChange(of: clock.isScrubbing) { wasScrubbing, isScrubbing in
            if !wasScrubbing, isScrubbing {
                screenTrails.clear()
            }
        }
        .onChange(of: persistentOverviewPresented) { _, presented in
            if presented {
                overviewTrails.clear()
                screenTrails.clear()
                lastOverviewTrailSample = -.infinity
            }
        }
        .onChange(of: session.catalogScope) { _, _ in
            capture.returnToExploring()
            screenTrails.clear()
            overviewTrails.clear()
        }
        .onChange(of: session.catalogFilters) { _, _ in
            capture.returnToExploring()
            screenTrails.clear()
            overviewTrails.clear()
        }
        .onChange(of: captureConfirmationEnabled) { _, enabled in
            guard !enabled else { return }
            if capture.isLocked {
                requestRelease()
            } else {
                capture.returnToExploring()
            }
        }
    }

    /// 进入感应范围先给一次轻而清晰的接触感，表示准星已经吸附到真实目标。
    private func acquisitionEntryHaptic() {
        ObservationHaptics.shared.softImpact(intensity: 0.28)
    }

    /// 捕获环收缩时，脉冲间隔随进度缩短；亮度和触觉使用同一进度源。
    private func updateAcquisitionHaptic(progress: Double) {
        guard capture.isAcquiring || capture.isAcquiringReplacement else { return }
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

    /// 默认识别完成：捕获环闭合与完整档案出现共用一次明确的刚性确认。
    private func recognitionCompleteHaptic() {
        ObservationHaptics.shared.rigidImpact(intensity: 0.86)
    }

    /// 手动锁定与默认识别完成保持同一种触觉语义。
    private func lockHaptic() {
        ObservationHaptics.shared.rigidImpact(intensity: 0.86)
    }

    /// 所有主动退出入口汇入同一个动作：先给一次极轻的“松开”触觉，再启动统一回收序列。
    private func requestRelease() {
        guard capture.isLocked || capture.recognitionReady else { return }
        releaseHintVisible = false
        ObservationHaptics.shared.softImpact(intensity: 0.32)
        capture.releaseSignal()
    }

    private func hideLockedDetail() {
        guard retainedDetailObjectID != nil else { return }
        withAnimation(
            suppressMotion ? .easeOut(duration: 0.12) : Motion.interfaceCollapse
        ) {
            lockedDetailPresented = false
            detailGraceDeadline = nil
            detailPinnedByInteraction = false
            // 已确认锁定仍需允许用户点目标或顶部状态重新展开；即时识别已经失效时
            // 则不保留一个无法再访问的旧对象引用。
            if !archivePresentationReady {
                retainedDetailObjectID = nil
            }
        }
    }

    private func showLockedDetail() {
        guard retainedDetailObjectID != nil else { return }
        withAnimation(
            suppressMotion ? .easeOut(duration: 0.12) : Motion.interfaceExpand
        ) {
            filterExpanded = false
            topPanel = nil
            lockedDetailPresented = true
        }
    }

    /// 捕获完成时建立新的阅读对象。重新对准同一对象只取消离焦倒计时，不会撤销
    /// 用户通过点按建立的保持态；明确捕获另一对象时才开始一张新卡片。
    private func presentDetail(for objectID: String) {
        let isNewObject = retainedDetailObjectID != objectID
        retainedDetailObjectID = objectID
        detailGraceDeadline = nil
        if isNewObject {
            detailPinnedByInteraction = false
        }
        lockedDetailPresented = true
    }

    /// 准星移开只启动阅读宽限，不延长对焦状态机本身。这样新目标仍能即时感应，
    /// 当前卡片则有足够时间承受一次正常的手部晃动。
    private func beginDetailGracePeriod(now: Date = Date()) {
        guard retainedDetailObjectID != nil else { return }
        guard lockedDetailPresented else {
            dismissRetainedDetail()
            return
        }
        guard !detailPinnedByInteraction else { return }
        detailGraceDeadline = TargetDetailRetentionPolicy.deadline(after: now)
    }

    /// 点按卡片代表用户已经从“观测”进入“阅读”，此时不再依据准星位置自动收起。
    /// 关闭、下滑或主动解除锁定仍然是明确退出入口。
    private func keepDetailVisible() {
        guard retainedDetailObjectID != nil,
              lockedDetailPresented
        else { return }
        detailPinnedByInteraction = true
        detailGraceDeadline = nil
    }

    private func dismissRetainedDetail() {
        lockedDetailPresented = false
        retainedDetailObjectID = nil
        detailGraceDeadline = nil
        detailPinnedByInteraction = false
    }

    private func handleStatusWingTap() {
        guard !overviewCommitted else { return }
        if archivePresentationReady {
            showLockedDetail()
        } else {
            toggleTopPanel(.observation)
        }
    }

    // MARK: - 底部观测动作 / 全局时间标尺

    /// 主天空与全局星图共享同一个底部槽位，但职责不混合：主天空只表达捕获意图，
    /// 全局星图才提供时间旅行。这样主页面不会在无全局语境时意外停留于过去/未来。
    private var bottomControlBand: some View {
        Group {
            if overviewChromeVisible {
                overviewControlColumn
                    .opacity(overviewPresentationProgress)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if lockedDetailPresented,
                      let id = retainedDetailObjectID,
                      let object = session.catalog.objectsByID[id] {
                lockedSummaryCard(object: object, objectID: id)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                skyControlRow
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
            }
        }
        .animation(Motion.interfaceCollapse, value: overviewCommitted)
        .animation(Motion.interfaceExpand, value: archivePresentationReady)
        .zIndex(2)
    }

    private func lockedSummaryCard(
        object: CatalogObject,
        objectID: String
    ) -> some View {
        ArchiveOverlay(
            object: object,
            ephemeris: engagedDisplayEphemeris(for: objectID),
            revealed: lockedDetailPresented,
            captured: detailRepresentsCapturedTarget(objectID) && !isReleasing,
            retainedByInteraction: detailPinnedByInteraction,
            releaseProgress: releasePresentationProgress(at: Date()),
            onOpenArchive: {
                if object.hasDeepArchive {
                    presentDeepArchive(for: object)
                } else {
                    onOpenArchive()
                }
            },
            onInteraction: keepDetailVisible,
            onDismiss: hideLockedDetail,
            onRelease: requestRelease
        )
        .id(objectID)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// 全局星图底部只承担时间旅行、视场操作和设置；返回统一移到左上角。
    private var overviewControlColumn: some View {
        VStack(spacing: 0) {
            timeDial

            ZStack {
                HStack {
                    Spacer(minLength: 0)
                    instrumentEntry
                }

                if !clock.isLive {
                    ReturnToLiveControl(
                        returning: clock.isReturningToLive,
                        action: returnToLiveFromCapsule
                    )
                } else if scaleResetAvailable {
                    FieldOfViewResetControl(action: resetActiveFieldOfView)
                }
            }
            .frame(height: AppChromeMetrics.controlHeight)
            .padding(.horizontal, AppChromeMetrics.edgeInset)
            .padding(.top, 7)
        }
        .background(Palette.voidBlack.opacity(0.97))
        .padding(.bottom, 8)
    }

    /// 探索态只保留筛选和设置；观测记录由设置页的摘要进入。
    /// 锁定后这一整组退出，由目标摘要接管底部。
    ///
    /// 左侧范围、中间主动作和右侧设置永远共用一条基线。中间没有当前动作时保持
    /// 为空，不再用无效按钮补齐构图。
    private var skyControlRow: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: AppChromeMetrics.itemSpacing) {
                    skyControlRowContent
                }
            } else {
                skyControlRowContent
            }
        }
        .padding(.horizontal, AppChromeMetrics.edgeInset)
        .padding(.bottom, 8)
        .opacity(filterExpanded ? 1 : localBottomPresence)
        .animation(Motion.interfaceCollapse, value: filterExpanded)
        .animation(Motion.interfaceExpand, value: focusActionMode)
        .animation(Motion.interfaceCollapse, value: scaleResetAvailable)
    }

    private var skyControlRowContent: some View {
        HStack(spacing: 0) {
            filterPort

            Spacer(minLength: AppChromeMetrics.itemSpacing)

            if !filterExpanded {
                primaryBottomAction
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.94, anchor: .bottom)
                        )
                    )

                Spacer(minLength: AppChromeMetrics.itemSpacing)

                instrumentEntry
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            }
        }
        .frame(height: AppChromeMetrics.controlHeight, alignment: .bottom)
    }

    /// 紧凑入口只占一枚横向胶囊；展开内容由同一外壳向上生长。
    private var filterPort: some View {
        Color.clear
            .frame(
                width: CatalogFilterControl.collapsedSize,
                height: SkyTopBarMetrics.controlHeight
            )
            .overlay(alignment: .bottomLeading) {
                CatalogFilterControl(
                    scope: session.catalogScope,
                    selections: session.catalogFilters,
                    resultCount: session.visibleObjects.count,
                    expanded: filterExpanded,
                    onToggle: { setFilterExpanded(!filterExpanded) },
                    onSelectScope: session.setCatalogScope,
                    onToggleFilter: session.toggleCatalogFilter,
                    onReset: session.resetCatalogFilters,
                    onClose: { setFilterExpanded(false) },
                    presence: filterChromeOpacity
                )
                .fixedSize()
                .animation(.easeOut(duration: 0.24), value: filterChromeOpacity)
            }
    }

    /// 主天空和全局星图唯一的右下常驻入口。
    private var instrumentEntry: some View {
        utilityButton(symbol: "slider.horizontal.3", action: onOpenInstrument)
        .opacity(observationChromeOpacity)
        .accessibilityLabel("打开仪器状态与设置")
        .accessibilityHint("进入设置、观测记录与帮助")
    }

    @ViewBuilder
    private func utilityButton(symbol: String, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: AppChromeMetrics.compactCornerRadius,
            style: .continuous
        )
        let button = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkMid.opacity(0.9))
                .frame(
                    width: AppChromeMetrics.controlHeight,
                    height: AppChromeMetrics.controlHeight
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)

        if #available(iOS 26.0, *) {
            button
                .glassEffect(
                    .regular
                        .tint(Palette.voidBlack.opacity(0.1))
                        .interactive(),
                    in: .rect(cornerRadius: AppChromeMetrics.compactCornerRadius)
                )
                .overlay {
                    shape.stroke(
                        Palette.inkFaint.opacity(0.29),
                        lineWidth: AppChromeMetrics.strokeWidth
                    )
                }
        } else {
            button
                .background(.ultraThinMaterial, in: shape)
                .background(Palette.voidBlack.opacity(0.72), in: shape)
                .overlay {
                    shape.stroke(Palette.inkFaint.opacity(0.34), lineWidth: 0.6)
                }
        }
    }

    @ViewBuilder
    private var primaryBottomAction: some View {
        if persistentOverviewProgress < 0.05 {
            if captureConfirmationEnabled, focusActionMode.isInteractive {
                FocusActionControl(
                    mode: focusActionMode,
                    action: performFocusAction
                )
            } else if scaleResetAvailable {
                FieldOfViewResetControl(action: resetActiveFieldOfView)
            }
        }
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

    private var focusActionMode: FocusActionMode {
        if isReleasing { return .releasing }
        if capture.isAcquiringReplacement {
            return .replace(progress: capture.replacementProgress)
        }
        if capture.isLocked {
            return .captured
        }
        if capture.isAcquiring {
            return .confirm(progress: capture.acquisitionProgress)
        }
        return .seeking
    }

    private func performFocusAction() {
        if capture.isAcquiringReplacement {
            _ = capture.confirmReplacement()
        } else if capture.isAcquiring {
            _ = capture.confirmAcquisition()
        }
    }

    private var captureSecondaryMode: CaptureSecondaryMode {
        isReleasing ? .cancelling : .cancelCapture
    }

    private func performSecondaryCaptureAction() {
        if capture.isLocked || capture.recognitionReady {
            requestRelease()
        }
    }

    private var timeDial: some View {
        TimeDial(clock: clock)
            .overlay {
                if filterExpanded {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { setFilterExpanded(false) }
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.24), value: clock.isLive)
            .animation(
                scaleResetAvailable ? Motion.interfaceExpand : Motion.interfaceCollapse,
                value: scaleResetAvailable
            )
    }

    private func returnToLiveFromCapsule() {
        guard !clock.isReturningToLive else { return }
        // 只保留这一次回归生成的轨迹，避免与上一次拖动残影混在一起。
        screenTrails.clear()
        overviewTrails.clear()
        ObservationHaptics.shared.mediumImpact(intensity: 0.82)
        clock.returnToLive()
    }

    private func resetActiveFieldOfView() {
        ObservationHaptics.shared.lightImpact(intensity: 0.68)

        if overviewCommitted {
            overviewResetRequest &+= 1
        } else {
            fieldMagnificationActive = false
            settledFieldMagnification = 1
            persistentOverviewProgress = 0
            persistentOverviewPresented = false
            overviewEntryPointing = nil
            overviewEntryMagnification = nil
            withAnimation(Motion.fieldReset) {
                fieldMagnification = 1
            }
        }
    }

    /// 顶部详情和筛选共享同一块空白区域关闭层；实际控件绘制在它上方。
    @ViewBuilder
    private var transientDismissLayer: some View {
        if filterExpanded || topPanel != nil {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(Motion.interfaceCollapse) {
                        filterExpanded = false
                        topPanel = nil
                    }
                }
                .accessibilityHidden(true)
        }
    }

    /// 捕获中镜片仍然可用，但退到背景层：它不与目标身份争夺第一视觉权重。
    private var filterChromeOpacity: Double {
        let stateOpacity: Double
        if capture.isLocked || isReleasing {
            stateOpacity = 0.4
        } else if capture.isAcquiring {
            stateOpacity = 0.58
        } else {
            stateOpacity = session.activeCatalogFilterCount == 0 ? 0.88 : 1
        }
        return stateOpacity * max(0.46, localChromePresence)
    }

    private func setFilterExpanded(_ expanded: Bool) {
        let animation: Animation = suppressMotion
            ? .easeOut(duration: 0.14)
            : (expanded ? Motion.interfaceExpand : Motion.interfaceCollapse)
        withAnimation(animation) {
            if expanded { topPanel = nil }
            filterExpanded = expanded
        }
    }

    /// 两侧入口常驻，但在感应与锁定时主动降到背景层。入口仍可用，不与目标信息
    /// 争夺第一视觉权重。
    private var observationChromeOpacity: Double {
        if overviewCommitted { return 1 }
        if capture.isLocked || isReleasing { return 0.28 }
        if capture.isAcquiring { return 0.46 }
        return max(0.42, localChromePresence)
    }

    private func togglePersistentOverview() {
        guard !overviewTransitioning else { return }
        if overviewCommitted {
            exitOverviewToLocal()
        } else {
            commitOverview()
        }
    }

    private var overviewModeAnimation: Animation {
        suppressMotion ? .easeOut(duration: 0.16) : Motion.skyOverviewMode
    }

    private var overviewModeDuration: Double {
        suppressMotion ? 0.16 : Motion.skyOverviewModeDuration
    }

    private func prepareOverviewLayer() {
        guard !persistentOverviewPresented else { return }
        overviewEntryPointing = session.pointing
        overviewEntryMagnification = settledFieldMagnification
        persistentOverviewProgress = 0
        persistentOverviewPresented = true
        withAnimation(Motion.interfaceCollapse) {
            filterExpanded = false
            topPanel = nil
        }
    }

    private func commitOverview() {
        prepareOverviewLayer()
        overviewCommitted = true
        overviewTransitioning = true
        overviewReturnGestureActive = false
        DispatchQueue.main.async {
            withAnimation(overviewModeAnimation) {
                persistentOverviewProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + overviewModeDuration) {
                guard overviewCommitted else { return }
                overviewTransitioning = false
            }
        }
    }

    private func exitOverviewToLocal() {
        guard persistentOverviewPresented else { return }
        let returnMagnification = overviewEntryMagnification ?? 1
        overviewTransitioning = true
        overviewReturnGestureActive = false
        if !clock.isLive {
            returnToLiveFromCapsule()
        }
        settledFieldMagnification = returnMagnification
        withAnimation(overviewModeAnimation) {
            persistentOverviewProgress = 0
            fieldMagnification = returnMagnification
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + overviewModeDuration) {
            guard persistentOverviewProgress < 0.001 else { return }
            overviewCommitted = false
            persistentOverviewPresented = false
            overviewTransitioning = false
            overviewEntryPointing = nil
            overviewEntryMagnification = nil
        }
    }

    private func updateOverviewScaleGesture(progress: Double) {
        guard !overviewCommitted else { return }
        if progress > 0.001 {
            prepareOverviewLayer()
        }
        persistentOverviewProgress = progress
        if ObservationScale.shouldCommit(progress), !overviewThresholdHapticSent {
            overviewThresholdHapticSent = true
            scaleThresholdHaptic()
        }
    }

    private func finishOverviewScaleGesture() {
        if ObservationScale.shouldCommit(persistentOverviewProgress) {
            commitOverview()
        } else {
            withAnimation(suppressMotion ? .easeOut(duration: 0.12) : Motion.scaleThresholdReturn) {
                persistentOverviewProgress = 0
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (suppressMotion ? 0.12 : Motion.scaleThresholdReturnDuration)
            ) {
                guard !overviewCommitted, persistentOverviewProgress < 0.001 else { return }
                persistentOverviewPresented = false
                overviewEntryPointing = nil
                overviewEntryMagnification = nil
            }
        }
    }

    private func updateOverviewReturnGesture(progress: Double) {
        guard overviewCommitted else { return }
        if progress <= 0.001, !overviewReturnGestureActive {
            overviewThresholdHapticSent = false
        }
        overviewReturnGestureActive = progress > 0.001
        persistentOverviewProgress = 1 - progress
        if ObservationScale.shouldCommit(progress), !overviewThresholdHapticSent {
            overviewThresholdHapticSent = true
            scaleThresholdHaptic()
        }
    }

    private func finishOverviewReturnGesture(commit: Bool) {
        let hadReturnProgress = overviewReturnGestureActive
            || persistentOverviewProgress < 0.999
        overviewReturnGestureActive = false
        guard hadReturnProgress else { return }
        if commit {
            exitOverviewToLocal()
        } else {
            overviewTransitioning = true
            withAnimation(suppressMotion ? .easeOut(duration: 0.12) : Motion.scaleThresholdReturn) {
                persistentOverviewProgress = 1
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (suppressMotion ? 0.12 : Motion.scaleThresholdReturnDuration)
            ) {
                overviewTransitioning = false
            }
        }
    }

    private func scaleThresholdHaptic() {
        ObservationHaptics.shared.rigidImpact(intensity: 0.38)
    }

    // MARK: - 指向读数

    /// 顶部信息围绕灵动岛分成状态翼与姿态翼；展开内容仍留在观测空间内。
    private var pointingReadout: some View {
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
                    islandLayout: islandLayout,
                    islandGapWidth: islandMetrics.islandGapWidth,
                    islandStatusWingWidth: islandMetrics.statusWingWidth,
                    islandDirectionWingWidth: islandMetrics.directionWingWidth,
                    wingHeight: islandMetrics.wingHeight,
                    wingCornerRadius: islandMetrics.wingCornerRadius,
                    backTitle: overviewChromeVisible ? "天空" : nil,
                    onBack: overviewChromeVisible ? exitOverviewToLocal : nil,
                    onStatusTap: {
                        handleStatusWingTap()
                    },
                    onDirectionTap: { toggleTopPanel(.direction) }
                )
                .frame(
                    width: geo.size.width,
                    height: SkyTopBarMetrics.controlHeight
                )

                if let topPanel {
                    let panelWidth = topPanel == .observation
                        ? islandMetrics.statusWingWidth
                        : islandMetrics.directionWingWidth
                    let centerX = topPanelCenterX(
                        topPanel,
                        viewportWidth: geo.size.width,
                        metrics: islandMetrics
                    )
                    topDetailPanel(
                        topPanel,
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
                value: topPanel
            )
        }
    }

    private func topPanelCenterX(
        _ panel: TopPanel,
        viewportWidth: CGFloat,
        metrics: DynamicIslandWingMetrics
    ) -> CGFloat {
        let width = panel == .observation
            ? metrics.statusWingWidth
            : metrics.directionWingWidth
        if metrics.usesIslandLayout {
            let offset = metrics.islandGapWidth / 2 + width / 2
            return viewportWidth / 2 + (panel == .observation ? -offset : offset)
        }
        return panel == .observation
            ? SkyTopBarMetrics.outerMargin + width / 2
            : viewportWidth - SkyTopBarMetrics.outerMargin - width / 2
    }

    /// 捕获中的事件状态优先于非阻断式环境提示，确保顶部与准星、卡片说同一种语言。
    private var statusMode: SkyStatusIndicator.Mode {
        if session.pointingAvailability == .unavailable {
            return .degraded(reason: "姿态不可用 · 方向仅供参考")
        }
        if overviewChromeVisible {
            return .field(timeLabel: clock.isLive ? "全局星图 · 此刻" : "全局星图 · \(clock.offsetLabel)")
        }
        if archivePresentationReady,
           let id = capture.engagedObjectId,
           let object = session.catalog.objectsByID[id] {
            if isReleasing {
                return .releasing(identifier: object.cosparId)
            }
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
        if archivePresentationReady { return 1 }
        if capture.isAcquiring { return capture.acquisitionProgress }
        return 0
    }

    private func toggleTopPanel(_ panel: TopPanel) {
        ObservationHaptics.shared.selectionChanged()
        withAnimation(
            suppressMotion ? .easeOut(duration: 0.14) : Motion.interfaceExpand
        ) {
            filterExpanded = false
            topPanel = topPanel == panel ? nil : panel
        }
    }

    private func topDetailPanel(
        _ panel: TopPanel,
        width: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        let metrics = topPanelMetrics(for: panel)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(panel == .observation ? "观测状态" : "方向与精度")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkHigh.opacity(0.94))
                Text(panel == .observation ? "SYSTEM" : "ATTITUDE")
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
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
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(Palette.inkLow.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Button(action: openFullInstrumentStatus) {
                HStack(spacing: 5) {
                    Text(panel == .observation ? "完整状态" : "查看校准")
                        .font(.system(size: 8.5, weight: .medium))
                    Spacer(minLength: 2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7.5, weight: .semibold))
                }
                .foregroundStyle(Palette.inkHigh.opacity(0.86))
                .frame(height: 30)
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
        .padding(.horizontal, 9)
        .padding(.top, 10)
        .padding(.bottom, 4)
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

    private func topPanelMetrics(for panel: TopPanel) -> [(String, String)] {
        switch panel {
        case .observation:
            [
                ("姿态", pointingAvailabilityText),
                ("方位参考", headingConfidenceText),
                ("定位", session.observer.coordinates.assumed ? "估算" : "实时"),
                ("轨道龄期", "\(session.tleAgeDays) 天"),
            ]
        case .direction:
            [
                ("方位", statusAzimuth.replacingOccurrences(of: "AZ ", with: "")),
                ("仰角", statusElevation.replacingOccurrences(of: "EL ", with: "")),
                ("视场", String(format: "%.1f×", Double(fieldMagnification))),
                ("精度", headingConfidenceText),
            ]
        }
    }

    private func topMetric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 7.5, weight: .regular))
                .foregroundStyle(Palette.inkLow.opacity(0.72))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.inkHigh.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(height: 26)
    }

    private func openFullInstrumentStatus() {
        withAnimation(Motion.interfaceCollapse) { topPanel = nil }
        onOpenSystemStatus()
    }

    private var pointingAvailabilityText: String {
        switch session.pointingAvailability {
        case .idle: "空闲"
        case .starting: "启动中"
        case .tracking: "追踪中"
        case .manual: "手动"
        case .unavailable: "不可用"
        }
    }

    private var headingConfidenceText: String {
        switch session.confidence {
        case .trueNorth: "真北"
        case .uncalibrated: "待校准"
        case .manual: "模拟"
        }
    }

    private var directionGuidance: String {
        session.confidence == .uncalibrated ? "画 8 字校准并查看详情" : "查看完整姿态信息"
    }

    /// 只有会影响“这些点是否真的在你所指天空中”的降级才常驻提示；正常真北、
    /// 真实坐标和新鲜目录下不增加任何界面噪声。
    private var pointingStatusLabel: String? {
        // 降级说明现在是用户最先读到的一行字，因此用可直接理解的中文，
        // 并只保留最重要的一条：同时罗列多项会让顶部重新变成一串噪声。
        switch session.pointingAvailability {
        case .unavailable:
            return "姿态不可用 · 方向仅供参考"
        case .manual:
            return nil
        case .idle, .starting, .tracking:
            if session.confidence == .uncalibrated {
                return "指向未校准 · 画 8 字校准"
            }
        }
        if session.observer.coordinates.assumed {
            return "位置为估算值"
        }
        if session.tleAgeDays > 14 {
            return "轨道数据已 \(session.tleAgeDays) 天"
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
        var nearest: (objectId: String, angularDistance: Double)?
        var trackedDistance: Double?
        let trackedID = capture.engagedObjectId

        func consider(_ object: CatalogObject) {
            guard let eph = session.ephemeris.cachedEphemeris(
                object.id,
                at: observation,
                live: clock.isLive
            ),
                  eph.elevation > 0
            else { return }
            let angularDistance = projection.angularDistance(
                azimuth: eph.azimuth,
                elevation: eph.elevation
            )
            guard angularDistance < Projection.fadeEnd else { return }
            let captureAngle = Projection.captureAngle(
                for: angularDistance,
                magnification: fieldMagnification
            )
            if object.id == trackedID {
                trackedDistance = captureAngle
            }

            if nearest == nil || captureAngle < nearest!.angularDistance {
                nearest = (object.id, captureAngle)
            }
        }

        // 主天空里的每一个点都是一个真实目录对象，捕获也直接使用同一批对象。
        // 状态机的 trackedDistance 会保持当前目标粘性，邻近星座成员不会造成闪换。
        for object in session.displayObjects {
            consider(object)
        }
        return CaptureSample(nearest: nearest, trackedDistance: trackedDistance)
    }

    /// 锁定结构、联系线和档案外壳共享同一确认进度，避免各自使用不一致的动画时钟。
    private func lockPresentationProgress(at date: Date) -> Double {
        guard let lockedAt else { return 0 }
        let raw = min(1, max(0, date.timeIntervalSince(lockedAt) / Motion.lockConfirmationDuration))
        return 1 - pow(1 - raw, 3)
    }

    /// 主动归还共享同一平滑进度；文字、线与标记只在各自区间内响应它。
    private func releasePresentationProgress(at date: Date) -> Double {
        guard case .releasing(_, let startedAt) = capture.phase else { return 0 }
        let raw = min(1, max(0, date.timeIntervalSince(startedAt) / Motion.releaseDuration))
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
        in size: CGSize,
        forceRecording: Bool = false
    ) {
        let observation = clock.observationTime(realNow: frameDate)
        var positions: [String: SIMD3<Double>] = [:]
        positions.reserveCapacity(session.visibleTrailObjects.count)

        for object in session.visibleTrailObjects {
            guard let eph = session.ephemeris.cachedEphemeris(
                object.id,
                at: observation,
                live: false
            ) else { continue }
            positions[object.id] = eph.orbitalPosition
        }

        overviewTrails.updateSpatial(
            offset: clock.offset,
            positions: positions,
            frameTime: frameDate.timeIntervalSince(startDate),
            forceRecording: forceRecording
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
                focusedObjectId: capture.engagedObjectId,
                scaleModified: $overviewScaleModified,
                resetRequest: overviewResetRequest,
                transitionProgress: progress,
                entryPointing: overviewEntryPointing,
                transitionMotionEnabled: !suppressMotion,
                interactive: overviewCommitted
                    && (!overviewTransitioning || overviewReturnGestureActive),
                onScaleReturnChanged: updateOverviewReturnGesture,
                onScaleReturnEnded: finishOverviewReturnGesture
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
                overviewCommitted
                    && (!overviewTransitioning || overviewReturnGestureActive)
            )
        }
    }

    @ViewBuilder
    private var scaleTransitionCueLayer: some View {
        if persistentOverviewPresented,
           !overviewCommitted,
           persistentOverviewProgress > 0.04 {
            let p = persistentOverviewProgress
            VStack(spacing: 8) {
                Spacer()
                Text("继续缩小 · 查看完整轨道")
                    .font(Typography.statusTag)
                    .tracking(0.8)
                    .foregroundStyle(Palette.inkMid.opacity(0.48 + 0.4 * p))

                HStack(spacing: 7) {
                    Rectangle()
                        .frame(width: 28, height: 0.5)
                    Circle()
                        .frame(width: 4, height: 4)
                    Rectangle()
                        .frame(width: 28, height: 0.5)
                    Text("±24H")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .tracking(0.7)
                }
                .foregroundStyle(Palette.signal.opacity(0.26 + 0.38 * p))
            }
            .padding(.bottom, 164)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(ObservationScale.eased((p - 0.08) / 0.42))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Canvas 层

    @ViewBuilder
    private func canvasLayer(time: TimeInterval, observation: Date) -> some View {
        Canvas { context, size in
            let frameDate = startDate.addingTimeInterval(time)
            let lockProgress = lockPresentationProgress(at: frameDate)
            let releaseProgress = releasePresentationProgress(at: frameDate)
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
               capture.isAcquiring || capture.isLocked || isReleasing {
                relationship = relationshipTarget(
                    objectID: engagedId,
                    observation: observation,
                    in: size
                )
            } else {
                relationship = nil
            }
            let replacementId = capture.replacementObjectId
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

            // 轨迹弧（锁定/释放中的对象；观测时刻为中心 ±3min）
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
                && object.id != replacementId
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
                let isReplacement = object.id == replacementId
                guard isEngaged
                    || isReplacement
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
                } else if isReplacement {
                    brightness = (0.38 + 0.5 * capture.replacementProgress) * proj.visibility
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
                        : (isReplacement ? capture.replacementProgress : 0),
                    locked: isEngaged && archivePresentationReady,
                    breathes: isEngaged || isReplacement,
                    haloStrength: (isEngaged || isReplacement ? 1 : 0.34)
                        * (1 - 0.38 * wideFieldProgress),
                    visualScale: widePointScale
                )

                if (isEngaged && capture.isAcquiring && !archivePresentationReady)
                    || isReplacement {
                    let progress = isReplacement
                        ? capture.replacementProgress
                        : capture.acquisitionProgress
                    let presence = isReplacement
                        ? max(0.3, capture.replacementProgress)
                        : max(0.24, strength)
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
                let releaseVisibility = 1 - unitSmoothstep((releaseProgress - 0.46) / 0.54)
                SkyRenderer.drawLockedMarker(
                    context,
                    at: marker.point,
                    edgeProgress: marker.edgeProgress,
                    inward: marker.inward,
                    clippedTo: cueBounds,
                    tint: object.identityTint,
                    time: motionTime,
                    confirmationProgress: lockProgress,
                    releaseProgress: releaseProgress,
                    showsDirectionCue: marker.isOffscreen,
                    alpha: isReleasing ? releaseVisibility : max(0.76, strength)
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
                    : capture.replacementProgress,
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
           let story = object.deepArchiveStory {
           SatelliteStoryView(
                object: object,
                story: story,
                ephemeris: engagedDisplayEphemeris(for: id),
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
               !filterExpanded,
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
        guard let objectID else { return }
        let observation = clock.observationTime()
        let live = clock.isLive
        session.tracks.prepareTrack(
            for: objectID,
            observer: session.observer.coordinates,
            at: observation
        )
        let precise = await session.ephemeris.preparePreciseEphemeris(
            objectID,
            at: observation,
            live: live
        )
        guard !Task.isCancelled,
              capture.engagedObjectId == objectID
        else { return }
        engagedPreciseEphemeris = precise
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
        }
        return current
    }

    private var isReleasing: Bool {
        if case .releasing = capture.phase { return true }
        return false
    }

    /// 面板只有两种状态：隐藏，或完整显示。默认模式等待圆环完全收束；
    /// 手动确认模式等待用户真正锁定，不再在 acquiring 中插入半张档案。
    private var archivePresentationReady: Bool {
        capture.isLocked
            || isReleasing
            || (!captureConfirmationEnabled && capture.recognitionReady)
    }

    private func detailRepresentsCapturedTarget(_ objectID: String) -> Bool {
        capture.lockedObjectId == objectID
            || (!captureConfirmationEnabled
                && capture.engagedObjectId == objectID
                && capture.recognitionReady)
    }

    // MARK: - 引导层

    @State private var lockedAt: Date?
    @AppStorage("hasEverLocked") private var hasEverLocked = false
    @AppStorage("releaseHintShown") private var releaseHintShown = 0
    @State private var guideVisible = false
    @State private var releaseHintVisible = false

    @ViewBuilder
    private var guideLayer: some View {
        if !hasEverLocked {
            VStack {
                Spacer()
                Text(
                    captureConfirmationEnabled
                        ? "对准目标，再确认持续捕获。"
                        : "将准星移向目标，档案会随视线出现。"
                )
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
        } else if releaseHintShown < 3 {
            // 释放提示：锁定驻留 6s 后浮现，教一次观测语言。最多出现三次。
            VStack {
                Spacer()
                Text("对准另一目标切换，或取消当前捕获。")
                    .font(Typography.guide)
                    .tracking(Typography.guideTracking)
                    .foregroundStyle(Palette.inkLow.opacity(releaseHintVisible ? Palette.Level.faint : 0))
                    .animation(.easeOut(duration: 2.4), value: releaseHintVisible)
                    .padding(.bottom, 190)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .onChange(of: capture.isLocked) { _, locked in
                if !locked { releaseHintVisible = false }
            }
            .task(id: capture.isLocked) {
                guard capture.isLocked else { return }
                try? await Task.sleep(for: .seconds(6))
                if capture.isLocked {
                    releaseHintVisible = true
                    releaseHintShown += 1
                }
            }
        }
    }

    // MARK: - 拖拽（模拟器指向）

    @State private var lastTranslation = CGSize.zero

    private var lockedTargetTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard archivePresentationReady,
                      !lockedDetailPresented,
                      !overviewCommitted,
                      let objectID = capture.engagedObjectId,
                      viewportSize != .zero,
                      let projected = relationshipTarget(
                          objectID: objectID,
                          observation: clock.observationTime(),
                          in: viewportSize
                      )?.projected?.point
                else { return }

                let distance = hypot(
                    value.location.x - projected.x,
                    value.location.y - projected.y
                )
                guard distance <= 36 else { return }
                showLockedDetail()
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard !overviewCommitted else { return }
                guard !fieldMagnificationActive else { return }
                guard let manual = session.manualProvider else { return }
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
                guard !overviewCommitted, !clock.isScrubbing else { return }
                if !fieldMagnificationActive {
                    overviewThresholdHapticSent = false
                    if filterExpanded {
                        withAnimation(Motion.interfaceCollapse) {
                            filterExpanded = false
                        }
                    }
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
                updateOverviewScaleGesture(
                    progress: ObservationScale.overviewProgress(
                        settled: settledFieldMagnification,
                        gestureScale: value
                    )
                )
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
                let target: CGFloat = abs(projected - 1) < 0.055
                    ? 1
                    : projected
                settledFieldMagnification = target
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
                }
                finishOverviewScaleGesture()
            }
    }
}

/// 详情阅读的短暂离焦容忍。它是纯值策略，避免把阅读寿命重新耦合到捕获阈值。
enum TargetDetailRetentionPolicy {
    static let graceDuration: TimeInterval = 3

    static func deadline(after date: Date) -> Date {
        date.addingTimeInterval(graceDuration)
    }

    static func shouldDismiss(
        now: Date,
        deadline: Date?,
        isPinned: Bool,
        isCaptureActive: Bool
    ) -> Bool {
        guard !isPinned,
              !isCaptureActive,
              let deadline
        else { return false }
        return now >= deadline
    }
}

#Preview {
    SkyView(session: SkySession(), capture: CaptureStateMachine(), clock: SkyClock())
}
