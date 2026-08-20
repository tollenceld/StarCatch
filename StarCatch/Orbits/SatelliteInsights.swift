import Foundation
import SatelliteKit

enum InformationProvenance: String, Codable, Sendable {
    case catalog
    case computed
    case verifiedObject
    case verifiedFamily
    case classification

    var title: String {
        switch self {
        case .catalog: "目录事实"
        case .computed: "本机推算"
        case .verifiedObject: "本星官方资料"
        case .verifiedFamily: "系列官方资料"
        case .classification: "StarCatch 分类"
        }
    }
}

enum InformationScope: String, Codable, Sendable {
    case object
    case family

    var title: String { self == .object ? "当前目标" : "系列背景" }
}

struct OrbitFingerprint: Codable, Equatable, Sendable {
    let periodMinutes: Double
    let inclinationDegrees: Double
    let eccentricity: Double
    let perigeeKm: Double
    let apogeeKm: Double

    var meanAltitudeKm: Double { (perigeeKm + apogeeKm) / 2 }
}

struct PassWindow: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case approaching
        case visible
        case stationary
    }

    let phase: Phase
    let rise: Date?
    let peak: Date?
    let set: Date?
    let maximumElevationDegrees: Double?

    func progress(at date: Date) -> Double? {
        guard phase == .visible, let rise, let set, set > rise else { return nil }
        return min(1, max(0, date.timeIntervalSince(rise) / set.timeIntervalSince(rise)))
    }
}

struct FamilyComparison: Equatable, Sendable {
    let family: CatalogFamily
    let memberCount: Int
    /// 相对系列中位数，正值代表当前节点更高 / 周期更长 / 倾角更大。
    let altitudeDeltaKm: Double
    let periodDeltaMinutes: Double
    let inclinationDeltaDegrees: Double
}

struct LaunchCohort: Equatable, Sendable {
    let launchKey: String
    let piece: String?
    let memberCount: Int
    let ordinal: Int
}

struct SatelliteInsightSnapshot: Equatable, Sendable {
    struct GroundPoint: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    let objectID: String
    let observationTime: Date
    let fingerprint: OrbitFingerprint
    let pass: PassWindow?
    let rangeRateKmS: Double?
    let subpoint: GroundPoint?
    let familyComparison: FamilyComparison?
    let launchCohort: LaunchCohort?

    var movementLabel: String? {
        guard let rangeRateKmS else { return nil }
        if abs(rangeRateKmS) < 0.02 { return "与观测者距离基本稳定" }
        return rangeRateKmS < 0
            ? String(format: "正在接近 · %.2f KM/S", abs(rangeRateKmS))
            : String(format: "正在远离 · %.2f KM/S", rangeRateKmS)
    }

    func headline(relativeTo now: Date) -> String {
        if let pass {
            switch pass.phase {
            case .visible:
                if let set = pass.set {
                    return "仍将在地平线上停留 \(Self.countdown(to: set, from: now))"
                }
            case .approaching:
                if let rise = pass.rise {
                    return "下一次进入地平线 \(Self.countdown(to: rise, from: now))"
                }
            case .stationary:
                return "相对地面方向在短时间内保持稳定"
            }
        }
        if let familyComparison {
            let direction = familyComparison.altitudeDeltaKm >= 0 ? "高" : "低"
            return String(
                format: "比 %@ 系列中位轨道约%@ %.0f KM",
                familyComparison.family.title,
                direction,
                abs(familyComparison.altitudeDeltaKm)
            )
        }
        if let launchCohort, launchCohort.memberCount > 1 {
            return "同次发射的第 \(launchCohort.ordinal) / \(launchCohort.memberCount) 个在列对象"
        }
        if fingerprint.eccentricity >= 0.08 {
            return String(format: "椭圆轨道 · 近远地点相差 %.0f KM", fingerprint.apogeeKm - fingerprint.perigeeKm)
        }
        if let movementLabel { return movementLabel }
        if let subpoint {
            return String(
                format: "星下点 · %.1f°%@  %.1f°%@",
                abs(subpoint.latitude), subpoint.latitude >= 0 ? "N" : "S",
                abs(subpoint.longitude), subpoint.longitude >= 0 ? "E" : "W"
            )
        }
        return String(format: "%.1f 分钟完成一周轨道", fingerprint.periodMinutes)
    }

    private static func countdown(to date: Date, from now: Date) -> String {
        let total = max(0, Int(date.timeIntervalSince(now)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "T−\(hours)H \(String(format: "%02d", minutes))M" : "T−\(minutes)M"
    }
}

struct CatalogInsightIndex: Sendable {
    private let familyComparisons: [String: FamilyComparison]
    private let launchCohorts: [String: LaunchCohort]

    init(objects: [CatalogObject]) {
        var comparisons: [String: FamilyComparison] = [:]
        let groupedFamilies = Dictionary(grouping: objects.compactMap { object in
            object.family.map { ($0, object) }
        }, by: \.0)
        for (family, pairs) in groupedFamilies {
            let members = pairs.map(\.1)
            let altitudes = members.map { $0.orbitFingerprint.meanAltitudeKm }.sorted()
            let periods = members.map { $0.orbitFingerprint.periodMinutes }.sorted()
            let inclinations = members.map { $0.orbitFingerprint.inclinationDegrees }.sorted()
            guard let medianAltitude = Self.median(altitudes),
                  let medianPeriod = Self.median(periods),
                  let medianInclination = Self.median(inclinations)
            else { continue }
            for member in members {
                comparisons[member.id] = FamilyComparison(
                    family: family,
                    memberCount: members.count,
                    altitudeDeltaKm: member.orbitFingerprint.meanAltitudeKm - medianAltitude,
                    periodDeltaMinutes: member.orbitFingerprint.periodMinutes - medianPeriod,
                    inclinationDeltaDegrees: member.orbitFingerprint.inclinationDegrees - medianInclination
                )
            }
        }

        var cohorts: [String: LaunchCohort] = [:]
        let groupedLaunches = Dictionary(grouping: objects.compactMap { object -> (String, CatalogObject)? in
            guard let key = object.launchKey else { return nil }
            return (key, object)
        }, by: \.0)
        for (key, pairs) in groupedLaunches {
            let members = pairs.map(\.1).sorted { lhs, rhs in
                if lhs.cosparId == rhs.cosparId { return lhs.noradId < rhs.noradId }
                return lhs.cosparId < rhs.cosparId
            }
            for (index, member) in members.enumerated() {
                cohorts[member.id] = LaunchCohort(
                    launchKey: key,
                    piece: member.launchPiece,
                    memberCount: members.count,
                    ordinal: index + 1
                )
            }
        }
        familyComparisons = comparisons
        launchCohorts = cohorts
    }

    func familyComparison(for objectID: String) -> FamilyComparison? {
        familyComparisons[objectID]
    }

    func launchCohort(for objectID: String) -> LaunchCohort? {
        launchCohorts[objectID]
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}

/// 只为当前感应目标生成低频阅读信息。全目录 Canvas 从不观察这个对象。
@MainActor
final class SatelliteInsightEngine {
    private struct CacheKey: Hashable {
        let objectID: String
        let latitudeCentidegrees: Int
        let longitudeCentidegrees: Int
        let fiveMinuteBucket: Int64
    }

    private let store: CatalogStore
    private var cache: [CacheKey: SatelliteInsightSnapshot] = [:]

    init(store: CatalogStore) {
        self.store = store
    }

    func insight(
        for objectID: String,
        observer: ObserverLocation.Coordinates,
        at date: Date
    ) async -> SatelliteInsightSnapshot? {
        let key = CacheKey(
            objectID: objectID,
            latitudeCentidegrees: Int((observer.latitude * 100).rounded()),
            longitudeCentidegrees: Int((observer.longitude * 100).rounded()),
            fiveMinuteBucket: Int64(date.timeIntervalSince1970 / 300)
        )
        if let cached = cache[key] { return cached }
        guard let object = store.objectsByID[objectID],
              let satellite = store.satellites[objectID]
        else { return nil }
        let familyComparison = store.insightIndex.familyComparison(for: objectID)
        let launchCohort = store.insightIndex.launchCohort(for: objectID)
        let task = Task.detached(priority: .utility) {
            Self.compute(
                object: object,
                satellite: satellite,
                observer: observer,
                date: date,
                familyComparison: familyComparison,
                launchCohort: launchCohort
            )
        }
        let snapshot = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled, let snapshot else { return nil }
        cache[key] = snapshot
        if cache.count > 48 { cache = [key: snapshot] }
        return snapshot
    }

    func prewarm(
        objectID: String,
        observer: ObserverLocation.Coordinates,
        at date: Date
    ) async {
        _ = await insight(for: objectID, observer: observer, at: date)
    }

    nonisolated private static func compute(
        object: CatalogObject,
        satellite: Satellite,
        observer: ObserverLocation.Coordinates,
        date: Date,
        familyComparison: FamilyComparison?,
        launchCohort: LaunchCohort?
    ) -> SatelliteInsightSnapshot? {
        let location = LatLonAlt(
            observer.latitude,
            observer.longitude,
            observer.altitudeMeters / 1000
        )
        let interval: TimeInterval = 8
        let before = try? satellite.topPosition(
            julianDays: date.addingTimeInterval(-interval).julianDate,
            observer: location
        )
        let after = try? satellite.topPosition(
            julianDays: date.addingTimeInterval(interval).julianDate,
            observer: location
        )
        let rangeRate = before.flatMap { first in
            after.map { ($0.dist - first.dist) / (2 * interval) }
        }
        let subpoint = (try? satellite.position(julianDays: date.julianDate)).map { position in
            let geo = eci2geo(julianDays: date.julianDate, celestial: position)
            let longitude = geo.lon > 180 ? geo.lon - 360 : geo.lon
            return SatelliteInsightSnapshot.GroundPoint(
                latitude: geo.lat,
                longitude: longitude
            )
        }
        let pass = computePassWindow(satellite: satellite, observer: location, start: date)
        return SatelliteInsightSnapshot(
            objectID: object.id,
            observationTime: date,
            fingerprint: object.orbitFingerprint,
            pass: pass,
            rangeRateKmS: rangeRate,
            subpoint: subpoint,
            familyComparison: familyComparison,
            launchCohort: launchCohort
        )
    }

    nonisolated private static func computePassWindow(
        satellite: Satellite,
        observer: LatLonAlt,
        start: Date
    ) -> PassWindow? {
        func elevation(_ date: Date) -> Double? {
            (try? satellite.topPosition(julianDays: date.julianDate, observer: observer))?.elev
        }
        guard let initial = elevation(start) else { return nil }
        if let later = elevation(start.addingTimeInterval(3600)),
           initial > 0, abs(later - initial) < 0.5 {
            return PassWindow(
                phase: .stationary,
                rise: nil,
                peak: nil,
                set: nil,
                maximumElevationDegrees: initial
            )
        }

        let step: TimeInterval = 60
        let limit = start.addingTimeInterval(24 * 3600)
        var rise: Date?
        var scan = start
        var previousElevation = initial

        if initial > 0 {
            var back = start
            var current = initial
            let backLimit = start.addingTimeInterval(-12 * 3600)
            while back > backLimit, !Task.isCancelled {
                let candidate = back.addingTimeInterval(-step)
                guard let value = elevation(candidate) else { break }
                if value <= 0, current > 0 {
                    rise = refineCrossing(
                        satellite: satellite,
                        observer: observer,
                        lower: candidate,
                        upper: back,
                        rising: true
                    )
                    break
                }
                back = candidate
                current = value
            }
        }

        while scan < limit, !Task.isCancelled {
            let candidate = scan.addingTimeInterval(step)
            guard let value = elevation(candidate) else { return nil }
            if rise == nil, previousElevation <= 0, value > 0 {
                rise = refineCrossing(
                    satellite: satellite,
                    observer: observer,
                    lower: scan,
                    upper: candidate,
                    rising: true
                )
            }
            if let rise, previousElevation > 0, value <= 0 {
                let set = refineCrossing(
                    satellite: satellite,
                    observer: observer,
                    lower: scan,
                    upper: candidate,
                    rising: false
                )
                let peak = findPeak(
                    satellite: satellite,
                    observer: observer,
                    rise: rise,
                    set: set
                )
                return PassWindow(
                    phase: initial > 0 ? .visible : .approaching,
                    rise: rise,
                    peak: peak.date,
                    set: set,
                    maximumElevationDegrees: peak.elevation
                )
            }
            scan = candidate
            previousElevation = value
        }
        return nil
    }

    nonisolated private static func refineCrossing(
        satellite: Satellite,
        observer: LatLonAlt,
        lower: Date,
        upper: Date,
        rising: Bool
    ) -> Date {
        var low = lower
        var high = upper
        for _ in 0 ..< 7 {
            let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            let elevation = (try? satellite.topPosition(
                julianDays: middle.julianDate,
                observer: observer
            ))?.elev ?? 0
            if rising ? elevation > 0 : elevation <= 0 {
                high = middle
            } else {
                low = middle
            }
        }
        return high
    }

    nonisolated private static func findPeak(
        satellite: Satellite,
        observer: LatLonAlt,
        rise: Date,
        set: Date
    ) -> (date: Date?, elevation: Double?) {
        guard set > rise else { return (nil, nil) }
        var bestDate = rise
        var bestElevation = -Double.infinity
        let samples = 48
        for index in 0 ... samples {
            if Task.isCancelled { return (nil, nil) }
            let date = rise.addingTimeInterval(
                set.timeIntervalSince(rise) * Double(index) / Double(samples)
            )
            if let elevation = try? satellite.topPosition(
                julianDays: date.julianDate,
                observer: observer
            ).elev, elevation > bestElevation {
                bestDate = date
                bestElevation = elevation
            }
        }
        return bestElevation.isFinite ? (bestDate, bestElevation) : (nil, nil)
    }
}
