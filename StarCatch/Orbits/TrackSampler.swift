import Foundation
import SatelliteKit

/// 锁定对象的轨迹弧采样：t ± 3min，每 20s 一点。
/// 结果是 az/el 折线，投影后由渲染层平滑。
@MainActor
final class TrackSampler {

    struct TrackPoint {
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
        if cachedObjectId == objectId,
           let at = cachedAt,
           let obs = cachedObservation,
           Date().timeIntervalSince(at) < cacheLifetime,
           abs(obs.timeIntervalSince(now)) < 5 {
            return cachedTrack
        }
        guard let sat = store.satellites[objectId] else { return [] }

        let geo = LatLonAlt(observer.latitude, observer.longitude, observer.altitudeMeters / 1000.0)
        var points: [TrackPoint] = []
        var offset: TimeInterval = -180
        while offset <= 180 {
            let jd = now.addingTimeInterval(offset).julianDate
            if let topo = try? sat.topPosition(julianDays: jd, observer: geo) {
                points.append(TrackPoint(
                    azimuth: topo.azim * .pi / 180,
                    elevation: topo.elev * .pi / 180,
                    offset: offset
                ))
            }
            offset += 20
        }

        cachedObjectId = objectId
        cachedAt = Date()
        cachedObservation = now
        cachedTrack = points
        return points
    }

    func invalidate() {
        cachedObjectId = nil
        cachedAt = nil
        cachedObservation = nil
        cachedTrack = []
    }
}
