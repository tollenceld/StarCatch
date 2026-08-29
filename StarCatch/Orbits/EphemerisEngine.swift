import Foundation
import SatelliteKit

/// 单个对象在某时刻的观测量。
struct Ephemeris: Sendable {
    let objectId: String
    /// 方位角，弧度，0 = 北，顺时针。
    var azimuth: Double
    /// 仰角，弧度。
    var elevation: Double
    /// 到观察者距离 km。
    var rangeKm: Double
    /// 轨道高度 km（近似：位置模长 - 地球半径）。
    var altitudeKm: Double
    /// 速度标量 km/s。
    var velocityKmS: Double
    /// 地心惯性坐标（ECI，km）。全局轨道球与主视野共享同一传播真值。
    var orbitalPosition: SIMD3<Double>
}

/// 在后台周期性传播本地目录，并把完整帧一次性提交给界面。
///
/// 天空和星图只消费批量缓存中的方位、仰角与距离。高度和速度仅在用户锁定
/// 单颗目标时精算并短时缓存，避免为数万颗不可见目标重复执行无用传播。
@MainActor
final class EphemerisEngine: ObservableObject {

    struct Sample: Sendable {
        var current: Ephemeris
        var previous: Ephemeris?
        var currentTime: Date
        var previousTime: Date?
    }

    /// SwiftUI 只观察轻量版本号。热路径中的每次字典查询不经过 `@Published`
    /// 包装器，避免在 16k 点位 × 帧率下反复触发动态类型检查。
    @Published private(set) var frameRevision: UInt = 0
    private var samples: [String: Sample] = [:]
    private var frozenSnapshot: [String: Ephemeris] = [:]

    private let store: CatalogStore
    private var observer: ObserverLocation.Coordinates
    private var propagationObjectIDs: [String]
    private var timer: Timer?
    private var liveTask: Task<Void, Never>?
    private var warmupTask: Task<Void, Never>?
    private var frozenTask: Task<Void, Never>?
    private var pendingFrozenDate: Date?
    private var frozenSnapshotTime: Date?
    private var isRunning = false

    private struct PreciseKey: Hashable {
        let objectId: String
        let timeBucket: Int64
    }
    private var preciseCache: [PreciseKey: Ephemeris] = [:]

    /// LIVE 帧周期。帧间由角度插值补齐。
    private let interval: TimeInterval = 4.0
    /// 时间轴只保留最新请求；四分之一秒桶避免手指细微抖动造成重复任务。
    private let frozenBucketInterval: TimeInterval = 0.25

    /// 测试与仪器诊断使用；不暴露对象内容，避免界面绕过目录所有权。
    var activePropagationObjectCount: Int { propagationObjectIDs.count }

    init(store: CatalogStore, observer: ObserverLocation.Coordinates) {
        self.store = store
        self.observer = observer
        propagationObjectIDs = store.objects.map(\.id)
    }

    func updateObserver(_ coordinates: ObserverLocation.Coordinates) {
        guard coordinates != observer else { return }
        observer = coordinates
        preciseCache.removeAll(keepingCapacity: true)
        if isRunning { requestLiveFrame() }
        if let frozenSnapshotTime {
            prepareSnapshot(at: frozenSnapshotTime)
        }
    }

    func start() {
        isRunning = true
        requestLiveFrame()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestLiveFrame() }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        liveTask?.cancel()
        liveTask = nil
        warmupTask?.cancel()
        warmupTask = nil
        frozenTask?.cancel()
        frozenTask = nil
        pendingFrozenDate = nil
    }

    /// 筛选不仅减少绘制，也缩小后续后台传播帧；单颗精算仍可读取完整目录。
    func setPropagationObjects(_ objects: [CatalogObject]) {
        let nextObjectIDs = objects.map(\.id)
        guard nextObjectIDs != propagationObjectIDs else { return }
        // 过滤器可能在旧的 16k 传播任务尚未结束时切换。取消旧任务并立即按新集合
        // 重建，避免上一帧在数秒后反向覆盖新筛选结果。
        liveTask?.cancel()
        liveTask = nil
        warmupTask?.cancel()
        warmupTask = nil
        frozenTask?.cancel()
        frozenTask = nil
        pendingFrozenDate = nil
        propagationObjectIDs = nextObjectIDs
        frozenSnapshotTime = nil
        frozenSnapshot.removeAll(keepingCapacity: true)
        preciseCache.removeAll(keepingCapacity: true)
        if isRunning { requestLiveFrame() }
    }

    /// LIVE 观测的插值量。完整帧之间保留连续运动。
    func interpolated(_ objectId: String, at date: Date) -> Ephemeris? {
        guard let sample = samples[objectId] else { return nil }
        guard let previous = sample.previous, let previousTime = sample.previousTime else {
            return sample.current
        }
        let span = sample.currentTime.timeIntervalSince(previousTime)
        guard span > 0 else { return sample.current }
        // `current` 是最近一次真实 SGP4 帧。当前时刻通常位于它之后，因此允许
        // 线性外推覆盖完整 4 秒帧间；即使首个速度样本间隔较短也不会中途冻结。
        // 若后台传播异常停滞，则最多继续预测一个帧周期再停住。
        let elapsed = max(0, date.timeIntervalSince(previousTime))
        let boundedElapsed = min(span + interval * 1.25, elapsed)
        let progress = boundedElapsed / span

        var result = sample.current
        result.azimuth = Self.lerpAngle(previous.azimuth, sample.current.azimuth, progress)
        result.elevation = previous.elevation
            + (sample.current.elevation - previous.elevation) * progress
        result.rangeKm = previous.rangeKm
            + (sample.current.rangeKm - previous.rangeKm) * progress
        result.altitudeKm = previous.altitudeKm
            + (sample.current.altitudeKm - previous.altitudeKm) * progress
        result.orbitalPosition = previous.orbitalPosition
            + (sample.current.orbitalPosition - previous.orbitalPosition) * progress
        return result
    }

    // MARK: - 批量缓存

    /// 请求任意观测时刻的完整帧。若上一帧仍在计算，只保留手指最新位置。
    func prepareSnapshot(at date: Date) {
        let requestedKey = bucket(for: date)
        if let frozenSnapshotTime, bucket(for: frozenSnapshotTime) == requestedKey {
            return
        }
        if let pendingFrozenDate, bucket(for: pendingFrozenDate) == requestedKey {
            return
        }
        pendingFrozenDate = date
        launchPendingFrozenFrameIfNeeded()
    }

    /// 大规模渲染入口：绝不在 Canvas 内同步传播轨道。
    /// 新时间帧尚未抵达时继续显示上一帧，随后由一次发布原位更新。
    func cachedEphemeris(
        _ objectId: String,
        at observationTime: Date,
        live: Bool
    ) -> Ephemeris? {
        if live { return interpolated(objectId, at: observationTime) }
        return frozenSnapshot[objectId] ?? samples[objectId]?.current
    }

    /// 单颗目标的精确入口：用于档案、观测记录和锁定瞬间。
    func ephemeris(_ objectId: String, at observationTime: Date, live: Bool) -> Ephemeris? {
        let key = preciseKey(
            objectId: objectId,
            observationTime: observationTime,
            live: live
        )
        if let cached = preciseCache[key] { return cached }
        guard let satellite = store.satellites[objectId] else { return nil }
        let result = Self.preciseEphemeris(
            objectId: objectId,
            satellite: satellite,
            date: observationTime,
            observer: observer
        )
        if preciseCache.count > 192 {
            preciseCache.removeAll(keepingCapacity: true)
        }
        preciseCache[key] = result
        return result
    }

    /// 视图渲染只能读取已经准备好的精确遥测，绝不在 `body` 首次出现时同步传播。
    func cachedPreciseEphemeris(
        _ objectId: String,
        at observationTime: Date,
        live: Bool
    ) -> Ephemeris? {
        preciseCache[
            preciseKey(
                objectId: objectId,
                observationTime: observationTime,
                live: live
            )
        ]
    }

    /// 目标进入感应阶段便在后台精算遥测。通常比底部摘要出现早约一秒，从而把
    /// SatelliteKit 的首次 position/velocity 成本移出锁定动画帧。
    func preparePreciseEphemeris(
        _ objectId: String,
        at observationTime: Date,
        live: Bool
    ) async -> Ephemeris? {
        let key = preciseKey(
            objectId: objectId,
            observationTime: observationTime,
            live: live
        )
        if let cached = preciseCache[key] { return cached }
        guard let satellite = store.satellites[objectId] else { return nil }
        let capturedObserver = observer
        let result = await Task.detached(priority: .utility) {
            Self.preciseEphemeris(
                objectId: objectId,
                satellite: satellite,
                date: observationTime,
                observer: capturedObserver
            )
        }.value
        guard !Task.isCancelled,
              observer == capturedObserver,
              let result
        else { return nil }
        if preciseCache.count > 192 {
            preciseCache.removeAll(keepingCapacity: true)
        }
        preciseCache[key] = result
        return result
    }

    /// 测试和低频工具使用的明确目标集合；不再提供隐式“全目录同步计算”。
    func snapshot(at date: Date, objectIDs: Set<String>) -> [String: Ephemeris] {
        var result: [String: Ephemeris] = [:]
        result.reserveCapacity(objectIDs.count)
        for objectId in objectIDs {
            guard let satellite = store.satellites[objectId],
                  let ephemeris = Self.preciseEphemeris(
                    objectId: objectId,
                    satellite: satellite,
                    date: date,
                    observer: observer
                  ) else { continue }
            result[objectId] = ephemeris
        }
        return result
    }

    private func requestLiveFrame() {
        guard liveTask == nil else { return }
        let date = Date()
        let capturedObserver = observer
        let satellites = store.satellites
        let objectIDs = propagationObjectIDs
        // 完整目录传播是持续后台工作，不能与首次捕获动画争抢 userInitiated CPU。
        // 精确目标仍由独立缓存补齐，主界面在两帧之间使用插值。
        liveTask = Task.detached(priority: .utility) { [self] in
            let frame = Self.bulkSnapshot(
                satellites: satellites,
                objectIDs: objectIDs,
                date: date,
                observer: capturedObserver
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.liveTask = nil
                guard self.observer == capturedObserver else {
                    self.requestLiveFrame()
                    return
                }
                let needsWarmup = frame.keys.contains { self.samples[$0] == nil }
                // 镜片切换只改变下一轮需要更新的对象，不销毁此前完整目录的缓存。
                // 因此从一个小集合切到另一个集合时，真实旧位置可以立即出现，
                // 并在本轮传播完成后平滑更新，而不是先给用户一片空天空。
                var next = self.samples
                next.reserveCapacity(max(next.count, frame.count))
                for (objectId, ephemeris) in frame {
                    let previous = self.samples[objectId]
                    next[objectId] = Sample(
                        current: ephemeris,
                        previous: previous?.current,
                        currentTime: date,
                        previousTime: previous?.currentTime
                    )
                }
                self.samples = next
                self.frameRevision &+= 1
                if needsWarmup, self.warmupTask == nil {
                    self.warmupTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(850))
                        guard !Task.isCancelled else { return }
                        self.warmupTask = nil
                        self.requestLiveFrame()
                    }
                }
            }
        }
    }

    private func launchPendingFrozenFrameIfNeeded() {
        guard frozenTask == nil, let date = pendingFrozenDate else { return }
        pendingFrozenDate = nil
        let capturedObserver = observer
        let satellites = store.satellites
        let objectIDs = propagationObjectIDs
        frozenTask = Task.detached(priority: .userInitiated) { [self] in
            let frame = Self.bulkSnapshot(
                satellites: satellites,
                objectIDs: objectIDs,
                date: date,
                observer: capturedObserver
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.frozenTask = nil
                if self.observer == capturedObserver {
                    self.frozenSnapshotTime = date
                    self.frozenSnapshot = frame
                    self.frameRevision &+= 1
                }
                self.launchPendingFrozenFrameIfNeeded()
            }
        }
    }

    nonisolated private static func bulkSnapshot(
        satellites: [String: Satellite],
        objectIDs: [String],
        date: Date,
        observer: ObserverLocation.Coordinates
    ) -> [String: Ephemeris] {
        let julianDays = date.julianDate
        let location = LatLonAlt(
            observer.latitude,
            observer.longitude,
            observer.altitudeMeters / 1000.0
        )
        var result: [String: Ephemeris] = [:]
        result.reserveCapacity(objectIDs.count)

        for (index, objectId) in objectIDs.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return [:] }
            guard let satellite = satellites[objectId],
                  let position = try? satellite.position(julianDays: julianDays)
            else { continue }
            let topocentric = Self.topocentricPosition(
                julianDays: julianDays,
                satCel: position,
                obsLLA: location
            )
            result[objectId] = Ephemeris(
                objectId: objectId,
                azimuth: topocentric.azim * .pi / 180,
                elevation: topocentric.elev * .pi / 180,
                rangeKm: topocentric.dist,
                // 批量帧只用于空间绘制；避免为数千点再做一次地理坐标迭代。
                // 用户可见的精确高度由单目标 preciseEphemeris 提供。
                altitudeKm: position.magnitude() - 6378.137,
                velocityKmS: 0,
                orbitalPosition: SIMD3(position.x, position.y, position.z)
            )
        }
        return result
    }

    nonisolated private static func preciseEphemeris(
        objectId: String,
        satellite: Satellite,
        date: Date,
        observer: ObserverLocation.Coordinates
    ) -> Ephemeris? {
        let julianDays = date.julianDate
        let location = LatLonAlt(
            observer.latitude,
            observer.longitude,
            observer.altitudeMeters / 1000.0
        )
        guard let position = try? satellite.position(julianDays: julianDays),
              let velocity = try? satellite.velocity(julianDays: julianDays) else {
            return nil
        }
        let topocentric = Self.topocentricPosition(
            julianDays: julianDays,
            satCel: position,
            obsLLA: location
        )
        return Ephemeris(
            objectId: objectId,
            azimuth: topocentric.azim * .pi / 180,
            elevation: topocentric.elev * .pi / 180,
            rangeKm: topocentric.dist,
            altitudeKm: eci2geo(
                julianDays: julianDays,
                celestial: position
            ).alt,
            velocityKmS: velocity.magnitude(),
            orbitalPosition: SIMD3(position.x, position.y, position.z)
        )
    }

    /// 与 `Satellite.topPosition` 使用完全相同的距离定义，但复用已经传播出的
    /// ECI 坐标，避免为了方位/仰角再次执行 SGP4。SatelliteKit 的同名全局
    /// helper 使用另一种距离路径，会在仰角上产生约 0.03° 的差异。
    nonisolated private static func topocentricPosition(
        julianDays: Double,
        satCel: Vector,
        obsLLA: LatLonAlt
    ) -> AziEleDst {
        let observer = geo2eci(julianDays: julianDays, geodetic: obsLLA)
        let top = cel2top(julianDays: julianDays, satCel: satCel, obsCel: observer)
        let distance = top.magnitude()
        return AziEleDst(
            atan2pi(top.y, -top.x) * rad2deg,
            asin(top.z / distance) * rad2deg,
            distance
        )
    }

    private func bucket(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / frozenBucketInterval).rounded())
    }

    private func preciseKey(
        objectId: String,
        observationTime: Date,
        live: Bool
    ) -> PreciseKey {
        let cacheInterval = live ? interval : frozenBucketInterval
        return PreciseKey(
            objectId: objectId,
            timeBucket: Int64(
                (observationTime.timeIntervalSince1970 / cacheInterval).rounded()
            )
        )
    }

    /// 角度插值（处理 ±π 回绕）。
    nonisolated static func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var delta = b - a
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return a + delta * t
    }
}

extension Date {
    /// UTC Julian date。
    var julianDate: Double {
        timeIntervalSince1970 / 86400.0 + 2440587.5
    }
}
