import Combine
import CoreMotion
import Foundation
import SwiftUI

/// 会话装配：按环境选择指向源，持有观察者坐标与轨道推算引擎。
@MainActor
final class SkySession: ObservableObject {

    let manualProvider: ManualPointingProvider?
    let motionProvider: MotionPointingProvider?
    let observer = ObserverLocation()
    let catalog = CatalogStore()
    let ephemeris: EphemerisEngine
    let tracks: TrackSampler
    let passes: PassPredictor
    let log = ObservationLog()

    @Published private(set) var pointing: Pointing = .initial
    @Published private(set) var confidence: HeadingConfidence = .manual
    @Published private(set) var catalogFilter: CatalogFilter = .all
    @Published private(set) var visibleObjects: [CatalogObject] = []
    @Published private(set) var displayObjects: [CatalogObject] = []
    @Published private(set) var overviewObjects: [CatalogObject] = []
    @Published private(set) var visibleTrailObjects: [CatalogObject] = []

    /// TLE 快照龄期（天）—— 档案层的 EPOCH AGE 字段。
    var tleAgeDays: Int {
        max(0, Int(Date().timeIntervalSince(catalog.snapshotEpoch) / 86400))
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        ephemeris = EphemerisEngine(store: catalog, observer: ObserverLocation.fallback)
        tracks = TrackSampler(store: catalog)
        passes = PassPredictor(store: catalog)
        let initialOverviewObjects = Self.makeDisplaySample(
            from: catalog.objects,
            starlinkDivisor: 14
        )
        visibleObjects = catalog.objects
        displayObjects = Self.makeDisplaySample(from: catalog.objects, starlinkDivisor: 8)
        overviewObjects = initialOverviewObjects
        visibleTrailObjects = Self.makeTrailSample(from: initialOverviewObjects)

        #if targetEnvironment(simulator)
        let manual = ManualPointingProvider()
        manualProvider = manual
        motionProvider = nil
        bind(manual)
        #else
        if CMMotionManager().isDeviceMotionAvailable {
            let motion = MotionPointingProvider()
            motionProvider = motion
            manualProvider = nil
            bind(motion)
        } else {
            let manual = ManualPointingProvider()
            manualProvider = manual
            motionProvider = nil
            bind(manual)
        }
        #endif

        observer.$coordinates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coords in
                self?.ephemeris.updateObserver(coords)
            }
            .store(in: &cancellables)
    }

    /// 直接订阅 `@Published` 的新值。过去监听 `objectWillChange` 时，回调发生在属性
    /// 写入之前，会把上一帧姿态复制到会话里，并在设备停止移动时永久落后一帧。
    private func bind(_ provider: ManualPointingProvider) {
        provider.$pointing
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak provider] pointing in
                guard let self, let provider else { return }
                self.pointing = pointing
                self.confidence = provider.confidence
            }
            .store(in: &cancellables)
        confidence = provider.confidence
    }

    private func bind(_ provider: MotionPointingProvider) {
        Publishers.CombineLatest(provider.$pointing, provider.$confidence)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pointing, confidence in
                self?.pointing = pointing
                self?.confidence = confidence
            }
            .store(in: &cancellables)
        confidence = provider.confidence
    }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        manualProvider?.start()
        motionProvider?.start()
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
        ephemeris.stop()
    }

    /// 默认保留完整目录；用户选择的类别只改变当前天空，不改写观测历史。
    func setCatalogFilter(_ filter: CatalogFilter) {
        guard filter != catalogFilter else { return }
        catalogFilter = filter
        let objects = catalog.objects(matching: filter)
        visibleObjects = objects
        displayObjects = Self.makeDisplaySample(from: objects, starlinkDivisor: 8)
        overviewObjects = Self.makeDisplaySample(from: objects, starlinkDivisor: 14)
        visibleTrailObjects = Self.makeTrailSample(from: overviewObjects)
        ephemeris.setPropagationObjects(objects)
    }

    /// 完整数据保留在 `visibleObjects`；默认绘制只对 Starlink 做确定性抽样。
    nonisolated static func makeDisplaySample(
        from objects: [CatalogObject],
        starlinkDivisor: Int
    ) -> [CatalogObject] {
        guard starlinkDivisor > 1 else { return objects }
        return objects.filter { object in
            !object.isStarlink || object.isCurated || object.noradId.isMultiple(of: starlinkDivisor)
        }
    }

    /// 全部点位仍参与显示、捕捉和方向信标；只有长光轨使用稳定的代表性子集，
    /// 避免上万条轨迹把星图涂成一整片亮面并占用过多内存。
    private static func makeTrailSample(
        from objects: [CatalogObject],
        limit: Int = 180
    ) -> [CatalogObject] {
        guard objects.count > limit else { return objects }

        var result = Array(objects.lazy.filter(\.isCurated).prefix(min(48, limit)))
        var selected = Set(result.map(\.id))
        let remaining = max(1, limit - result.count)
        let strideLength = max(1, objects.count / remaining)
        var index = 0
        while index < objects.count, result.count < limit {
            let object = objects[index]
            if selected.insert(object.id).inserted { result.append(object) }
            index += strideLength
        }
        return result
    }
}
