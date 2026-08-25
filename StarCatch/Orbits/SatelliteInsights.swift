import Foundation
import SatelliteKit

enum InformationProvenance: String, Codable, Sendable {
    case catalog
    case computed
    case verifiedObject
    case verifiedFamily
    case classification

    func title(language: SupportedLanguage = .current) -> String {
        switch self {
        case .catalog: L10n.text("provenance.catalog", table: "SatelliteText", language: language)
        case .computed: L10n.text("provenance.computed", table: "SatelliteText", language: language)
        case .verifiedObject: L10n.text("provenance.verified_object", table: "SatelliteText", language: language)
        case .verifiedFamily: L10n.text("provenance.verified_family", table: "SatelliteText", language: language)
        case .classification: L10n.text("provenance.classification", table: "SatelliteText", language: language)
        }
    }

    var title: String { title() }
}

enum InformationScope: String, Codable, Sendable {
    case object
    case family

    func title(language: SupportedLanguage = .current) -> String {
        L10n.text(
            self == .object ? "scope.object" : "scope.family",
            table: "SatelliteText",
            language: language
        )
    }

    var title: String { title() }
}

enum OrbitMotionPresentation: String, Equatable, Sendable {
    case pass
    case lowOrbit
    case mediumOrbit
    case highElliptical
    case geostationary
}

/// A low-frequency, immutable signature derived when the insight snapshot is
/// built. SwiftUI may interpolate it at 30 fps without propagating an orbit,
/// touching the catalog, or reading a resource file.
struct SatelliteMotionSignature: Equatable, Sendable {
    let referenceDate: Date
    let phaseRadians: Double
    let angularDirection: Double
    let periodSeconds: Double
    let inclinationDegrees: Double
    let eccentricity: Double
    let rangeRateKmS: Double?
    let presentation: OrbitMotionPresentation
}

enum OrbitMotionModel {
    static func phase(
        for signature: SatelliteMotionSignature,
        at date: Date
    ) -> Double {
        guard signature.presentation != .geostationary else {
            return normalized(signature.phaseRadians)
        }
        let elapsed = date.timeIntervalSince(signature.referenceDate)
        let mean = normalized(
            signature.phaseRadians
                + signature.angularDirection * 2 * .pi * elapsed / max(60, signature.periodSeconds)
        )
        guard signature.presentation == .highElliptical,
              signature.eccentricity > 0.01
        else { return mean }

        // Solve Kepler's equation with a fixed iteration count. This is only a
        // geometric playback mapping; the factual position came from SGP4 when
        // the signature was created.
        let eccentricity = min(0.92, max(0, signature.eccentricity))
        var eccentricAnomaly = mean
        for _ in 0 ..< 5 {
            eccentricAnomaly -= (eccentricAnomaly - eccentricity * sin(eccentricAnomaly) - mean)
                / max(0.08, 1 - eccentricity * cos(eccentricAnomaly))
        }
        let numerator = sqrt(1 + eccentricity) * sin(eccentricAnomaly / 2)
        let denominator = sqrt(1 - eccentricity) * cos(eccentricAnomaly / 2)
        return normalized(2 * atan2(numerator, denominator))
    }

    static func scanProgress(
        for signature: SatelliteMotionSignature,
        at date: Date
    ) -> Double {
        let duration = max(2.4, min(8.0, signature.periodSeconds / 180))
        return positiveRemainder(
            date.timeIntervalSince(signature.referenceDate) / duration,
            divisor: 1
        )
    }

    private static func normalized(_ value: Double) -> Double {
        positiveRemainder(value, divisor: 2 * .pi)
    }

    private static func positiveRemainder(_ value: Double, divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
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
    let riseAzimuthDegrees: Double?
    let setAzimuthDegrees: Double?

    init(
        phase: Phase,
        rise: Date?,
        peak: Date?,
        set: Date?,
        maximumElevationDegrees: Double?,
        riseAzimuthDegrees: Double? = nil,
        setAzimuthDegrees: Double? = nil
    ) {
        self.phase = phase
        self.rise = rise
        self.peak = peak
        self.set = set
        self.maximumElevationDegrees = maximumElevationDegrees
        self.riseAzimuthDegrees = riseAzimuthDegrees
        self.setAzimuthDegrees = setAzimuthDegrees
    }

    var duration: TimeInterval? {
        guard let rise, let set, set > rise else { return nil }
        return set.timeIntervalSince(rise)
    }

    func progress(at date: Date) -> Double? {
        guard phase == .visible, let rise, let set, set > rise else { return nil }
        return min(1, max(0, date.timeIntervalSince(rise) / set.timeIntervalSince(rise)))
    }
}

/// A bounded, immutable view of the next day. It is produced only for the
/// deep archive and never participates in the capture/rendering hot path.
struct PassForecast: Equatable, Sendable {
    let objectID: String
    let referenceDate: Date
    let endDate: Date
    let windows: [PassWindow]
    let isStationary: Bool
    let stationaryElevationDegrees: Double?

    func defaultWindowIndex(at date: Date) -> Int? {
        if let active = windows.firstIndex(where: { window in
            guard let rise = window.rise, let set = window.set else { return false }
            return rise ... set ~= date
        }) {
            return active
        }
        return windows.firstIndex(where: { ($0.rise ?? .distantPast) >= date })
            ?? windows.indices.first
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
    let motion: SatelliteMotionSignature

    func movementLabel(language: SupportedLanguage = .current) -> String? {
        SatelliteInsightCopy.movement(snapshot: self, language: language)
    }

    var movementLabel: String? { movementLabel() }

    func headline(
        relativeTo now: Date,
        language: SupportedLanguage = .current
    ) -> String {
        SatelliteInsightCopy.headline(snapshot: self, relativeTo: now, language: language)
    }
}

enum SatelliteInsightCopy {
    static func movement(
        snapshot: SatelliteInsightSnapshot,
        language: SupportedLanguage = .current
    ) -> String? {
        guard let rate = snapshot.rangeRateKmS else { return nil }
        if abs(rate) < 0.02 {
            return L10n.text("insight.range.stable", table: "SatelliteText", language: language)
        }
        return L10n.format(
            rate < 0 ? "insight.range.approaching" : "insight.range.receding",
            table: "SatelliteText",
            language: language,
            abs(rate)
        )
    }

    static func headline(
        snapshot: SatelliteInsightSnapshot,
        relativeTo now: Date,
        language: SupportedLanguage = .current
    ) -> String {
        if let pass = snapshot.pass {
            switch pass.phase {
            case .visible:
                if let set = pass.set {
                    return L10n.format(
                        "insight.pass.visible",
                        table: "SatelliteText",
                        language: language,
                        countdown(to: set, from: now)
                    )
                }
            case .approaching:
                if let rise = pass.rise {
                    return L10n.format(
                        "insight.pass.next_rise",
                        table: "SatelliteText",
                        language: language,
                        countdown(to: rise, from: now)
                    )
                }
            case .stationary:
                return L10n.text("insight.pass.stationary", table: "SatelliteText", language: language)
            }
        }
        if let comparison = snapshot.familyComparison {
            return L10n.format(
                comparison.altitudeDeltaKm >= 0
                    ? "insight.family.higher"
                    : "insight.family.lower",
                table: "SatelliteText",
                language: language,
                comparison.family.title(language: language),
                abs(comparison.altitudeDeltaKm)
            )
        }
        if let cohort = snapshot.launchCohort, cohort.memberCount > 1 {
            return L10n.format(
                "insight.launch.cohort",
                table: "SatelliteText",
                language: language,
                cohort.ordinal,
                cohort.memberCount
            )
        }
        if snapshot.fingerprint.eccentricity >= 0.08 {
            return L10n.format(
                "insight.orbit.elliptical",
                table: "SatelliteText",
                language: language,
                snapshot.fingerprint.apogeeKm - snapshot.fingerprint.perigeeKm
            )
        }
        if let movement = movement(snapshot: snapshot, language: language) { return movement }
        if let subpoint = snapshot.subpoint {
            return L10n.format(
                "insight.subpoint",
                table: "SatelliteText",
                language: language,
                abs(subpoint.latitude), subpoint.latitude >= 0 ? "N" : "S",
                abs(subpoint.longitude), subpoint.longitude >= 0 ? "E" : "W"
            )
        }
        return L10n.format(
            "insight.orbit.period",
            table: "SatelliteText",
            language: language,
            snapshot.fingerprint.periodMinutes
        )
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

    private struct ForecastCacheKey: Hashable {
        let objectID: String
        let latitudeCentidegrees: Int
        let longitudeCentidegrees: Int
        let fifteenMinuteBucket: Int64
    }

    private let store: CatalogStore
    private var cache: [CacheKey: SatelliteInsightSnapshot] = [:]
    private var forecastCache: [ForecastCacheKey: PassForecast] = [:]

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

    func forecast(
        for objectID: String,
        observer: ObserverLocation.Coordinates,
        at date: Date
    ) async -> PassForecast? {
        let key = ForecastCacheKey(
            objectID: objectID,
            latitudeCentidegrees: Int((observer.latitude * 100).rounded()),
            longitudeCentidegrees: Int((observer.longitude * 100).rounded()),
            fifteenMinuteBucket: Int64(date.timeIntervalSince1970 / 900)
        )
        if let cached = forecastCache[key] { return cached }
        guard let satellite = store.satellites[objectID] else { return nil }
        let task = Task.detached(priority: .utility) {
            Self.computeForecast(
                objectID: objectID,
                satellite: satellite,
                observer: observer,
                start: date
            )
        }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled, let result else { return nil }
        forecastCache[key] = result
        if forecastCache.count > 24 { forecastCache = [key: result] }
        return result
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
        guard let currentPosition = try? satellite.position(julianDays: date.julianDate) else {
            return nil
        }
        let futurePosition = try? satellite.position(
            julianDays: date.addingTimeInterval(60).julianDate
        )
        let currentAngle = atan2(currentPosition.y, currentPosition.x)
        let futureAngle = futurePosition.map { atan2($0.y, $0.x) }
        let delta = futureAngle.map { angle -> Double in
            var value = angle - currentAngle
            if value > .pi { value -= 2 * .pi }
            if value < -.pi { value += 2 * .pi }
            return value
        } ?? 1
        let fingerprint = object.orbitFingerprint
        let presentation: OrbitMotionPresentation
        if pass?.phase == .stationary || fingerprint.periodMinutes > 1_250 {
            presentation = .geostationary
        } else if pass?.phase == .visible || pass?.phase == .approaching {
            presentation = .pass
        } else if fingerprint.eccentricity >= 0.08 {
            presentation = .highElliptical
        } else if fingerprint.periodMinutes < 225 {
            presentation = .lowOrbit
        } else {
            presentation = .mediumOrbit
        }
        let motion = SatelliteMotionSignature(
            referenceDate: date,
            phaseRadians: currentAngle,
            angularDirection: delta < 0 ? -1 : 1,
            periodSeconds: max(60, fingerprint.periodMinutes * 60),
            inclinationDegrees: fingerprint.inclinationDegrees,
            eccentricity: fingerprint.eccentricity,
            rangeRateKmS: rangeRate,
            presentation: presentation
        )
        return SatelliteInsightSnapshot(
            objectID: object.id,
            observationTime: date,
            fingerprint: fingerprint,
            pass: pass,
            rangeRateKmS: rangeRate,
            subpoint: subpoint,
            familyComparison: familyComparison,
            launchCohort: launchCohort,
            motion: motion
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

    nonisolated private static func computeForecast(
        objectID: String,
        satellite: Satellite,
        observer: ObserverLocation.Coordinates,
        start: Date
    ) -> PassForecast? {
        let location = LatLonAlt(
            observer.latitude,
            observer.longitude,
            observer.altitudeMeters / 1000
        )
        func elevation(_ date: Date) -> Double? {
            (try? satellite.topPosition(julianDays: date.julianDate, observer: location))?.elev
        }
        func azimuth(_ date: Date) -> Double? {
            (try? satellite.topPosition(julianDays: date.julianDate, observer: location))?.azim
        }
        guard let initialElevation = elevation(start) else { return nil }
        let end = start.addingTimeInterval(24 * 3600)
        if let laterElevation = elevation(start.addingTimeInterval(3600)),
           initialElevation > 0,
           abs(laterElevation - initialElevation) < 0.5 {
            return PassForecast(
                objectID: objectID,
                referenceDate: start,
                endDate: end,
                windows: [],
                isStationary: true,
                stationaryElevationDegrees: initialElevation
            )
        }

        let step: TimeInterval = 60
        var windows: [PassWindow] = []
        var rise: Date?
        var scan = start
        var previousElevation = initialElevation

        if initialElevation > 0 {
            var back = start
            var current = initialElevation
            let backLimit = start.addingTimeInterval(-12 * 3600)
            while back > backLimit, !Task.isCancelled {
                let candidate = back.addingTimeInterval(-step)
                guard let value = elevation(candidate) else { break }
                if value <= 0, current > 0 {
                    rise = refineCrossing(
                        satellite: satellite,
                        observer: location,
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

        while scan < end, windows.count < 8, !Task.isCancelled {
            let candidate = min(end, scan.addingTimeInterval(step))
            guard let value = elevation(candidate) else { return nil }
            if rise == nil, previousElevation <= 0, value > 0 {
                rise = refineCrossing(
                    satellite: satellite,
                    observer: location,
                    lower: scan,
                    upper: candidate,
                    rising: true
                )
            }
            if let currentRise = rise, previousElevation > 0, value <= 0 {
                let set = refineCrossing(
                    satellite: satellite,
                    observer: location,
                    lower: scan,
                    upper: candidate,
                    rising: false
                )
                let peak = findPeak(
                    satellite: satellite,
                    observer: location,
                    rise: currentRise,
                    set: set
                )
                windows.append(
                    PassWindow(
                        phase: currentRise <= start && start <= set ? .visible : .approaching,
                        rise: currentRise,
                        peak: peak.date,
                        set: set,
                        maximumElevationDegrees: peak.elevation,
                        riseAzimuthDegrees: azimuth(currentRise),
                        setAzimuthDegrees: azimuth(set)
                    )
                )
                rise = nil
            }
            scan = candidate
            previousElevation = value
        }
        guard !Task.isCancelled else { return nil }
        return PassForecast(
            objectID: objectID,
            referenceDate: start,
            endDate: end,
            windows: windows,
            isStationary: false,
            stationaryElevationDegrees: nil
        )
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
