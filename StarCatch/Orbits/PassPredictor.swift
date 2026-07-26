import Foundation
import SatelliteKit

/// 过境预报 —— 对象下一次升起/落下的时刻。
///
/// LEO 对象几小时一圈，"下一次经过"是用户再次打开仪器的理由。
/// GEO 常驻天空（elevation 恒定），预报对它没有意义，返回 .stationary。
@MainActor
final class PassPredictor {

    enum Prediction: Equatable {
        /// 下一次升起（当前在地平线下）。
        case rises(at: Date)
        /// 将在此时刻落下（当前在地平线上）。
        case sets(at: Date)
        /// 常驻（GEO 类，仰角基本不变）。
        case stationary
        /// 24h 内无过境。
        case none
    }

    private struct CacheKey: Hashable {
        let objectId: String
        let latitudeCentidegrees: Int
        let longitudeCentidegrees: Int
    }

    private let store: CatalogStore
    private var cache: [CacheKey: (prediction: Prediction, at: Date)] = [:]
    /// 预报缓存 60s —— 分钟级精度足够。
    private let cacheLifetime: TimeInterval = 60

    init(store: CatalogStore) {
        self.store = store
    }

    func nextPass(
        for objectId: String,
        observer: ObserverLocation.Coordinates,
        after start: Date
    ) -> Prediction {
        let key = CacheKey(
            objectId: objectId,
            latitudeCentidegrees: Int((observer.latitude * 100).rounded()),
            longitudeCentidegrees: Int((observer.longitude * 100).rounded())
        )
        if let cached = cache[key],
           Date().timeIntervalSince(cached.at) < cacheLifetime {
            return cached.prediction
        }
        let prediction = compute(objectId: objectId, observer: observer, start: start)
        cache[key] = (prediction, Date())
        return prediction
    }

    private func compute(
        objectId: String,
        observer: ObserverLocation.Coordinates,
        start: Date
    ) -> Prediction {
        guard let sat = store.satellites[objectId] else { return .none }
        let geo = LatLonAlt(observer.latitude, observer.longitude, observer.altitudeMeters / 1000.0)

        func elevation(at t: Date) -> Double? {
            (try? sat.topPosition(julianDays: t.julianDate, observer: geo))?.elev
        }

        guard let e0 = elevation(at: start) else { return .none }

        // GEO/静止判定：1 小时后仰角变化 < 0.5°
        if let e1h = elevation(at: start.addingTimeInterval(3600)),
           abs(e1h - e0) < 0.5, e0 > 0 {
            return .stationary
        }

        // 粗扫 + 二分找地平线穿越。步长 60s，扫 24h。
        let target: Double = 0 // 地平线
        let lookingForRise = e0 <= target
        var prev = start
        var prevElev = e0
        var t = start.addingTimeInterval(60)
        let end = start.addingTimeInterval(24 * 3600)

        while t <= end {
            guard let e = elevation(at: t) else { return .none }
            let crossed = lookingForRise ? (prevElev <= target && e > target)
                                         : (prevElev > target && e <= target)
            if crossed {
                // 二分细化到 ~2s
                var lo = prev, hi = t
                for _ in 0 ..< 6 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    guard let em = elevation(at: mid) else { break }
                    if lookingForRise ? (em > target) : (em <= target) {
                        hi = mid
                    } else {
                        lo = mid
                    }
                }
                return lookingForRise ? .rises(at: hi) : .sets(at: hi)
            }
            prev = t
            prevElev = e
            t = t.addingTimeInterval(60)
        }
        return .none
    }

    /// 预报的仪器读法："RISES 02:14" / "SETS 00:41"（时:分倒计时）。
    static func label(for prediction: Prediction, from now: Date = Date()) -> (label: String, value: String)? {
        switch prediction {
        case .rises(let at):
            return ("NEXT PASS", countdown(to: at, from: now))
        case .sets(let at):
            return ("SETS IN", countdown(to: at, from: now))
        case .stationary:
            return ("PASS", "STATIONARY")
        case .none:
            return nil
        }
    }

    private static func countdown(to date: Date, from now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? String(format: "T−%dH %02dM", h, m) : String(format: "T−%02dM", m)
    }
}
