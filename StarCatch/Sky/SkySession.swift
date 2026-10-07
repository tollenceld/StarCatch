import Combine
import CoreLocation
import CoreMotion
import Foundation
import SwiftUI

/// 会话装配：按环境选择指向源，持有观察者坐标与轨道推算引擎。
@MainActor
final class SkySession: ObservableObject {

    let manualProvider: ManualPointingProvider?
    let motionProvider: MotionPointingProvider?
    private var pointingNavigation: SkyPointingNavigation
    @Published private(set) var pointingMode: SkyPointingNavigation.Mode
    var canSampleCapture: Bool { pointingNavigation.canSampleCapture }
    let observer = ObserverLocation()
    let catalog: CatalogStore
    let ephemeris: EphemerisEngine
    let tracks: TrackSampler
    let passes: PassPredictor
    let insights: SatelliteInsightEngine
    let log = ObservationLog()

    @Published private(set) var pointing: Pointing = .initial
    @Published private(set) var confidence: HeadingConfidence = .manual
    @Published private(set) var pointingAvailability: PointingAvailability = .idle
    @Published private(set) var catalogScope: CatalogScope = .all
    @Published private(set) var catalogFilters: Set<CatalogFilter> = []
    @Published private(set) var visibleObjects: [CatalogObject] = []
    @Published private(set) var displayObjects: [CatalogObject] = []
    @Published private(set) var overviewObjects: [CatalogObject] = []
    @Published private(set) var overviewTrailObjects: [CatalogObject] = []
    private var overviewPropagationActive = false
    private var overviewIDs: Set<String> = []
    private var displayIDs: Set<String> = []
    private struct SceneTargetIdentity {
        let object: CatalogObject
        let isOverview: Bool
        let revealOrder: Double
    }
    private var overviewSceneIdentities: [SceneTargetIdentity] = []
    private var localSceneIdentities: [SceneTargetIdentity] = []
    private var sceneIdentityRevision: UInt = 0
    private struct SceneFrameKey: Equatable {
        let date: Date
        let live: Bool
        let includeLocal: Bool
        let focusedObjectID: String?
        let ephemerisRevision: UInt
        let identityRevision: UInt
        let observer: ObserverLocation.Coordinates
        let pointing: Pointing
    }
    private var cachedSceneFrame: (key: SceneFrameKey, frame: ObservationSceneFrame)?
    #if DEBUG
    private(set) var sceneFrameBuildCount = 0
    #endif

    func sceneFrame(at date: Date, live: Bool = true, includeLocal: Bool = false,
                    focusedObjectID: String? = nil) -> ObservationSceneFrame {
        let frameObserver = ephemeris.frameObserver ?? observer.coordinates
        let key = SceneFrameKey(date: date, live: live, includeLocal: includeLocal,
            focusedObjectID: focusedObjectID, ephemerisRevision: ephemeris.frameRevision,
            identityRevision: sceneIdentityRevision, observer: frameObserver, pointing: pointing)
        if let cachedSceneFrame, cachedSceneFrame.key == key { return cachedSceneFrame.frame }
        let identities = includeLocal ? localSceneIdentities : overviewSceneIdentities
        var targets: [ObservationSceneFrame.Target] = []
        targets.reserveCapacity(identities.count + (focusedObjectID == nil ? 0 : 1))
        for identity in identities {
            guard let sample = ephemeris.cachedEphemeris(identity.object.id, at: date, live: live) else { continue }
            targets.append(.init(object: identity.object, ephemeris: sample,
                isOverview: identity.isOverview, revealOrder: identity.revealOrder))
        }
        if let focusedObjectID,
           !(includeLocal ? displayIDs : overviewIDs).contains(focusedObjectID),
           let focused = catalog.objectsByID[focusedObjectID],
           let sample = ephemeris.cachedEphemeris(focusedObjectID, at: date, live: live) {
            targets.append(.init(object: focused, ephemeris: sample,
                isOverview: true, revealOrder: 0))
        }
        let frame = ObservationSceneFrame(observation: date, observer: frameObserver,
                                          pointing: pointing, targets: targets)
        cachedSceneFrame = (key, frame)
        #if DEBUG
        sceneFrameBuildCount += 1
        #endif
        return frame
    }

    private func prepareSceneIdentity() {
        sceneIdentityRevision &+= 1
        cachedSceneFrame = nil
        overviewIDs = Set(overviewObjects.map(\.id))
        displayIDs = Set(displayObjects.map(\.id))
        let revealOrders = Dictionary(uniqueKeysWithValues: displayObjects.map { object in
            // Inclination groups are a stable reveal order, never a substitute orbit.
            let group = min(5, max(0, floor(object.orbitFingerprint.inclinationDegrees / 30)))
            return (object.id, (group + ObservationSceneMath.revealOrder(object.id)) / 6)
        })
        overviewSceneIdentities = overviewObjects.map { object in
            SceneTargetIdentity(object: object, isOverview: true,
                revealOrder: revealOrders[object.id] ?? 0)
        }
        localSceneIdentities = displayObjects.map { object in
            SceneTargetIdentity(object: object, isOverview: overviewIDs.contains(object.id),
                revealOrder: revealOrders[object.id] ?? 0)
        }
    }

    /// TLE 快照龄期（天）—— 档案层的 EPOCH AGE 字段。
    var tleAgeDays: Int {
        max(0, Int(Date().timeIntervalSince(catalog.snapshotEpoch) / 86400))
    }

    private var cancellables = Set<AnyCancellable>()

    /// 正式启动路径会先在后台准备目录，再在主线程装配轻量会话对象。
    /// 默认值保留给测试与 Preview；它们仍可独立创建完整会话。
    init(catalog: CatalogStore = CatalogStore()) {
        self.catalog = catalog
        ephemeris = EphemerisEngine(store: catalog, observer: ObserverLocation.fallback)
        tracks = TrackSampler(store: catalog)
        passes = PassPredictor(store: catalog)
        insights = SatelliteInsightEngine(store: catalog)
        let initialDisplayObjects = Self.makeDisplaySample(
            from: catalog.objects,
            starlinkDivisor: 8
        )
        let initialOverviewObjects = Self.makeOverviewSample(
            from: initialDisplayObjects
        )
        visibleObjects = catalog.objects
        displayObjects = initialDisplayObjects
        overviewObjects = initialOverviewObjects
        overviewTrailObjects = OverviewAmbientTrailPolicy.select(from: initialOverviewObjects)

        #if targetEnvironment(simulator)
        let manual = ManualPointingProvider()
        manualProvider = manual
        motionProvider = nil
        pointingNavigation = SkyPointingNavigation(deviceDriven: false)
        pointingMode = .browsing
        bind(manual)
        #else
        if CMMotionManager().isDeviceMotionAvailable {
            let motion = MotionPointingProvider()
            let manual = ManualPointingProvider()
            motionProvider = motion
            manualProvider = manual
            pointingNavigation = SkyPointingNavigation(deviceDriven: true)
            pointingMode = .following
            bind(motion)
            bind(manual)
        } else {
            let manual = ManualPointingProvider()
            manualProvider = manual
            motionProvider = nil
            pointingNavigation = SkyPointingNavigation(deviceDriven: false)
            pointingMode = .browsing
            bind(manual)
        }
        #endif

        // 首次进入天空只传播确实会绘制、可捕获的目标，避免完整 16k 目录任务
        // 与用户第一次对焦争抢 CPU。进入全局星图前再切换到完整目录。
        ephemeris.setPropagationObjects(displayObjects)
        prepareSceneIdentity()

        observer.$coordinates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coords in
                self?.ephemeris.updateObserver(coords)
            }
            .store(in: &cancellables)

        observer.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        observer.$authorizationStatus
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.started, let motion = self.motionProvider else { return }
                motion.start(prefersTrueNorth: Self.locationAllowsTrueNorth(status))
            }
            .store(in: &cancellables)
    }

    /// 直接订阅 `@Published` 的新值。过去监听 `objectWillChange` 时，回调发生在属性
    /// 写入之前，会把上一帧姿态复制到会话里，并在设备停止移动时永久落后一帧。
    private func bind(_ provider: ManualPointingProvider) {
        provider.$pointing
            .sink { [weak self, weak provider] pointing in
                guard let self, let provider else { return }
                self.pointingNavigation.ingestManual(pointing)
                self.publishDisplayPointing()
                if self.motionProvider == nil {
                    self.confidence = provider.confidence
                    self.pointingAvailability = .manual
                }
            }
            .store(in: &cancellables)
        if motionProvider == nil {
            confidence = provider.confidence
            pointingAvailability = .manual
        }
    }

    private func bind(_ provider: MotionPointingProvider) {
        Publishers.CombineLatest3(
            provider.$pointing,
            provider.$confidence,
            provider.$availability
        )
            .sink { [weak self] pointing, confidence, availability in
                guard let self else { return }
                self.pointingNavigation.ingestDevice(pointing, availability: availability)
                self.publishDisplayPointing()
                self.confidence = confidence
                self.pointingAvailability = availability
            }
            .store(in: &cancellables)
        confidence = provider.confidence
        pointingAvailability = provider.availability
    }

    func beginManualBrowse() {
        let origin = pointingNavigation.beginBrowsing()
        manualProvider?.reset(to: origin)
        publishDisplayPointing()
    }

    @discardableResult
    func recenterPointing(at time: TimeInterval, reducedMotion: Bool) -> Bool {
        manualProvider?.stop()
        let ready = pointingNavigation.recenter(at: time, reducedMotion: reducedMotion)
        publishDisplayPointing()
        return ready
    }

    /// Driven by the existing sky frame clock, never by a second sensor or timer.
    func advancePointingNavigation(at time: TimeInterval) {
        pointingNavigation.advance(at: time)
        publishDisplayPointing()
    }

    private func publishDisplayPointing() {
        if pointing != pointingNavigation.pointing { pointing = pointingNavigation.pointing }
        if pointingMode != pointingNavigation.mode { pointingMode = pointingNavigation.mode }
    }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        manualProvider?.start()
        motionProvider?.start(
            prefersTrueNorth: Self.locationAllowsTrueNorth(observer.authorizationStatus)
        )
        ephemeris.start()
    }

    /// 只在用户完成首启说明、真正进入天空后请求定位。
    func requestObserverAccess() {
        #if !targetEnvironment(simulator)
        observer.request()
        #endif
    }

    func stop() {
        guard started else { return }
        started = false
        manualProvider?.stop()
        motionProvider?.stop()
        observer.stop()
        ephemeris.stop()
    }

    /// 在轻量加载页仍可见时预热首次捕获会用到的“速度精算 + 多时刻轨迹”路径。
    /// 在 utility 后台执行，不阻塞首份轨道快照。
    func prewarmCapturePipeline(at date: Date = Date()) async {
        guard let objectID = displayObjects.first?.id else { return }
        async let precise = ephemeris.preparePreciseEphemeris(
            objectID,
            at: date,
            live: true
        )
        async let track: Void = tracks.prewarm(
            observer: observer.coordinates,
            at: date
        )
        async let insight: Void = insights.prewarm(
            objectID: objectID,
            observer: observer.coordinates,
            at: date
        )
        _ = await (precise, track, insight)
    }

    private nonisolated static func locationAllowsTrueNorth(
        _ status: CLAuthorizationStatus
    ) -> Bool {
        status == .authorizedAlways || status == .authorizedWhenInUse
    }

    var activeCatalogFilterCount: Int {
        catalogFilters.count + (catalogScope == .all ? 0 : 1)
    }

    /// 显示范围互斥；改变后立即作用于天空。
    func setCatalogScope(_ scope: CatalogScope) {
        guard scope != catalogScope else { return }
        catalogScope = scope
        applyCatalogSelection()
    }

    /// 任务、运营方和轨道网络可多选。同组取并集，不同组取交集。
    func toggleCatalogFilter(_ filter: CatalogFilter) {
        guard filter != .all else {
            resetCatalogFilters()
            return
        }
        if catalogFilters.contains(filter) {
            catalogFilters.remove(filter)
        } else {
            catalogFilters.insert(filter)
        }
        applyCatalogSelection()
    }

    /// 常用镜片是一个快速起点：选择后清空上一组组合条件，再建立单一镜片。
    /// 完整筛选区仍保留同组并集、跨组交集的原有语义。
    func setFrequentLens(_ filter: CatalogFilter) {
        guard CatalogFilter.frequentLenses.contains(filter) else { return }
        catalogScope = .all
        catalogFilters.removeAll()
        if filter != .all {
            catalogFilters.insert(filter)
        }
        applyCatalogSelection()
    }

    func resetCatalogFilters() {
        guard catalogScope != .all || !catalogFilters.isEmpty else { return }
        catalogScope = .all
        catalogFilters.removeAll()
        applyCatalogSelection()
    }

    /// 局部天空只需要显示采样；全局星图才需要完整筛选结果。切换只改变后续
    /// 后台帧，已有样本会保留，因此尺度过渡不会先清空再重建点云。
    func setOverviewPropagationActive(_ active: Bool) {
        guard overviewPropagationActive != active else { return }
        overviewPropagationActive = active
        sceneIdentityRevision &+= 1
        cachedSceneFrame = nil
        ephemeris.setPropagationObjects(active ? overviewObjects : displayObjects)
    }

    private func applyCatalogSelection() {
        let grouped = Dictionary(grouping: catalogFilters, by: \.group)
        let objects = catalog.objects.filter { object in
            guard catalogScope.includes(object) else { return false }
            for group in [
                CatalogFilterGroup.overview,
                CatalogFilterGroup.mission,
                CatalogFilterGroup.authority,
                CatalogFilterGroup.constellation,
            ] {
                guard let filters = grouped[group], !filters.isEmpty else { continue }
                guard filters.contains(where: { $0.includes(object) }) else { return false }
            }
            return true
        }
        visibleObjects = objects
        displayObjects = Self.makeDisplaySample(from: objects, starlinkDivisor: 8)
        overviewObjects = Self.makeOverviewSample(from: displayObjects)
        prepareSceneIdentity()
        overviewTrailObjects = OverviewAmbientTrailPolicy.select(from: overviewObjects)
        ephemeris.setPropagationObjects(
            overviewPropagationActive ? overviewObjects : displayObjects
        )
    }

    /// 完整数据保留在 `visibleObjects`；默认绘制对大型星座分别做确定性抽样。
    /// 深度档案目标永远保留，避免策展入口因为密度收束而从天空消失。
    nonisolated static func makeDisplaySample(
        from objects: [CatalogObject],
        starlinkDivisor: Int
    ) -> [CatalogObject] {
        // 已经经过具体镜片筛选的小目录不再二次抽稀。这样导航、移动通信等
        // 百余颗规模的真实集合能够提供足够观测密度；完整天空才压低大型星座。
        guard starlinkDivisor > 1, objects.count > 1_400 else { return objects }
        return objects.filter { object in
            guard let family = object.family else { return true }
            if object.isCurated || object.isFeatured { return true }
            let divisor: Int = switch family {
            case .starlink: starlinkDivisor
            case .oneweb, .qianfan, .hulianwang: max(2, starlinkDivisor / 3)
            case .kuiper, .iridium, .globalstar, .orbcomm: max(2, starlinkDivisor / 4)
            }
            return object.noradId.isMultiple(of: divisor)
        }
    }

    /// 地球仪保留数千颗真实目标形成完整轨道密度，但使用局部天空已经传播过的
    /// 集合做稳定上限抽样。这样开始缩小的第一帧便有位置数据，也不会在转场中
    /// 突然启动完整目录传播。精选目标始终保留，其他目标按目录顺序均匀取样。
    nonisolated static func makeOverviewSample(
        from objects: [CatalogObject],
        limit: Int = 4_600
    ) -> [CatalogObject] {
        guard limit > 0, objects.count > limit else { return objects }

        var selected = Set(
            objects.lazy
                .filter { $0.isCurated || $0.isFeatured }
                .map(\.id)
        )
        let remaining = max(0, limit - selected.count)
        guard remaining > 0 else {
            return objects.filter { selected.contains($0.id) }
        }

        let step = Double(objects.count) / Double(remaining)
        var cursor = step * 0.5
        while selected.count < limit, Int(cursor) < objects.count {
            selected.insert(objects[Int(cursor)].id)
            cursor += step
        }
        if selected.count < limit {
            for object in objects where selected.count < limit {
                selected.insert(object.id)
            }
        }
        return objects.filter { selected.contains($0.id) }
    }

}
