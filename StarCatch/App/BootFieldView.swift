import Foundation

/// Launch readiness is intentionally independent of a fixed-length animation.
/// The catalog and first usable orbit frame decide when the sky may appear; a
/// short minimum dwell only prevents a one-frame flash on fast devices.
struct ObservationEstablishment {
    enum Phase: Equatable {
        case preparing
        case waitingForFrame
        case waitingForLocation
        case live
        case failed
    }

    static let minimumDwell: TimeInterval = 0.55
    static let reducedMotionDwell: TimeInterval = 0.14
    static let frameSettle: TimeInterval = 0.08
    static let locationGrace: TimeInterval = 0.45
    static let frameTimeout: TimeInterval = 8

    private(set) var elapsed: TimeInterval = 0
    private(set) var phase: Phase = .preparing
    private var lastTick: TimeInterval?
    private var frameReadySince: TimeInterval?
    private var locationWaitStartedAt: TimeInterval?

    var isComplete: Bool { phase == .live || phase == .failed }

    mutating func pause() { lastTick = nil }

    mutating func advance(
        at uptime: TimeInterval,
        active: Bool,
        sessionReady: Bool,
        frameReady: Bool,
        locating: Bool,
        assumedLocation: Bool,
        failed: Bool = false,
        reducedMotion: Bool = false
    ) {
        guard active, !isComplete else {
            lastTick = nil
            return
        }
        if let lastTick { elapsed += max(0, uptime - lastTick) }
        lastTick = uptime

        if failed {
            phase = .failed
            return
        }
        guard sessionReady else {
            frameReadySince = nil
            locationWaitStartedAt = nil
            phase = .preparing
            return
        }
        guard frameReady else {
            frameReadySince = nil
            locationWaitStartedAt = nil
            phase = elapsed >= Self.frameTimeout ? .live : .waitingForFrame
            return
        }

        if frameReadySince == nil { frameReadySince = elapsed }
        if locating && assumedLocation {
            if locationWaitStartedAt == nil { locationWaitStartedAt = elapsed }
            if elapsed - (locationWaitStartedAt ?? elapsed) < Self.locationGrace {
                phase = .waitingForLocation
                return
            }
        } else {
            locationWaitStartedAt = nil
        }

        let dwell = reducedMotion ? Self.reducedMotionDwell : Self.minimumDwell
        if elapsed >= dwell,
           elapsed - (frameReadySince ?? elapsed) >= Self.frameSettle {
            phase = .live
        } else {
            phase = .preparing
        }
    }
}
