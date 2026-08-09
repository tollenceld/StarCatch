import Foundation
import SatelliteKit

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
