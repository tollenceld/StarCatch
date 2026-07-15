import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 主渲染视图：TimelineView + Canvas，30fps。
/// 完整层序：星尘 → 拖影 → 轨迹弧 → 点位/刻度环/扫描 → vignette → 边缘信标 → 十字丝 → 档案层 → 颗粒 shader。
///
/// 两个观测维度：指向（拖拽/传感器）决定看哪里，观测时钟（TimeDial）决定看何时。
/// 非 LIVE 时全部对象按观测时刻推算；拨动时间时点位留下拖影 —— 时间方向的视觉痕迹。
struct SkyView: View {
    private enum ArchivePlacementSide {
        case leading
        case trailing
    }

    @ObservedObject var session: SkySession
    @ObservedObject var capture: CaptureStateMachine
    @ObservedObject var clock: SkyClock

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
    @State private var measuredTimeDialTop: CGFloat = 0
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
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in
                                handleSkyTap(
                                    at: value.location,
                                    observation: obsTime,
                                    in: geo.size
                                )
                            }
                        )
                        .scaleEffect(suppressMotion ? 1 : 1 - 0.07 * overviewPresentationProgress)
                        .blur(radius: suppressMotion ? 0 : 2.4 * overviewPresentationProgress)
                        .opacity(1 - 0.48 * overviewPresentationProgress)
                    archiveLayer(observation: obsTime, frameDate: timeline.date)
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
        .overlay { leadingControls }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            timeDial
        }
        .coordinateSpace(name: "sky-interface")
        .onPreferenceChange(TimeDialTopPreferenceKey.self) { top in
            if top > 0, abs(top - measuredTimeDialTop) > 0.5 {
                measuredTimeDialTop = top
            }
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
            session.start()
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--openFilter") {
                filterExpanded = true
            }
            if arguments.contains("--filterObservation") {
                session.setCatalogFilter(.observation)
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
            #endif
        }
        .onChange(of: capture.phase) { oldPhase, newPhase in
            switch newPhase {
            case .acquiring(let objectId):
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
    }

    /// 进入感应范围只给一次近乎阈下的确认。
    private func acquisitionEntryHaptic() {
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.18)
        #endif
    }

    /// 捕获环收缩时，脉冲间隔随进度缩短；亮度和触觉使用同一进度源。
    private func updateAcquisitionHaptic(progress: Double) {
        guard capture.isAcquiring || capture.isAcquiringReplacement else { return }
        let now = Date()
        let p = min(1, max(0, progress))
        let interval = 0.52 - 0.36 * pow(p, 0.78)
        if let lastAcquisitionPulse,
           now.timeIntervalSince(lastAcquisitionPulse) < interval { return }
        lastAcquisitionPulse = now
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.16 + 0.25 * p)
        #endif
    }

    /// 锁定瞬间是清晰但克制的仪器确认，不使用成功提示或强震动。
    private func lockHaptic() {
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.56)
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

    // MARK: - 时间标尺

    private var timeDial: some View {
        TimeDial(clock: clock)
            .overlay(alignment: .top) {
                if !filterExpanded {
                    Group {
                        if capture.isLocked || isReleasing {
                            ArchiveDismissControl(
                                releasing: isReleasing,
                                action: requestRelease
                            )
                        } else if !clock.isLive || scaleResetAvailable {
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
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TimeDialTopPreferenceKey.self,
                        value: proxy.frame(in: .named("sky-interface")).minY
                    )
                }
            }
            .animation(.easeOut(duration: 0.24), value: clock.isLive)
            .animation(
                scaleResetAvailable ? Motion.interfaceExpand : Motion.interfaceCollapse,
                value: scaleResetAvailable
            )
            .animation(Motion.interfaceExpand, value: capture.isLocked)
            .animation(Motion.interfaceCollapse, value: isReleasing)
            .zIndex(2)
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

    /// 全局星图入口留在左上；目录镜片靠近时间轴停在左下，形成“空间 / 时间”
    /// 两个不同尺度的控制区。展开时外部触摸只负责收拢。
    private var leadingControls: some View {
        GeometryReader { proxy in
            let dialTop = measuredTimeDialTop > 0
                ? measuredTimeDialTop
                : proxy.size.height - 108
            let filterTimelineClearance: CGFloat = 14

            ZStack(alignment: .topLeading) {
                if filterExpanded {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { setFilterExpanded(false) }
                        .accessibilityHidden(true)
                }

                overviewEntry
                    .safeAreaPadding(.top, SkyTopBarMetrics.safeAreaSpacing)
                    .safeAreaPadding(.leading, 8)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )

                // 筛选属于探索态，档案属于阅读态；两者不再争夺左下同一片空间。
                if !capture.isLocked && !isReleasing {
                    CatalogFilterControl(
                        selection: session.catalogFilter,
                        categoryCounts: session.catalog.categoryCounts,
                        totalCount: session.catalog.objects.count,
                        expanded: filterExpanded,
                        onToggle: { setFilterExpanded(!filterExpanded) },
                        onSelect: { filter in
                            session.setCatalogFilter(filter)
                            setFilterExpanded(false)
                        }
                    )
                    // 与时间轴保留一段清晰的呼吸区，避免两个独立交互面粘连成一体。
                    .offset(
                        x: 8,
                        y: max(
                            0,
                            dialTop
                                - CatalogFilterControl.surfaceHeight(expanded: filterExpanded)
                                - filterTimelineClearance
                        )
                    )
                    .transition(
                        .opacity.combined(with: .offset(y: 8))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                suppressMotion ? .easeOut(duration: 0.14) : Motion.interfaceCollapse,
                value: capture.isLocked || isReleasing
            )
        }
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

    private func togglePersistentOverview() {
        guard !overviewTransitioning else { return }
        let duration = suppressMotion ? 0.16 : Motion.skyOverviewModeDuration
        let animation: Animation = suppressMotion
            ? .easeOut(duration: duration)
            : Motion.skyOverviewMode

        if persistentOverviewPresented {
            overviewTransitioning = true
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

    /// 顶部中央的方位/仰角读数：探索时低调可读，捕捉时随 strength 增强。
    private var pointingReadout: some View {
        let az = session.pointing.azimuth * 180 / .pi
        let el = session.pointing.elevation * 180 / .pi
        let azNorm = az < 0 ? az + 360 : az
        let magnification = fieldMagnification > 1.01
            ? String(format: "  ·  %.1f×", Double(fieldMagnification))
            : ""
        let pointing = String(
            format: "AZ %05.1f°  ·  EL %+05.1f°%@",
            azNorm,
            el,
            magnification
        )
        let pointingAlpha = (0.64 + 0.24 * capture.strength) * (1 - overviewPresentationProgress)
        let overviewAlpha = 0.86 * overviewPresentationProgress
        let overviewTime = clock.isLive ? "LIVE" : clock.offsetLabel

        return ZStack {
            Text(pointing)
                .foregroundStyle(Palette.inkLow.opacity(pointingAlpha))
            Text("ORBIT FIELD  ·  \(overviewTime)")
                .foregroundStyle(Palette.inkLow.opacity(overviewAlpha))
        }
        .font(Typography.statusTag)
        .tracking(Typography.statusTagTracking)
        .frame(height: SkyTopBarMetrics.controlHeight, alignment: .center)
        .safeAreaPadding(.top, SkyTopBarMetrics.safeAreaSpacing)
        .allowsHitTesting(false)
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
        for object in session.displayObjects {
            guard let eph = session.ephemeris.cachedEphemeris(
                object.id,
                at: observation,
                live: clock.isLive
            ),
                  eph.elevation > -0.1,
                  let proj = projection.project(
                      azimuth: eph.azimuth, elevation: eph.elevation
                  ) else { continue }
            let captureAngle = Projection.captureAngle(
                for: proj.angularDistance,
                magnification: fieldMagnification
            )
            if nearest == nil || captureAngle < nearest!.angularDistance {
                nearest = (object.id, captureAngle)
            }
            if object.id == trackedID {
                trackedDistance = captureAngle
            }
        }
        return CaptureSample(nearest: nearest, trackedDistance: trackedDistance)
    }

    /// 感应态轻触直接确认；稳定阅读态只把明确点位轻触解释为切换目标。
    /// 空域轻触不再关闭档案，避免用户移动/缩放时误结束；显式退出统一在底部胶囊。
    private func handleSkyTap(at point: CGPoint, observation: Date, in size: CGSize) {
        guard !persistentOverviewPresented, !clock.isScrubbing, !filterExpanded else { return }
        if capture.confirmAcquisition() { return }
        guard let lockedID = capture.lockedObjectId else { return }

        if let selected = targetObject(
            near: point,
            excluding: lockedID,
            observation: observation,
            in: size
        ) {
            _ = capture.selectLockedTarget(selected)
        }
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

    /// 只把点位附近的轻触解释为切换目标，避免阅读时随手轻触误选远处卫星。
    private func targetObject(
        near point: CGPoint,
        excluding excludedID: String,
        observation: Date,
        in size: CGSize
    ) -> String? {
        let projection = Projection(
            pointing: session.pointing,
            screenSize: size,
            verticalFOV: fieldVerticalFOV
        )
        var best: (id: String, distance: CGFloat)?
        let selectionRadius: CGFloat = 28
        for object in session.displayObjects where object.id != excludedID {
            guard let eph = session.ephemeris.cachedEphemeris(
                object.id,
                at: observation,
                live: clock.isLive
            ), eph.elevation > -0.1,
                  let projected = projection.project(
                    azimuth: eph.azimuth,
                    elevation: eph.elevation
                  ) else { continue }
            let distance = hypot(projected.point.x - point.x, projected.point.y - point.y)
            guard distance <= selectionRadius else { continue }
            if best == nil || distance < best!.distance {
                best = (object.id, distance)
            }
        }
        return best?.id
    }

    private func relationshipBounds(in size: CGSize) -> CGRect {
        CGRect(
            x: 22,
            y: 72,
            width: max(1, size.width - 44),
            height: max(1, size.height - 72 - 112)
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
        let width = min(168, size.width * 0.41)
        let rememberedHeight = measuredArchiveFrame.height
        let height = rememberedHeight > 100 && rememberedHeight < size.height * 0.62
            ? rememberedHeight
            : min(280, size.height * 0.42)
        let gap: CGFloat = 14
        let x = archivePlacementSide == .leading
            ? projected.x - width - gap
            : projected.x + gap
        let y = projected.y - height * 0.52
        return CGRect(x: x, y: y, width: width, height: height)
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
        if clock.isScrubbing || persistentOverviewPresented {
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
            let revealStarlink = engagedObject?.isStarlink == true
            let renderObjects = revealStarlink ? session.visibleObjects : session.displayObjects

            // 投影所有对象（LIVE 用插值，非 LIVE 按观测时刻直算）
            var projected: [(object: CatalogObject, proj: Projection.Projected)] = []
            var screenPositions: [String: CGPoint] = [:]
            var edgeCandidates: [Projection.ScreenDirection] = []
            // 避开灵动岛/顶部读数与底部时间坐标仪。
            let cueBounds = relationshipBounds(in: size)
            let relationship: RelationshipTarget?
            if let engagedId, capture.isLocked || isReleasing {
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
            for object in renderObjects {
                guard let eph = session.ephemeris.cachedEphemeris(object.id, at: observation, live: live),
                      eph.elevation > -0.1 else { continue }

                if let proj = projection.project(azimuth: eph.azimuth, elevation: eph.elevation) {
                    projected.append((object, proj))
                    screenPositions[object.id] = proj.point
                    if cueBounds.contains(proj.point) { continue }
                }

                if let direction = projection.screenDirection(
                    azimuth: eph.azimuth, elevation: eph.elevation
                ), direction.angularDistance < 165 * .pi / 180 {
                    edgeCandidates.append(direction)
                }
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
                for (object, _) in projected {
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

            // 普通点位先批量绘制，避免为上万颗目标创建独立模糊层。
            var explorationField: [CGPoint] = []
            var observationField: [CGPoint] = []
            var networkField: [CGPoint] = []
            var legacyField: [CGPoint] = []
            var starlinkField: [CGPoint] = []
            explorationField.reserveCapacity(projected.count / 8)
            observationField.reserveCapacity(projected.count / 6)
            networkField.reserveCapacity(projected.count / 5)
            legacyField.reserveCapacity(64)
            starlinkField.reserveCapacity(projected.count / 2)
            for (object, proj) in projected
            where object.id != engagedId && object.id != replacementId && !object.isCurated {
                if object.isStarlink {
                    starlinkField.append(proj.point)
                } else {
                    switch object.category {
                    case .exploration: explorationField.append(proj.point)
                    case .observation: observationField.append(proj.point)
                    case .network: networkField.append(proj.point)
                    case .legacy: legacyField.append(proj.point)
                    }
                }
            }
            SkyRenderer.drawTargetField(
                context,
                points: explorationField,
                tint: Palette.explorationTint,
                opacity: 0.52,
                haloStrength: 0.065
            )
            SkyRenderer.drawTargetField(
                context,
                points: observationField,
                tint: Palette.observationTint,
                opacity: 0.5,
                haloStrength: 0.07
            )
            SkyRenderer.drawTargetField(
                context,
                points: networkField,
                tint: Palette.networkTint,
                opacity: 0.48,
                haloStrength: 0.06
            )
            SkyRenderer.drawTargetField(
                context,
                points: legacyField,
                tint: Palette.legacyTint,
                opacity: 0.44,
                haloStrength: 0.055
            )
            SkyRenderer.drawTargetField(
                context,
                points: starlinkField,
                tint: Palette.starlinkTint,
                opacity: revealStarlink ? 0.74 : 0.34,
                coreRadius: revealStarlink ? 0.96 : 0.62,
                haloStrength: revealStarlink ? 0.16 : 0.085
            )

            // 精选与当前捕捉对象保留呼吸、光晕和刻度细节。
            for (object, proj) in projected {
                let isEngaged = object.id == engagedId
                let isReplacement = object.id == replacementId
                guard isEngaged || isReplacement || (object.isCurated && !object.isStarlink)
                else { continue }
                let tint = object.identityTint
                let brightness: Double
                if isEngaged {
                    brightness = (0.3 + 0.7 * strength) * proj.visibility
                } else if isReplacement {
                    brightness = (0.38 + 0.5 * capture.replacementProgress) * proj.visibility
                } else {
                    brightness = 0.3 * proj.visibility
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
            SkyRenderer.drawCrosshair(
                context,
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                emphasis: capture.isAcquiring
                    ? strength
                    : capture.replacementProgress,
                presence: 1 - 0.48 * (
                    capture.isLocked
                        ? lockProgress
                        : (isReleasing ? 1 - releaseProgress : 0)
                )
            )
        }
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
    private func archiveLayer(observation: Date, frameDate: Date) -> some View {
        GeometryReader { geo in
            if let id = capture.engagedObjectId,
               let object = session.catalog.objectsByID[id],
               capture.isLocked || isReleasing,
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
                        revealed: capture.isLocked,
                        lockProgress: lockPresentationProgress(at: frameDate),
                        releaseProgress: releasePresentationProgress(at: frameDate),
                        nextPass: session.passes.nextPass(
                            for: id,
                            observer: session.observer.coordinates,
                            after: Date()
                        ),
                        observationTimeLabel: clock.isLive ? nil : clock.offsetLabel
                    )
                    .id(id)
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
        // 关闭动作已统一移到时间轴上方；空间档案自身不再截获天空手势。
        .allowsHitTesting(false)
    }

    private var isReleasing: Bool {
        if case .releasing = capture.phase { return true }
        return false
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
                Text("举起，指向天空。")
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
                Text("持续对准另一目标，可切换观测。")
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

private struct TimeDialTopPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
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
