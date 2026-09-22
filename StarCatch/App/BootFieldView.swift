import SwiftUI
import simd

/// Root-owned presentation state. Business readiness remains in SkySession.
struct ObservationEstablishment {
    enum Phase: Equatable { case signal, earth, network, observer, descent, live, failed }
    private(set) var elapsed = 0.0
    private(set) var networkStartedAt: Double?
    private(set) var observerStartedAt: Double?
    private(set) var observer: ObserverLocation.Coordinates?
    private(set) var phase: Phase = .signal
    private(set) var confirmed = false
    private var lastTick: Double?
    private var locationWaitStartedAt: Double?
    private(set) var reducedMotion = false

    var isComplete: Bool { phase == .live || phase == .failed }
    var localProgress: Double {
        guard let observerStartedAt else { return isComplete ? 1 : 0 }
        return min(1, max(0, (elapsed - observerStartedAt - (reducedMotion ? 0 : 0.25)) / (reducedMotion ? 0.16 : 1.05)))
    }
    var chromePresence: Double { isComplete ? 1 : ObservationSceneMath.ease((localProgress - 0.8) / 0.2) }
    mutating func pause() { lastTick = nil }

    /// Returns one confirmation event, never a Canvas side effect.
    mutating func advance(at uptime: Double, active: Bool, sessionReady: Bool,
                          frameReady: Bool, locating: Bool, coordinates: ObserverLocation.Coordinates,
                          failed: Bool = false, reduced: Bool = false) -> Bool {
        guard active, !isComplete else { lastTick = nil; return false }
        if let lastTick { elapsed += max(0, uptime - lastTick) }
        lastTick = uptime
        reducedMotion = reduced
        if failed { phase = .failed; return false }
        if sessionReady, elapsed >= 8, !frameReady { phase = .live; return false }
        if frameReady, networkStartedAt == nil { networkStartedAt = max(reduced ? 0 : 0.7, elapsed) }
        let networkFinished = networkStartedAt.map { elapsed >= $0 + (reduced ? 0 : 0.6) } ?? false
        if networkFinished, frameReady, observerStartedAt == nil {
            if locating, coordinates.assumed {
                if locationWaitStartedAt == nil { locationWaitStartedAt = elapsed }
                if elapsed - (locationWaitStartedAt ?? elapsed) < 0.8 { phase = .network; return false }
            }
            observer = coordinates
            observerStartedAt = elapsed
        }
        if let observerStartedAt {
            if localProgress >= 1 { phase = .live }
            else { phase = elapsed < observerStartedAt + 0.25 && !reduced ? .observer : .descent }
            if !confirmed {
                confirmed = true
                return observer?.assumed == false
            }
        } else if elapsed < 0.15, !reduced { phase = .signal }
        else if elapsed < 0.7, !reduced { phase = .earth }
        else { phase = .network }
        return false
    }

    var reveal: ObservationSceneReveal {
        let ease = ObservationSceneMath.ease
        let network = networkStartedAt.map { min(1, max(0, (elapsed - $0) / 0.6)) } ?? 0
        let lock = observerStartedAt.map { ease((elapsed - $0) / 0.25) } ?? 0
        let waiting = max(0, elapsed - 1.3)
        let breath = 1 - 0.025 * ease(waiting) * (1 - cos(waiting * .pi / 2)) * (1 - lock)
        if reducedMotion { return ObservationSceneReveal(signal: 0, limb: 1, grid: 1, land: 1,
            orbits: 1, satellites: networkStartedAt == nil ? 0 : 1, observer: observer == nil ? 0 : 1) }
        return ObservationSceneReveal(
            signal: ease(elapsed / 0.12) * (1 - ease((elapsed - 0.16) / 0.28)),
            limb: ease((elapsed - 0.12) / 0.32) * breath, grid: ease((elapsed - 0.28) / 0.32),
            land: ease((elapsed - 0.4) / 0.3), orbits: ease((elapsed - 0.65) / 0.55),
            satellites: network, observer: lock, confirmation: lock)
    }

    var rotation: Double {
        guard !reducedMotion else { return 0 }
        let start = observerStartedAt ?? elapsed
        let brake = min(1, max(0, (elapsed - start) / 0.25))
        let integral = brake - pow(brake, 4) * (2.5 - 3 * brake + brake * brake)
        return (start + integral * 0.25) * .pi / 90
    }
}

struct ObservationEstablishmentField: View {
    let establishment: ObservationEstablishment
    let frame: ObservationSceneFrame
    @ObservedObject private var coastlines = EarthCoastlineStore.shared

    var body: some View {
        Canvas(opaque: true, colorMode: .linear) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.voidBlack))
            let orientation = SkyOverviewView.presentationOrientation(
                latitude: ObserverLocation.fallback.latitude, longitude: ObserverLocation.fallback.longitude,
                siderealRadians: ObservationSceneCoordinates.sidereal(at: frame.observation))
            let base = SkyOverviewView.globeGeometry(in: size)
            let orbitOrientation = simd_quatd(angle: -14 * .pi / 180, axis: SIMD3(0, 0, 1)) * orientation
                * simd_quatd(angle: establishment.rotation, axis: SIMD3(0, 0, 1))
            let focus = SkyOverviewView.presentationOrientation(
                latitude: frame.observer.latitude, longitude: frame.observer.longitude,
                siderealRadians: ObservationSceneCoordinates.sidereal(at: frame.observation))
            let alignment = establishment.observerStartedAt.map {
                ObservationSceneMath.ease((establishment.elapsed - $0) / 0.25)
            } ?? 0
            let geometry = SkyOverviewView.GlobeGeometry(center: base.center, radius: base.radius,
                orientation: simd_slerp(orbitOrientation, focus, alignment))
            let camera = ObservationCameraState(size: size, geometry: geometry,
                zoom: ObservationScale.defaultOverviewZoom, localProgress: establishment.reducedMotion ? 0 : establishment.localProgress,
                observer: frame.observer, pointing: frame.pointing, observation: frame.observation)
            ObservationSceneRenderer.drawBackground(context, size: size, pointing: frame.pointing,
                presence: ObservationSceneMath.ease((establishment.elapsed - 0.4) / 0.9))
            ObservationSceneRenderer.draw(context, camera: camera, frame: frame,
                reveal: establishment.reveal, landStore: coastlines)
        }
        .onAppear { coastlines.prepare() }
        .accessibilityHidden(true)
    }
}
