import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 主渲染视图：TimelineView + Canvas，30fps。
/// 完整层序：星尘 → 拖影 → 轨迹弧 → 点位/刻度环/扫描 → vignette → 边缘信标 → 十字丝 → 档案层 → 颗粒 shader。
///
/// 两个观测维度：主天空负责指向与明确捕获，全局星图中的 TimeDial 负责选择观测时刻。
/// 非 LIVE 时全部对象按观测时刻推算；拨动时间时点位留下拖影 —— 时间方向的视觉痕迹。
struct SkyView: View {
    private enum ArchivePlacementSide {
        case leading
        case trailing
    }

    @ObservedObject var session: SkySession
    @ObservedObject var capture: CaptureStateMachine
    @ObservedObject var clock: SkyClock
    var onStoryPresentationChanged: (Bool) -> Void = { _ in }
    /// 设置入口与视野切换同属底部控制轨，因此由天空页统一排布，由上层负责呈现面板。
    var onOpenInstrument: () -> Void = {}

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
    @State private var persistentOverviewPresented = false
    @State private var persistentOverviewProgress: Double = 0
    @State private var overviewTransitioning = false
    @State private var filterExpanded = false
    /// 设置关闭时只做随准星出现/消失的即时识别；开启后才呈现底部确认控件。
    @AppStorage("captureConfirmationEnabled") private var captureConfirmationEnabled = false
    @State private var lastOverviewTrailSample: TimeInterval = -.infinity
    @State private var lastCaptureSample: TimeInterval = -.infinity
    @State private var measuredArchiveFrame: CGRect = .zero
    @State private var archivePlacementSide: ArchivePlacementSide = .leading
    @State private var lastRelationshipPoint: CGPoint?
    @State private var relationshipMotionEmphasis: Double = 1
    @State private var lastRelationshipSample: Date?
    @State private var lastAcquisitionPulse: Date?
    @State private var fieldMagnification: CGFloat = 1
    @State private var settledFieldMagnification: CGFloat = 1
    @State private var fieldMagnificationActive = false
    @State private var overviewScaleModified = false
    @State private var overviewResetRequest = 0
    @State private var presentedStoryObjectID: String?

    private static let maximumFieldMagnification: CGFloat = 4

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }
    private var fieldVerticalFOV: Double {
        Projection.verticalFOV(forMagnification: fieldMagnification)
    }
    private var scaleResetAvailable: Bool {
        if persistentOverviewPresented {
            return overviewScaleModified && !overviewTransitioning
        }
        return !clock.isScrubbing && fieldMagnification > 1.015
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSince(startDate)
                let obsTime = clock.observationTime(realNow: timeline.date)

                ZStack(alignment: .topLeading) {
                    canvasLayer(time: time, observation: obsTime)
                        .contentShape(Rectangle())
                        .scaleEffect(suppressMotion ? 1 : 1 - 0.07 * overviewPresentationProgress)
                        .blur(radius: suppressMotion ? 0 : 2.4 * overviewPresentationProgress)
                        .opacity(1 - 0.48 * overviewPresentationProgress)
                    archiveLayer(observation: obsTime, frameDate: timeline.date)
                        .opacity(1 - overviewPresentationProgress)
                    crosshairLayer(frameDate: timeline.date)
                        .opacity(1 - overviewPresentationProgress)
                    if clock.isLive {
                        guideLayer
                            .opacity(1 - overviewPresentationProgress)
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
                       !persistentOverviewPresented,
                       frameTime - lastCaptureSample >= 0.1 {
                        lastCaptureSample = frameTime
                        let sample = captureSample(at: obsTime, in: geo.size)
                        capture.update(
                            nearest: sample.nearest,
                            trackedDistance: sample.trackedDistance,
                            captureEnabled: captureConfirmationEnabled,
                            now: frameDate
                        )
                        updateRelationshipMotion(
                            at: frameDate,
                            observation: obsTime,
                            in: geo.size
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
        .overlay(alignment: .top) { pointingReadout }
        .overlay { filterLayer }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomControlBand
        }
        .coordinateSpace(name: "sky-interface")
        .overlay {
            satelliteStoryLayer
        }
        .onPreferenceChange(ArchiveBoundsPreferenceKey.self) { frame in
            // 面板离场后保留最后一次真实高度，回到视野时不会先按估算尺寸跳一帧。
            guard frame.width > 0, frame.height > 0 else { return }
            if abs(frame.minX - measuredArchiveFrame.minX) > 0.5
                || abs(frame.minY - measuredArchiveFrame.minY) > 0.5
                || abs(frame.width - measuredArchiveFrame.width) > 0.5
                || abs(frame.height - measuredArchiveFrame.height) > 0.5 {
                measuredArchiveFrame = frame
            }
        }
        .onAppear {
            if !captureConfirmationEnabled {
                if capture.isLocked {
                    requestRelease()
                } else {
                    capture.returnToExploring()
                }
            }
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--openFilter") {
                // 镜片只属于探索层。模拟器默认指向常常正好落在目标上，
                // 不先解锁的话这个开关看起来毫无效果。
                capture.returnToExploring()
                filterExpanded = true
            }
            if arguments.contains("--filterObservation") {
                session.setCatalogFilter(.featured)
            }
            if arguments.contains("--openOverview") {
                persistentOverviewPresented = true
                persistentOverviewProgress = 1
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
        .onChange(of: capture.phase) { oldPhase, newPhase in
            switch newPhase {
            case .acquiring(let objectId):
                if filterExpanded { setFilterExpanded(false) }
                lastAcquisitionPulse = Date()
                acquisitionEntryHaptic()
                let observation = clock.observationTime()
                if viewportSize != .zero,
                   let projected = relationshipTarget(
                    objectID: objectId,
                    observation: observation,
                    in: viewportSize
                   )?.projected?.point {
                    archivePlacementSide = projected.x < viewportSize.width / 2
                        ? .trailing
                        : .leading
                }
            case .locked(let objectId):
                if filterExpanded { setFilterExpanded(false) }
                lockedAt = Date()
                hasEverLocked = true
                lastAcquisitionPulse = nil
                lastRelationshipPoint = nil
                lastRelationshipSample = nil
                relationshipMotionEmphasis = 1
                lockHaptic()
                let observation = clock.observationTime()
                if viewportSize != .zero,
                   let projected = relationshipTarget(
                    objectID: objectId,
                    observation: observation,
                    in: viewportSize
                   )?.projected?.point {
                    archivePlacementSide = projected.x < viewportSize.width / 2
                        ? .trailing
                        : .leading
                }
                let ephemeris = session.ephemeris.ephemeris(
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
                lastRelationshipPoint = nil
                lastRelationshipSample = nil
                relationshipMotionEmphasis = 0
            case .releasing:
                lastAcquisitionPulse = nil
                releaseHintVisible = false
            }
        }
        .onChange(of: capture.acquisitionProgress) { _, progress in
            updateAcquisitionHaptic(progress: progress)
        }
        .onChange(of: capture.recognitionReady) { _, ready in
            guard ready else { return }
            hasEverLocked = true
            recognitionCompleteHaptic()
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
        .onChange(of: session.catalogFilter) { _, _ in
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
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.28)
        #endif
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
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.2 + 0.28 * p)
        #endif
    }

    /// 默认识别完成：捕获环闭合与完整档案出现共用一次明确的刚性确认。
    private func recognitionCompleteHaptic() {
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.86)
        #endif
    }

    /// 手动锁定与默认识别完成保持同一种触觉语义。
    private func lockHaptic() {
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.86)
        #endif
    }

    /// 所有主动退出入口汇入同一个动作：先给一次极轻的“松开”触觉，再启动统一回收序列。
    private func requestRelease() {
        guard capture.isLocked else { return }
        releaseHintVisible = false
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.32)
        #endif
        capture.releaseSignal()
    }

    // MARK: - 底部观测动作 / 全局时间标尺

    /// 主天空与全局星图共享同一个底部槽位，但职责不混合：主天空只表达捕获意图，
    /// 全局星图才提供时间旅行。这样主页面不会在无全局语境时意外停留于过去/未来。
    private var bottomControlBand: some View {
        Group {
            if persistentOverviewPresented {
                overviewControlColumn
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                skyControlRow
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
            }
        }
        .animation(Motion.interfaceCollapse, value: persistentOverviewPresented)
        .zIndex(2)
    }

    /// 全局星图只提供时间旅行与返回：镜片属于指向观测，这里不出现。
    private var overviewControlColumn: some View {
        VStack(spacing: 10) {
            timeDial

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                overviewEntry
                instrumentEntry
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    /// 主天空的底部秩序：动作行与仪器轨叠放而不是上下堆叠，动作行因此能真正
    /// 贴住下缘 —— 这是“深入档案”过去悬在半空的原因：它被整条仪器轨顶高了。
    ///
    /// 单枚动作（深入档案、复位视场）与仪器轨并排，各自留出对方的宽度；
    /// 开启确认捕获后的动作行本身就接近满宽，此时改为让它升到轨道上方一行。
    private var skyControlRow: some View {
        ZStack(alignment: .bottom) {
            focusDock
                .padding(
                    .horizontal,
                    dockNeedsFullWidth ? 0 : CatalogFilterControl.collapsedSize + 20
                )
                .padding(.bottom, dockNeedsFullWidth ? utilityRailHeight + 10 : 0)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                utilityRail
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(Motion.interfaceCollapse, value: dockNeedsFullWidth)
    }

    /// 确认捕获的主动作加取消按钮并排后接近满宽，无法再与右侧仪器轨共处一行。
    private var dockNeedsFullWidth: Bool {
        captureConfirmationEnabled && !filterExpanded
    }

    private var utilityRailHeight: CGFloat {
        SkyTopBarMetrics.controlHeight + 8 + CatalogFilterControl.collapsedSize
    }

    /// 竖向仪器轨：视野切换与系统设置成对在上，常驻镜片端口坐在右下角末端。
    /// 镜片展开后的长面板由端口自身以覆盖层向上生长，不参与这里的布局，
    /// 因此展开时不会把动作行顶离拇指区。
    private var utilityRail: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                overviewEntry
                instrumentEntry
            }
            .animation(
                suppressMotion ? .easeOut(duration: 0.12) : Motion.interfaceCollapse,
                value: capture.phase
            )

            filterPort
        }
    }

    /// 轨道末端始终只占收起态的尺寸；镜片作为覆盖层锚在这个槽位的右下角，
    /// 展开后向左上生长。这样展开不会改变轨道高度，也不会挤动动作行。
    private var filterPort: some View {
        Color.clear
            .frame(
                width: CatalogFilterControl.collapsedSize,
                height: CatalogFilterControl.collapsedSize
            )
            .overlay(alignment: .bottomTrailing) {
                CatalogFilterControl(
                    selection: session.catalogFilter,
                    expanded: filterExpanded,
                    onToggle: { setFilterExpanded(!filterExpanded) },
                    onSelect: { filter in
                        session.setCatalogFilter(filter)
                        setFilterExpanded(false)
                    },
                    presence: filterChromeOpacity
                )
                .fixedSize()
                .animation(.easeOut(duration: 0.24), value: filterChromeOpacity)
            }
    }

    /// 系统设置入口。与视野切换共用同一枚圆形端口造型，形成成对的工具轨。
    private var instrumentEntry: some View {
        Button(action: onOpenInstrument) {
            ZStack {
                Circle()
                    .fill(Palette.voidBlack.opacity(0.9))
                Circle()
                    .stroke(Palette.inkFaint.opacity(0.72), lineWidth: 0.65)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
            }
            .frame(width: 30, height: 30)
            .frame(
                width: SkyTopBarMetrics.controlHeight,
                height: SkyTopBarMetrics.controlHeight
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(observationChromeOpacity)
        .accessibilityLabel("打开仪器状态与设置")
        .accessibilityHint("进入设置、观测记录与帮助")
    }

    @ViewBuilder
    private var focusDock: some View {
        VStack(spacing: 8) {
            if !filterExpanded {
                if captureConfirmationEnabled || scaleResetAvailable {
                    HStack(spacing: 8) {
                        if captureConfirmationEnabled {
                            FocusActionControl(
                                mode: focusActionMode,
                                action: performFocusAction
                            )
                            if capture.isLocked || isReleasing {
                                CaptureSecondaryControl(
                                    mode: captureSecondaryMode,
                                    action: performSecondaryCaptureAction
                                )
                            }
                        }
                        if scaleResetAvailable {
                            FieldOfViewResetControl(action: resetActiveFieldOfView)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if let object = deepArchiveActionObject {
                    SatelliteStoryEntryControl(tint: object.identityTint) {
                        presentDeepArchive(for: object)
                    }
                    .id(object.id)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.92, anchor: .bottom)
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.interfaceExpand, value: focusActionMode)
        .animation(Motion.interfaceExpand, value: captureConfirmationEnabled)
        .animation(Motion.interfaceCollapse, value: filterExpanded)
        .animation(Motion.interfaceCollapse, value: scaleResetAvailable)
        .animation(Motion.interfaceExpand, value: deepArchiveActionObject?.id)
    }

    /// 深入档案只在完整即时信息已经建立时出现。它与空间面板共享目标状态，
    /// 但不共享面板坐标，因此设备移动时不会跟着正文漂移。
    private var deepArchiveActionObject: CatalogObject? {
        guard archivePresentationReady,
              !isReleasing,
              let id = capture.engagedObjectId,
              let object = session.catalog.objectsByID[id],
              object.deepArchiveStory != nil,
              viewportSize != .zero,
              let target = relationshipTarget(
                  objectID: id,
                  observation: clock.observationTime(),
                  in: viewportSize
              ),
              let frame = spatialArchiveFrame(for: target, in: viewportSize),
              spatialArchiveVisibility(
                  target: target,
                  frame: frame,
                  in: viewportSize
              ) > 0.42 else { return nil }
        return object
    }

    private func presentDeepArchive(for object: CatalogObject) {
        guard object.deepArchiveStory != nil else { return }
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred(intensity: 0.5)
        #endif
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
        if capture.isLocked {
            requestRelease()
        }
    }

    private var timeDial: some View {
        TimeDial(clock: clock)
            .overlay(alignment: .top) {
                if !filterExpanded, !clock.isLive || scaleResetAvailable {
                    HStack(spacing: 8) {
                        if !clock.isLive {
                            ReturnToLiveControl(
                                returning: clock.isReturningToLive,
                                action: returnToLiveFromCapsule
                            )
                        }
                        if scaleResetAvailable {
                            FieldOfViewResetControl(action: resetActiveFieldOfView)
                        }
                    }
                    .offset(y: -52)
                    .transition(
                        .scale(scale: 0.9, anchor: .bottom)
                            .combined(with: .opacity)
                    )
                }
            }
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
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: 0.82)
        #endif
        clock.returnToLive()
    }

    private func resetActiveFieldOfView() {
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.68)
        #endif

        if persistentOverviewPresented {
            overviewResetRequest &+= 1
        } else {
            fieldMagnificationActive = false
            settledFieldMagnification = 1
            withAnimation(Motion.fieldReset) {
                fieldMagnification = 1
            }
        }
    }

    /// 镜片展开后天空只承担一件事：点画面任意处收起。镜片本体常驻在仪器轨末端，
    /// 因此这一层不再持有控件，只提供收拢用的透明捕获面。
    @ViewBuilder
    private var filterLayer: some View {
        if filterExpanded {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { setFilterExpanded(false) }
                .accessibilityHidden(true)
        }
    }

    /// 捕获中镜片仍然可用，但退到背景层：它不与目标身份争夺第一视觉权重。
    private var filterChromeOpacity: Double {
        if capture.isLocked || isReleasing { return 0.4 }
        if capture.isAcquiring { return 0.58 }
        return session.catalogFilter == .all ? 0.88 : 1
    }

    private func setFilterExpanded(_ expanded: Bool) {
        let animation: Animation = suppressMotion
            ? .easeOut(duration: 0.14)
            : (expanded ? Motion.interfaceExpand : Motion.interfaceCollapse)
        withAnimation(animation) { filterExpanded = expanded }
    }

    /// 左上角与右上角设置端口形成一对：一个切换空间尺度，一个进入系统设置。
    private var overviewEntry: some View {
        Button(action: togglePersistentOverview) {
            ZStack {
                Circle()
                    .fill(Palette.voidBlack.opacity(0.9))
                Circle()
                    .stroke(Palette.inkFaint.opacity(0.72), lineWidth: 0.65)

                if persistentOverviewPresented {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.signal.opacity(0.9))
                } else {
                    Capsule()
                        .stroke(Palette.inkMid.opacity(0.7), lineWidth: 0.6)
                        .frame(width: 17, height: 8)
                        .rotationEffect(.degrees(-24))
                    Circle()
                        .fill(Palette.signal.opacity(0.92))
                        .frame(width: 3, height: 3)
                        .offset(x: 6, y: -4)
                    Circle()
                        .fill(Palette.inkMid.opacity(0.82))
                        .frame(width: 2.5, height: 2.5)
                }
            }
            .frame(width: 30, height: 30)
            .frame(
                width: SkyTopBarMetrics.controlHeight,
                height: SkyTopBarMetrics.controlHeight
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(observationChromeOpacity)
        .opacity(clock.isScrubbing && !persistentOverviewPresented ? 0 : 1)
        .allowsHitTesting(!clock.isScrubbing || persistentOverviewPresented)
        .disabled(overviewTransitioning)
        .accessibilityLabel(persistentOverviewPresented ? "返回捕获视野" : "打开全局星图")
        .accessibilityHint(
            persistentOverviewPresented
                ? "关闭全局星图并恢复准星观测"
                : "查看你周围的人造天体与实时轨迹"
        )
    }

    /// 两侧入口常驻，但在感应与锁定时主动降到背景层。入口仍可用，不与目标信息
    /// 争夺第一视觉权重。
    private var observationChromeOpacity: Double {
        if persistentOverviewPresented { return 1 }
        if capture.isLocked || isReleasing { return 0.28 }
        if capture.isAcquiring { return 0.46 }
        return 1
    }

    private func togglePersistentOverview() {
        guard !overviewTransitioning else { return }
        let duration = suppressMotion ? 0.16 : Motion.skyOverviewModeDuration
        let animation: Animation = suppressMotion
            ? .easeOut(duration: duration)
            : Motion.skyOverviewMode

        if persistentOverviewPresented {
            overviewTransitioning = true
            // 时间轴只存在于全局星图。离开这一空间前先启动回归，主天空不会保留一个
            // 缺少时间控制入口的历史/未来状态。
            if !clock.isLive {
                returnToLiveFromCapsule()
            }
            withAnimation(animation) {
                persistentOverviewProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard persistentOverviewProgress < 0.001 else { return }
                persistentOverviewPresented = false
                overviewTransitioning = false
            }
        } else {
            persistentOverviewPresented = true
            persistentOverviewProgress = 0
            overviewTransitioning = true
            // 先把零进度星图插入层级，下一帧再让同一组属性连续显影。
            DispatchQueue.main.async {
                withAnimation(animation) {
                    persistentOverviewProgress = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    overviewTransitioning = false
                }
            }
        }
    }

    // MARK: - 指向读数

    /// 顶部中央的方位/仰角读数始终只是弱方向参考；感应和锁定时继续后退，
    /// 不与目标身份和档案正文竞争。
    private var pointingReadout: some View {
        SkyStatusIndicator(
            mode: statusMode,
            coordinates: statusCoordinates,
            presence: statusPresence
        )
        .frame(height: SkyTopBarMetrics.controlHeight, alignment: .center)
        .safeAreaPadding(.top, SkyTopBarMetrics.safeAreaSpacing)
        .allowsHitTesting(false)
    }

    /// 状态判定顺序即优先级：降级 → 全局星图 → 捕获 → 感应 → 常规观测。
    /// 这样"点位方向是否可信"永远是用户最先读到的信息。
    private var statusMode: SkyStatusIndicator.Mode {
        if let reason = pointingStatusLabel {
            return .degraded(reason: reason)
        }
        if persistentOverviewPresented {
            return .field(timeLabel: clock.isLive ? "全局星图 · 此刻" : "全局星图 · \(clock.offsetLabel)")
        }
        if capture.isLocked || isReleasing,
           let id = capture.engagedObjectId,
           let object = session.catalog.objectsByID[id] {
            return .locked(name: object.name)
        }
        if capture.isAcquiring { return .acquiring }
        return .observing
    }

    /// 坐标只在主天空出现；全局星图里方位角没有对应含义。
    private var statusCoordinates: String? {
        guard !persistentOverviewPresented else { return nil }
        let az = session.pointing.azimuth * 180 / .pi
        let el = session.pointing.elevation * 180 / .pi
        let azNorm = az < 0 ? az + 360 : az
        let magnification = fieldMagnification > 1.01
            ? String(format: " · %.1f×", Double(fieldMagnification))
            : ""
        return String(format: "AZ %03.0f° EL %+03.0f°%@", azNorm, el, magnification)
    }

    /// 锁定后指示器后退，把第一视觉权重让给目标档案；但绝不完全消失。
    private var statusPresence: Double {
        if persistentOverviewPresented { return 1 }
        if capture.isLocked || isReleasing { return 0.42 }
        if capture.isAcquiring { return 0.62 }
        return 0.92
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
            return "手动指向"
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
                  eph.elevation > 0,
                  let proj = projection.project(
                      azimuth: eph.azimuth, elevation: eph.elevation
                  ) else { return }
            let captureAngle = Projection.captureAngle(
                for: proj.angularDistance,
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

    private func relationshipMarker(
        objectID: String,
        observation: Date,
        in size: CGSize
    ) -> TargetRelationshipGeometry.Marker? {
        relationshipTarget(
            objectID: objectID,
            observation: observation,
            in: size
        )?.marker
    }

    /// 档案与卫星共享同一个屏幕位移。这里刻意不钳制位置：设备转动时档案会像
    /// 空间注释一样自然离开屏幕，而不是重新吸附到固定 UI 坐标。
    private func spatialArchiveFrame(
        for target: RelationshipTarget,
        in size: CGSize
    ) -> CGRect? {
        guard let projected = target.projected?.point else { return nil }
        // 铭牌是定宽器件：遥测栅格需要两列可读的中文标签，宽度必须由面板自身的
        // 排版决定，而不是屏幕比例。窄屏时才等比收窄。
        let width = min(ArchiveOverlay.plateWidth, size.width - 32)
        let rememberedHeight = measuredArchiveFrame.height
        let height = rememberedHeight > 100 && rememberedHeight < size.height * 0.62
            ? rememberedHeight
            : min(280, size.height * 0.42)
        let gap: CGFloat = 14
        let minX: CGFloat = 12
        let maxX = max(minX, size.width - width - 12)
        // 先按目标所在的一侧摆放；那一侧放不下时改用另一侧，避免定宽铭牌被钳回
        // 目标身上。窄屏两侧都放不下时才接受钳制，由下面的准星让位继续处理。
        let preferred: CGFloat = archivePlacementSide == .leading
            ? projected.x - width - gap
            : projected.x + gap
        let alternate: CGFloat = archivePlacementSide == .leading
            ? projected.x + gap
            : projected.x - width - gap
        let x: CGFloat
        if preferred >= minX, preferred <= maxX {
            x = preferred
        } else if alternate >= minX, alternate <= maxX {
            x = alternate
        } else {
            x = min(max(preferred, minX), maxX)
        }
        let y = projected.y - height * 0.52
        return archiveFrameAvoidingCrosshair(
            CGRect(x: x, y: y, width: width, height: height),
            in: size
        )
    }

    /// 准星是这台仪器的取景中心，任何情况下都不该被读物盖住。铭牌与准星重叠时
    /// 整体沿纵向让开 —— 联系线继续指回目标，因此空间关系不会因为这一次让位而断开。
    private func archiveFrameAvoidingCrosshair(
        _ frame: CGRect,
        in size: CGSize
    ) -> CGRect {
        // 准星的四条刻线延伸到中心 15pt；再留 9pt 呼吸，让铭牌边框不与刻线相切。
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let keepOutRadius: CGFloat = 24
        let keepOut = CGRect(
            x: center.x - keepOutRadius,
            y: center.y - keepOutRadius,
            width: keepOutRadius * 2,
            height: keepOutRadius * 2
        )
        guard frame.intersects(keepOut) else { return frame }

        // 上缘让给顶部指向读数：那一行是"这些点是否可信"的答案，不能被铭牌压住。
        let topLimit = SkyTopBarMetrics.safeAreaSpacing
            + SkyTopBarMetrics.controlHeight
            + 76
        // 下缘让给整条底部控制带：仪器轨两行加动作行，铭牌不覆盖任何可点区域。
        let bottomLimit = size.height - utilityRailHeight - 62
        let above = keepOut.minY - 10 - frame.height
        let below = keepOut.maxY + 10
        let fitsAbove = above >= topLimit
        let fitsBelow = below + frame.height <= bottomLimit

        let y: CGFloat
        if fitsAbove, fitsBelow {
            // 两侧都放得下时走位移更小的一侧，铭牌不会为了让位跨过整块画面。
            y = abs(above - frame.minY) <= abs(below - frame.minY) ? above : below
        } else if fitsAbove {
            y = above
        } else if fitsBelow {
            y = below
        } else {
            // 窄屏上定宽铭牌比中心两侧的剩余空间都高，完全避开无解。这时贴住下缘：
            // 准星因此落在铭牌顶部的留白与状态标签上，而不是名称、叙述或读数上。
            // 准星本身画在档案之上，所以取景中心始终可见。
            y = max(topLimit, bottomLimit - frame.height)
        }
        return CGRect(x: frame.minX, y: y, width: frame.width, height: frame.height)
    }

    /// 面板接近屏幕边缘时随自身裁切比例和目标边缘进度共同淡出；返回同一方向后
    /// 使用完全相同的函数反向出现，不需要额外的“重新打开”状态。
    private func spatialArchiveVisibility(
        target: RelationshipTarget,
        frame: CGRect,
        in size: CGSize
    ) -> Double {
        let viewport = CGRect(
            x: 4,
            y: 70,
            width: max(1, size.width - 8),
            height: max(1, size.height - 70 - 112)
        )
        let intersection = frame.intersection(viewport)
        guard !intersection.isNull, frame.width > 0, frame.height > 0 else { return 0 }
        let visibleFraction = Double(
            (intersection.width * intersection.height) / (frame.width * frame.height)
        )
        let panelPresence = unitSmoothstep((visibleFraction - 0.08) / 0.55)
        let targetPresence = 1 - unitSmoothstep((target.marker.edgeProgress - 0.08) / 0.78)
        return panelPresence * targetPresence
    }

    /// 连线静止时回落为低存在感；目标位置在相邻采样间明显变化时快速增强，
    /// 让用户重新建立空间关系，然后以较慢时间常数淡回阅读层。
    private func updateRelationshipMotion(
        at date: Date,
        observation: Date,
        in size: CGSize
    ) {
        guard let objectID = capture.engagedObjectId,
              capture.isLocked || isReleasing,
              let marker = relationshipMarker(
                objectID: objectID,
                observation: observation,
                in: size
              ) else {
            lastRelationshipPoint = nil
            lastRelationshipSample = nil
            relationshipMotionEmphasis = 0
            return
        }

        let dt = min(0.25, max(1.0 / 60.0, lastRelationshipSample.map {
            date.timeIntervalSince($0)
        } ?? 0.1))
        let distance = lastRelationshipPoint.map {
            hypot(marker.point.x - $0.x, marker.point.y - $0.y)
        } ?? 18
        let target = min(1, Double(distance / 16))
        let timeConstant = target > relationshipMotionEmphasis ? 0.1 : 0.82
        let alpha = 1 - exp(-dt / timeConstant)
        relationshipMotionEmphasis += (target - relationshipMotionEmphasis) * alpha
        lastRelationshipPoint = marker.point
        lastRelationshipSample = date
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
                interactive: persistentOverviewPresented
                    && persistentOverviewProgress > 0.98
                    && !overviewTransitioning
            )
            .opacity(overviewPresentationProgress)
            .scaleEffect(suppressMotion ? 1 : 0.84 + 0.16 * overviewPresentationProgress)
            .rotationEffect(
                suppressMotion
                    ? .zero
                    : .degrees(-1.6 * (1 - overviewPresentationProgress))
            )
            .blur(radius: suppressMotion ? 0 : 4 * (1 - overviewPresentationProgress))
            .transition(
                suppressMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .identity,
                        removal: .opacity
                    )
            )
            .allowsHitTesting(
                persistentOverviewPresented
                    && persistentOverviewProgress > 0.98
                    && !overviewTransitioning
            )
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
            let parallax = CGPoint(
                x: CGFloat(-pointing.azimuth) * 40,
                y: CGFloat(pointing.elevation) * 40
            )
            SkyRenderer.drawDust(context, dust: dust, time: motionTime, size: size, parallax: parallax)

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
            var screenPositions: [String: CGPoint] = [:]
            var edgeCandidates: [Projection.ScreenDirection] = []
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
            let spatialFrame = relationship.flatMap { spatialArchiveFrame(for: $0, in: size) }
            let archivePresence: Double
            if let relationship, let spatialFrame {
                archivePresence = spatialArchiveVisibility(
                    target: relationship,
                    frame: spatialFrame,
                    in: size
                )
            } else {
                archivePresence = 0
            }
            let archiveBounds = archivePresence > 0.01 ? spatialFrame ?? .null : .null
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
                    screenPositions[object.id] = proj.point
                    if cueBounds.contains(proj.point) { return }
                }

                if let direction = projection.screenDirection(
                    azimuth: eph.azimuth, elevation: eph.elevation
                ), direction.angularDistance < 165 * .pi / 180 {
                    edgeCandidates.append(direction)
                }
            }
            for object in session.displayObjects {
                projectObject(object)
            }

            // 时间拖影：offset 变化时记录，停止后消散
            if !clock.isScrubbing {
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

            // 轨迹弧（锁定/释放中的对象；观测时刻为中心 ±3min）
            if let id = engagedId, capture.isLocked || isReleasing {
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
                    context, pastPoints: past, futurePoints: future, alpha: strength
                )
            }

            // 星野按星等分档批量绘制：亮度差建立深度，类别色只留在最亮档的外晕。
            // 图层数由档位数决定，与目标数量无关。
            var categoryTiers: [CatalogCategory: [SkyRenderer.StarMagnitude: [CGPoint]]] = [:]
            var familyTiers: [CatalogFamily: [SkyRenderer.StarMagnitude: [CGPoint]]] = [:]
            categoryTiers.reserveCapacity(CatalogCategory.allCases.count)
            familyTiers.reserveCapacity(CatalogFamily.allCases.count)
            for (object, proj, magnitude) in projected
            where object.id != engagedId
                && object.id != replacementId
                && !object.isCurated
                && !object.isFeatured {
                if let family = object.family {
                    familyTiers[family, default: [:]][magnitude, default: []].append(proj.point)
                } else {
                    categoryTiers[object.category, default: [:]][magnitude, default: []]
                        .append(proj.point)
                }
            }
            for category in CatalogCategory.allCases {
                guard let tiers = categoryTiers[category] else { continue }
                SkyRenderer.drawStarField(
                    context,
                    tiers: tiers,
                    tint: category.tint
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
                    opacity: emphasized ? 0.92 : 0.62,
                    emphasis: emphasized ? 1.08 : 0.86
                )
            }

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
                let targetBehindArchive = isEngaged
                    && (capture.isLocked || isReleasing)
                    && archiveBounds.contains(proj.point)
                if !targetBehindArchive {
                    SkyRenderer.drawTarget(
                        context,
                        at: proj.point,
                        brightness: brightness,
                        tint: tint,
                        time: motionTime,
                        breathPhase: Double(object.id.hashValue % 628) / 100.0
                    )
                }

                if (isEngaged && capture.isAcquiring) || isReplacement {
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
                        tint: tint
                    )
                    let scanStart = isReplacement
                        ? capture.replacementTriggeredAt
                        : capture.scanTriggeredAt
                    if let scanStart,
                       !clock.isScrubbing, !suppressMotion {
                        let scanProgress = frameDate.timeIntervalSince(scanStart) / Motion.scanDuration
                        SkyRenderer.drawScanBand(
                            context, around: proj.point, width: 160, progress: scanProgress
                        )
                    }

                }
            }

            // 稳定阅读关系：不依赖目标是否仍在正常投影视野。画面内标记、边缘裁切
            // 信标和档案联系线全部由同一个 marker 连续派生，因此出入边缘不会换轨。
            if let id = engagedId,
               capture.isLocked || isReleasing,
               let object = session.catalog.objectsByID[id],
               let relationship,
               let lockTime = lockedAt {
                let marker = relationship.marker
                let rawGrowth = min(1, max(
                    0,
                    (frameDate.timeIntervalSince(lockTime) - 0.08)
                        / Motion.signalLineGrowDuration
                ))
                let grownLine = 1 - pow(1 - rawGrowth, 3)
                // 归还开始时先让正文消隐，再把联系线从档案边界收回目标。
                let lineRetraction = unitSmoothstep((releaseProgress - 0.14) / 0.68)
                let lineProgress = grownLine * (1 - lineRetraction)
                let releaseVisibility = 1 - unitSmoothstep((releaseProgress - 0.46) / 0.54)
                let readingAlpha = 0.46 + 0.54 * relationshipMotionEmphasis
                let connection = archivePresence > 0.01
                    ? TargetRelationshipGeometry.connection(
                        from: marker.point,
                        to: archiveBounds
                    )
                    : nil
                if let connection {
                    SkyRenderer.drawSignalLine(
                        context,
                        from: connection.start,
                        to: connection.archiveAnchor,
                        progress: lineProgress,
                        alpha: (capture.isLocked ? max(0.72, strength) : releaseVisibility)
                            * readingAlpha * archivePresence
                    )
                }

                if connection?.targetOccludedByArchive != true {
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
                        alpha: capture.isLocked ? max(0.72, strength) : releaseVisibility
                    )
                }
            }

            SkyRenderer.drawVignette(context, size: size)

            // 任意观测时刻的探索态都给出方向提示；进入捕捉后让信标退场。
            if !clock.isScrubbing, engagedId == nil {
                let cues = Self.selectedEdgeCues(from: edgeCandidates, limit: 3)
                for (rank, cue) in cues.enumerated() {
                    SkyRenderer.drawEdgeCue(
                        context,
                        direction: cue.vector,
                        inside: cueBounds,
                        rank: rank,
                        time: motionTime
                    )
                }
            }
        }
    }

    /// 准星是这台仪器的取景中心，它单独成层画在档案之上。
    ///
    /// 定宽铭牌加上纵向让位仍无法在窄屏上完全避开画面中心 —— 面板本身就有
    /// 屏高三分之一。所以最后一道保证放在层序上：无论档案落在哪里，对焦框都不会
    /// 被盖住。锁定后它已经降到半强度，穿过正文的两根细线不会干扰阅读。
    @ViewBuilder
    private func crosshairLayer(frameDate: Date) -> some View {
        Canvas { context, size in
            let lockProgress = lockPresentationProgress(at: frameDate)
            let releaseProgress = releasePresentationProgress(at: frameDate)
            SkyRenderer.drawCrosshair(
                context,
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                emphasis: capture.isAcquiring
                    ? capture.strength
                    : capture.replacementProgress,
                presence: 1 - 0.48 * (
                    capture.isLocked
                        ? lockProgress
                        : (isReleasing ? 1 - releaseProgress : 0)
                )
            )
        }
        .allowsHitTesting(false)
    }

    /// 按角距选最近目标，并合并屏幕方向相差不足 16° 的拥挤信标。
    private nonisolated static func selectedEdgeCues(
        from candidates: [Projection.ScreenDirection],
        limit: Int
    ) -> [Projection.ScreenDirection] {
        var selected: [Projection.ScreenDirection] = []
        let minimumSeparation: CGFloat = cos(16 * .pi / 180)

        for candidate in candidates {
            if let overlapIndex = selected.firstIndex(where: { existing in
                candidate.vector.dx * existing.vector.dx
                    + candidate.vector.dy * existing.vector.dy > minimumSeparation
            }) {
                if candidate.angularDistance < selected[overlapIndex].angularDistance {
                    selected[overlapIndex] = candidate
                }
                continue
            }
            selected.append(candidate)
            selected.sort { $0.angularDistance < $1.angularDistance }
            if selected.count > limit { selected.removeLast() }
        }
        return selected
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
                ephemeris: session.ephemeris.ephemeris(
                    id,
                    at: clock.observationTime(),
                    live: clock.isLive
                ),
                onDismiss: {
                    withAnimation(
                        suppressMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22)
                    ) {
                        presentedStoryObjectID = nil
                        onStoryPresentationChanged(false)
                    }
                }
            )
            .transition(.opacity)
            .zIndex(20)
        }
    }

    @ViewBuilder
    private func archiveLayer(observation: Date, frameDate: Date) -> some View {
        GeometryReader { geo in
            if archivePresentationReady,
               let id = capture.engagedObjectId,
               let object = session.catalog.objectsByID[id],
               let target = relationshipTarget(
                    objectID: id,
                    observation: observation,
                    in: geo.size
               ),
               let frame = spatialArchiveFrame(for: target, in: geo.size) {
                let presence = spatialArchiveVisibility(target: target, frame: frame, in: geo.size)
                if presence > 0.001 {
                    ArchiveOverlay(
                        object: object,
                        ephemeris: session.ephemeris.ephemeris(
                            id,
                            at: observation,
                            live: clock.isLive
                        ),
                        revealed: archivePresentationReady,
                        captured: capture.isLocked || isReleasing,
                        lockProgress: 1,
                        releaseProgress: releasePresentationProgress(at: frameDate),
                        nextPass: clock.isLive
                            ? session.passes.nextPass(
                                for: id,
                                observer: session.observer.coordinates,
                                after: observation
                            )
                            : .none,
                        observationTimeLabel: clock.isLive ? nil : clock.offsetLabel
                    )
                    .allowsHitTesting(false)
                    .id(id)
                    .transition(.opacity)
                    .frame(width: frame.width, alignment: .leading)
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(presence)
                    .accessibilityHidden(presence < 0.35)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ArchiveBoundsPreferenceKey.self,
                                value: proxy.frame(in: .named("sky-interface"))
                            )
                        }
                    }
                }
            }
        }
        // 空间正文不截获天空手势；“深入档案”已独立放在底部操作区。
        .animation(
            suppressMotion ? .easeOut(duration: 0.1) : .easeOut(duration: 0.18),
            value: capture.phase
        )
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard !persistentOverviewPresented else { return }
                guard !fieldMagnificationActive else { return }
                guard let manual = session.manualProvider else { return }
                let scale = max(1, fieldMagnification)
                let delta = CGSize(
                    width: (value.translation.width - lastTranslation.width) / scale,
                    height: (value.translation.height - lastTranslation.height) / scale
                )
                lastTranslation = value.translation
                manual.drag(translation: delta)
            }
            .onEnded { value in
                guard !persistentOverviewPresented else {
                    lastTranslation = .zero
                    return
                }
                lastTranslation = .zero
                guard !fieldMagnificationActive else { return }
                let scale = max(1, fieldMagnification)
                session.manualProvider?.endDrag(velocity: CGSize(
                    width: value.velocity.width / scale,
                    height: value.velocity.height / scale
                ))
            }
    }

    /// 主天空的相机式长焦：围绕固定准星收窄视场，手机姿态仍决定镜头朝向。
    /// 全局星图出现时由其自身的三维手势接管，避免父子层同时缩放。
    private var fieldMagnificationGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard !persistentOverviewPresented, !clock.isScrubbing else { return }
                fieldMagnificationActive = true
                fieldMagnification = min(
                    Self.maximumFieldMagnification,
                    max(1, settledFieldMagnification * value)
                )
            }
            .onEnded { _ in
                guard fieldMagnificationActive else { return }
                fieldMagnificationActive = false
                let target: CGFloat = fieldMagnification < 1.08 ? 1 : fieldMagnification
                settledFieldMagnification = target
                withAnimation(.easeOut(duration: 0.2)) {
                    fieldMagnification = target
                }
            }
    }
}

private struct ArchiveBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}

#Preview {
    SkyView(session: SkySession(), capture: CaptureStateMachine(), clock: SkyClock())
}
