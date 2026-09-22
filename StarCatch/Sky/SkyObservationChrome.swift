import SwiftUI
import CoreLocation
import simd

/// Pure observation policy. All time comes from the existing frame clock; no delayed
/// callbacks or additional sensor subscription survive a covered/background scene.
struct SkyDockActivity {
    private(set) var lastTouch: TimeInterval = 0
    private(set) var wakeUntil: TimeInterval = 0
    private(set) var moving = false
    private var previous: (pointing: Pointing, time: TimeInterval)?
    private var fastSince: TimeInterval?
    private var slowSince: TimeInterval?

    mutating func restart(at time: TimeInterval) {
        self = Self()
        touch(at: time, bottom: true)
    }

    mutating func touch(at time: TimeInterval, bottom: Bool) {
        lastTouch = time
        if bottom { wakeUntil = time + 3 }
    }

    mutating func sample(_ pointing: Pointing, at time: TimeInterval) {
        guard let previous else {
            self.previous = (pointing, time)
            return
        }
        let dt = time - previous.time
        guard dt >= 0.1 - 0.000_001 else { return }
        self.previous = (pointing, time)
        guard dt < 0.5 else {
            moving = false
            fastSince = nil
            slowSince = nil
            return
        }
        let speed = Self.angleDegrees(previous.pointing, pointing) / dt
        if speed > 6 {
            slowSince = nil
            if fastSince == nil { fastSince = previous.time }
            if time - (fastSince ?? time) >= 0.25 { moving = true }
        } else if speed < 2 {
            fastSince = nil
            if slowSince == nil { slowSince = previous.time }
            if time - (slowSince ?? time) >= 0.8 { moving = false }
        } else {
            fastSince = nil
            slowSince = nil
        }
    }

    func opacity(at time: TimeInterval, accessible: Bool = false) -> Double {
        if accessible || time < wakeUntil { return 1 }
        if moving { return 0.35 }
        return time - lastTouch >= 8 ? 0.72 : 1
    }

    static func angleDegrees(_ lhs: Pointing, _ rhs: Pointing) -> Double {
        acos(min(1, max(-1, simd_dot(lhs.unitVector, rhs.unitVector)))) * 180 / .pi
    }
}

/// Only opacity transitions publish. Sampling and deadline bookkeeping are silent.
@MainActor
final class SkyDockActivityController: ObservableObject {
    @Published private(set) var opacity = 1.0
    private var policy = SkyDockActivity()
    private var lastSample: TimeInterval = -.infinity

    func restart(at time: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        policy.restart(at: time)
        lastSample = -.infinity
        publish(1)
    }

    func touch(bottom: Bool, accessible: Bool) {
        let now = Date.timeIntervalSinceReferenceDate
        policy.touch(at: now, bottom: bottom)
        publish(policy.opacity(at: now, accessible: accessible))
    }

    func update(pointing: Pointing, at time: TimeInterval, accessible: Bool) {
        guard time - lastSample >= 0.1 - 0.000_001 else { return }
        lastSample = time
        policy.sample(pointing, at: time)
        publish(policy.opacity(at: time, accessible: accessible))
    }

    private func publish(_ next: Double) {
        if opacity != next { opacity = next }
    }
}

struct SkyFieldResetPolicy {
    private(set) var zoomDisplaced = false
    private(set) var directionDisplaced = false

    mutating func update(magnification: Double, manualDeviation: Double) {
        let delta = abs(magnification - 1)
        if delta > 0.08 { zoomDisplaced = true }
        else if delta <= 0.03 { zoomDisplaced = false }
        if manualDeviation > 3 { directionDisplaced = true }
        else if manualDeviation <= 1 { directionDisplaced = false }
    }

    func isAvailable(interacting: Bool) -> Bool {
        !interacting && (zoomDisplaced || directionDisplaced)
    }
}

enum SkyObservationIssue: Equatable {
    case motionUnavailable, locationDenied, locating, locationAssumed
    case locationAccuracy, directionUncalibrated
    case staleOrbit(days: Int)

    static func resolve(
        availability: PointingAvailability,
        authorization: CLAuthorizationStatus,
        locating: Bool,
        assumed: Bool,
        accuracy: Double,
        confidence: HeadingConfidence,
        orbitAge: Int
    ) -> Self? {
        if availability == .unavailable { return .motionUnavailable }
        if authorization == .denied || authorization == .restricted { return .locationDenied }
        if assumed {
            if locating { return .locating }
            return .locationAssumed
        }
        if accuracy > 2_000 { return .locationAccuracy }
        if confidence == .uncalibrated { return .directionUncalibrated }
        if orbitAge > 14 { return .staleOrbit(days: orbitAge) }
        return nil
    }

    var shortLabel: String { L10n.text("sky.issue.\(key)") }

    var fullLabel: String {
        switch self {
        case .motionUnavailable: L10n.text("sky.degraded.pointing")
        case .locationDenied: L10n.text("sky.issue.location_denied.detail")
        case .locating: L10n.text("sky.issue.locating.detail")
        case .locationAssumed: L10n.text("sky.degraded.location_assumed")
        case .locationAccuracy: L10n.text("sky.degraded.location_accuracy")
        case .directionUncalibrated: L10n.text("sky.degraded.uncalibrated")
        case .staleOrbit(let days): L10n.format("sky.degraded.orbit_age", days)
        }
    }

    private var key: String {
        switch self {
        case .motionUnavailable: "motion"
        case .locationDenied: "location_denied"
        case .locating: "locating"
        case .locationAssumed: "location_assumed"
        case .locationAccuracy: "location_accuracy"
        case .directionUncalibrated: "direction"
        case .staleOrbit: "orbit"
        }
    }
}
