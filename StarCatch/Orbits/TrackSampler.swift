import Foundation
import SatelliteKit

/// Factual local-sky samples, stamped at their observation time. Reading views
/// consume this value without scheduling propagation from their drawing code.
struct SatelliteTrackSnapshot: Sendable {
    let objectID: String
    let referenceDate: Date
    let points: [TrackSampler.TrackPoint]

    var finitePoints: [TrackSampler.TrackPoint] {
        points.filter { $0.offset.isFinite && $0.elevation.isFinite && $0.azimuth.isFinite }
            .sorted { $0.offset < $1.offset }
    }

    /// Keep at least 20 degrees on the vertical axis so GEO motion is not exaggerated.
    var elevationBounds: ClosedRange<Double> {
        let values = finitePoints.map { $0.elevation * 180 / .pi }
        let lower = floor((values.min() ?? -10) / 10) * 10 - 5
        let upper = ceil((values.max() ?? 10) / 10) * 10 + 5
        let middle = (lower + upper) / 2
        let halfSpan = max(10, (upper - lower) / 2)
        let clippedUpper = min(90, middle + halfSpan)
        let clippedLower = max(-90, min(middle - halfSpan, clippedUpper - 20))
        return clippedLower ... min(90, max(clippedUpper, clippedLower + 20))
    }
}

/// 锁定对象的轨迹弧采样：t ± 3min，每 20s 一点。
/// 结果是 az/el 折线，投影后由渲染层平滑。
@MainActor
final class TrackSampler {

    struct TrackPoint: Sendable {
        let azimuth: Double
        let elevation: Double
        /// 相对当前的秒偏移（负 = 过去）。
        let offset: TimeInterval
    }

    private let store: CatalogStore
    private var cachedObjectId: String?
    private var cachedAt: Date?
    /// 缓存对应的观测时刻 —— 拨动时间时轨迹要跟着走。
    private var cachedObservation: Date?
    private var cachedTrack: [TrackPoint] = []
    private var preparationTask: Task<Void, Never>?
    private var preparingObjectId: String?

    /// 缓存有效期 —— 轨迹弧不需要每帧重算。
    private let cacheLifetime: TimeInterval = 10

    init(store: CatalogStore) {
        self.store = store
    }

    func track(
        for objectId: String,
        observer: ObserverLocation.Coordinates,
        at now: Date
    ) -> [TrackPoint] {
        if cacheIsValid(for: objectId, at: now) {
            return cachedTrack
        }
        prepareTrack(for: objectId, observer: observer, at: now)
        return []
    }

    /// 感应一开始即异步准备轨迹。Canvas 在缓存抵达前宁可省略一帧轨迹，
    /// 也不在锁定完成的那一帧同步传播 19 个时间点。
    func prepareTrack(
        for objectId: String,
        observer: ObserverLocation.Coordinates,
        at now: Date
    ) {
        guard !cacheIsValid(for: objectId, at: now) else { return }
        if preparingObjectId == objectId, preparationTask != nil { return }
        guard let sat = store.satellites[objectId] else { return }

        preparationTask?.cancel()
        preparingObjectId = objectId
        preparationTask = Task.detached(priority: .utility) {
            let points = Self.sampleTrack(
                satellite: sat,
                observer: observer,
                at: now
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.preparingObjectId == objectId else { return }
                self.cachedObjectId = objectId
                self.cachedAt = Date()
                self.cachedObservation = now
                self.cachedTrack = points
                self.preparingObjectId = nil
                self.preparationTask = nil
            }
        }
    }

    /// Return cached data only. Safe for a view's presentation assembly.
    func preparedSnapshot(for objectID: String) -> SatelliteTrackSnapshot? {
        guard cachedObjectId == objectID, let referenceDate = cachedObservation,
              !cachedTrack.isEmpty else { return nil }
        return SatelliteTrackSnapshot(objectID: objectID, referenceDate: referenceDate, points: cachedTrack)
    }

    /// A reading page owns one immutable trace, even while the sky is suspended.
    func snapshot(
        for objectID: String,
        observer: ObserverLocation.Coordinates,
        at date: Date
    ) async -> SatelliteTrackSnapshot? {
        if cacheIsValid(for: objectID, at: date) { return preparedSnapshot(for: objectID) }
        if preparingObjectId == objectID, let preparationTask {
            await preparationTask.value
            guard !Task.isCancelled else { return nil }
            if cacheIsValid(for: objectID, at: date) { return preparedSnapshot(for: objectID) }
        }
        guard let satellite = store.satellites[objectID] else { return nil }
        let points = await Task.detached(priority: .userInitiated) {
            Self.sampleTrack(satellite: satellite, observer: observer, at: date)
        }.value
        guard !Task.isCancelled, !points.isEmpty else { return nil }
        return SatelliteTrackSnapshot(objectID: objectID, referenceDate: date, points: points)
    }

    /// 启动叙事期间只运行一次 SatelliteKit 的多时刻传播路径。结果无需保留；
    /// 目的只是把库级冷初始化移出第一次目标感应动画。
    func prewarm(observer: ObserverLocation.Coordinates, at now: Date) async {
        guard let satellite = store.satellites.values.first else { return }
        _ = await Task.detached(priority: .utility) {
            Self.sampleTrack(satellite: satellite, observer: observer, at: now)
        }.value
    }

    nonisolated private static func sampleTrack(
        satellite: Satellite,
        observer: ObserverLocation.Coordinates,
        at now: Date
    ) -> [TrackPoint] {
        let geo = LatLonAlt(
            observer.latitude,
            observer.longitude,
            observer.altitudeMeters / 1000.0
        )
        var points: [TrackPoint] = []
        points.reserveCapacity(19)
        var offset: TimeInterval = -180
        while offset <= 180 {
            if Task.isCancelled { return [] }
            let jd = now.addingTimeInterval(offset).julianDate
            if let topo = try? satellite.topPosition(julianDays: jd, observer: geo) {
                points.append(TrackPoint(
                    azimuth: topo.azim * .pi / 180,
                    elevation: topo.elev * .pi / 180,
                    offset: offset
                ))
            }
            offset += 20
        }
        return points
    }

    private func cacheIsValid(for objectId: String, at now: Date) -> Bool {
        cachedObjectId == objectId
            && cachedAt.map { Date().timeIntervalSince($0) < cacheLifetime } == true
            && cachedObservation.map { abs($0.timeIntervalSince(now)) < 5 } == true
    }

    func invalidate() {
        preparationTask?.cancel()
        preparationTask = nil
        preparingObjectId = nil
        cachedObjectId = nil
        cachedAt = nil
        cachedObservation = nil
        cachedTrack = []
    }
}
