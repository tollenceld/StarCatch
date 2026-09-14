import SwiftUI
import simd

/// Three real preparation milestones owned by `RootView`. The boot film reads
/// only the aggregate readiness flag; it never touches the services doing the work.
struct BootPreparationState: Equatable, Sendable {
    var catalogReady = false
    var orbitEngineReady = false
    var observationModelReady = false

    static let initial = BootPreparationState()
    static let ready = BootPreparationState(
        catalogReady: true,
        orbitEngineReady: true,
        observationModelReady: true
    )

    var isReady: Bool {
        catalogReady && orbitEngineReady && observationModelReady
    }
}

/// Pure-value clock for the deterministic orbital boot film.
struct BootOrbitalTimeline: Equatable, Sendable {
    static let minimumPresentationDuration: TimeInterval = 3.2
    static let revealDuration: TimeInterval = 0.48
    static let establishEnd: TimeInterval = 0.34
    static let sweepPeak: TimeInterval = 0.94
    static let sweepRelease: TimeInterval = 1.14
    static let settleEnd: TimeInterval = 1.92
    static let cruiseTransitionDuration: TimeInterval = 0.8

    private static let satelliteCruiseSpeed = 0.12
    private static let satelliteSweepSpeed = 1.6
    private static let earthPeakVelocityDegrees = 22.0
    private static let earthCruiseVelocityDegrees = 1.2

    let elapsed: TimeInterval
    let reducedMotion: Bool

    init(elapsed: TimeInterval, reducedMotion: Bool = false) {
        self.elapsed = max(0, elapsed)
        self.reducedMotion = reducedMotion
    }

    var revealProgress: Double {
        Self.smoothstep(elapsed / Self.revealDuration)
    }

    var sceneOpacity: Double {
        reducedMotion ? 1 : revealProgress
    }

    var globeScale: CGFloat {
        guard !reducedMotion else { return 1 }
        if elapsed <= Self.revealDuration {
            return 0.94 + CGFloat(revealProgress) * 0.072
        }
        let settling = Self.smoothstep((elapsed - Self.revealDuration) / 0.42)
        return 1.012 - CGFloat(settling) * 0.012
    }

    var trailPresence: Double {
        guard !reducedMotion else { return 0 }
        let arrival = Self.smoothstep((elapsed - 0.4) / 0.3)
        let motionEnergy = Self.smoothstep(satelliteSpeedMultiplier / 0.35)
        return arrival * (0.06 + motionEnergy * 0.74)
    }

    var brandOpacity: Double {
        let arrival = Self.smoothstep((elapsed - 1.56) / 0.56)
        return reducedMotion ? 0.18 : 0.22 * arrival
    }

    /// A single authored gesture: establish, sweep, brake to a full hold, then
    /// resume a restrained cruise only when real preparation takes longer.
    var satelliteSpeedMultiplier: Double {
        guard !reducedMotion else { return 0 }
        return Self.satelliteSweepSpeed * gestureSpeed
            + Self.satelliteCruiseSpeed * cruiseSpeed
    }

    private var gestureSpeed: Double {
        if elapsed <= Self.establishEnd { return 0 }
        if elapsed <= Self.sweepPeak {
            return Self.smootherstep(
                (elapsed - Self.establishEnd)
                    / (Self.sweepPeak - Self.establishEnd)
            )
        }
        if elapsed <= Self.sweepRelease { return 1 }
        if elapsed <= Self.settleEnd {
            return 1 - Self.smootherstep(
                (elapsed - Self.sweepRelease)
                    / (Self.settleEnd - Self.sweepRelease)
            )
        }
        return 0
    }

    private var cruiseSpeed: Double {
        Self.smootherstep(
            (elapsed - Self.minimumPresentationDuration)
                / Self.cruiseTransitionDuration
        )
    }

    /// Analytic integral of `satelliteSpeedMultiplier`. Both position and velocity
    /// are continuous across every beat, including the deliberate full stop.
    var satellitePhaseTime: TimeInterval {
        guard !reducedMotion else { return Self.satelliteSweepSpeed * Self.gestureDuration }
        return Self.satelliteSweepSpeed * gesturePhase
            + Self.satelliteCruiseSpeed * cruisePhase
    }

    private static var gestureDuration: TimeInterval {
        (sweepPeak - establishEnd) / 2 + sweepRelease - sweepPeak
            + (settleEnd - sweepRelease) / 2
    }

    private var gesturePhase: TimeInterval {
        let rise = Self.integratedRamp(
            at: elapsed,
            from: Self.establishEnd,
            to: Self.sweepPeak,
            startValue: 0,
            endValue: 1
        )
        let sweep = max(
            0,
            min(elapsed, Self.sweepRelease) - Self.sweepPeak
        )
        let braking = Self.integratedRamp(
            at: elapsed,
            from: Self.sweepRelease,
            to: Self.settleEnd,
            startValue: 1,
            endValue: 0
        )
        return rise + sweep + braking
    }

    private var cruisePhase: TimeInterval {
        let cruiseRamp = Self.integratedRamp(
            at: elapsed,
            from: Self.minimumPresentationDuration,
            to: Self.minimumPresentationDuration + Self.cruiseTransitionDuration,
            startValue: 0,
            endValue: 1
        )
        let cruise = max(
            0,
            elapsed - Self.minimumPresentationDuration - Self.cruiseTransitionDuration
        )
        return cruiseRamp + cruise
    }

    var earthAngularVelocityDegrees: Double {
        guard !reducedMotion else { return 0 }
        return Self.earthPeakVelocityDegrees * gestureSpeed
            + Self.earthCruiseVelocityDegrees * cruiseSpeed
    }

    /// Roughly twenty degrees of travel, resolving at zero so the held frame
    /// centers Shanghai. The reduced-motion frame uses that same composition.
    var earthRotationRadians: Double {
        guard !reducedMotion else { return 0 }
        return (
            Self.earthPeakVelocityDegrees * (gesturePhase - Self.gestureDuration)
                + Self.earthCruiseVelocityDegrees * cruisePhase
        ) * .pi / 180
    }

    var isCruising: Bool {
        elapsed > Self.minimumPresentationDuration + Self.cruiseTransitionDuration
    }

    private static func smoothstep(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        return value * value * (3 - 2 * value)
    }

    /// Quintic speed ramps have zero acceleration and jerk at both endpoints;
    /// their steeper middle makes the sweep distinct from the hold.
    private static func smootherstep(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * x * (10 + x * (-15 + 6 * x))
    }

    /// Exact integral of quintic smootherstep, not frame-delta accumulation.
    private static func integratedSmoothstep(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * x * x * (2.5 + x * (-3 + x))
    }

    private static func integratedRamp(
        at time: TimeInterval,
        from start: TimeInterval,
        to end: TimeInterval,
        startValue: Double,
        endValue: Double
    ) -> Double {
        guard time > start, end > start else { return 0 }
        let duration = end - start
        let progress = min(1, (time - start) / duration)
        return duration * (
            startValue * progress
                + (endValue - startValue) * integratedSmoothstep(progress)
        )
    }
}

enum BootCompletionPolicy {
    /// Nil means preparation is still in progress. Reduced Motion never adds a
    /// decorative delay; the animated film otherwise owns a 3.2-second minimum.
    nonisolated static func remainingDelay(
        elapsed: TimeInterval,
        isReady: Bool,
        reducedMotion: Bool
    ) -> TimeInterval? {
        guard isReady else { return nil }
        guard !reducedMotion else { return 0 }
        return max(0, BootOrbitalTimeline.minimumPresentationDuration - elapsed)
    }
}

/// Immutable analytic orbit set. It is intentionally unrelated to CatalogObject,
/// SatelliteKit, the real star catalogue, location, or observation time.
struct BootOrbitalScenePreset: Equatable, Sendable {
    enum Population: Hashable, Sendable {
        case constellation, equatorial, highInclination
    }

    struct Satellite: Identifiable, Equatable, Sendable {
        let id: Int
        let population: Population
        let inclination: Double
        let ascendingNode: Double
        let initialPhase: Double
        let displayRadius: Double
        let turnsPerSecond: Double
        let direction: Double
        let tintIndex: Int
        let hasTrail: Bool
        let orbitBasisX: SIMD3<Double>
        let orbitBasisY: SIMD3<Double>
    }

    static let standard = BootOrbitalScenePreset()
    static let satelliteCount = 4_600
    static let trailSatelliteCount = 24
    static let trailSampleCount = 8
    static let trailSampleInterval: TimeInterval = 0.06

    let satellites: [Satellite]

    init(
        count: Int = satelliteCount,
        trailCount: Int = trailSatelliteCount,
        seed: UInt64 = 0xB007_0B17_A15
    ) {
        var random = SplitMix64(seed: seed)
        satellites = (0 ..< max(0, count)).map { index in
            // An authored population, NOT catalog objects or physical altitudes.
            // Dominant 43°/53° shells echo broadband constellations. The 18%
            // near-equatorial belt is deliberately exaggerated for legibility;
            // it must not be presented as Starlink's actual orbital distribution.
            let bucket = (index * 37) % 100
            let population: Population
            let band: Double
            let radius: Double
            let speed: Double
            if bucket < 74 {
                population = .constellation
                band = bucket < 30 ? 43 : 53
                radius = 0.61 + Double(random.nextUnit()) * 0.055
                speed = 0.085 + Double(random.nextUnit()) * 0.055
            } else if bucket < 92 {
                population = .equatorial
                band = 6
                radius = 0.74 + Double(random.nextUnit()) * 0.08
                speed = 0.055 + Double(random.nextUnit()) * 0.025
            } else {
                population = .highInclination
                band = bucket < 96 ? 70 : 97.3
                radius = 0.65 + Double(random.nextUnit()) * 0.23
                speed = 0.065 + Double(random.nextUnit()) * 0.03
            }
            let jitter = (Double(random.nextUnit()) - 0.5)
                * (population == .equatorial ? 10 : 2)
            let inclination = (band + jitter) * .pi / 180
            // Stable orbital planes give the main shells a coherent band instead
            // of a uniformly scattered spherical halo. Precomputed once.
            let ascendingNode = population == .constellation
                ? Double((index / 100) % 24) * 2 * .pi / 24
                    + (Double(random.nextUnit()) - 0.5) * 0.025
                : Double(random.nextUnit()) * 2 * .pi
            let nodeCosine = cos(ascendingNode)
            let nodeSine = sin(ascendingNode)
            let inclinationCosine = cos(inclination)
            let inclinationSine = sin(inclination)
            return Satellite(
                id: index,
                population: population,
                inclination: inclination,
                ascendingNode: ascendingNode,
                initialPhase: Double(random.nextUnit()) * 2 * .pi,
                displayRadius: radius,
                turnsPerSecond: speed,
                // Retrograde motion is already encoded by inclination > 90°.
                direction: 1,
                tintIndex: index % 4,
                hasTrail: index < min(trailCount, count),
                orbitBasisX: SIMD3(nodeCosine, nodeSine, 0),
                orbitBasisY: SIMD3(
                    -nodeSine * inclinationCosine,
                    nodeCosine * inclinationCosine,
                    inclinationSine
                )
            )
        }
    }

    func position(
        of satellite: Satellite,
        phaseTime: TimeInterval
    ) -> SIMD3<Double> {
        let angle = satellite.initialPhase
            + satellite.direction
                * phaseTime
                * satellite.turnsPerSecond
                * 2 * .pi
        return (
            satellite.orbitBasisX * cos(angle)
                + satellite.orbitBasisY * sin(angle)
        ) * satellite.displayRadius
    }
}

/// Boot-specific camera parameters, using the global globe's exact projection.
/// Roll is applied in camera space; spin remains about the geographic polar axis.
enum BootGlobePresentation {
    static let latitude = 31.2304
    static let longitude = 121.4737
    static let rollRadians = -14.0 * Double.pi / 180

    static func orientation(rotation: Double) -> simd_quatd {
        simd_normalize(
            simd_quatd(angle: rollRadians, axis: SIMD3(0, 0, 1))
                * baseOrientation
                * simd_quatd(angle: rotation, axis: SIMD3(0, 0, 1))
        )
    }

    private static let baseOrientation = SkyOverviewView.presentationOrientation(
        latitude: latitude,
        longitude: longitude,
        siderealRadians: 0
    )
}

/// Lightweight boot-only orbital scene. The 30fps path evaluates a bounded analytic
/// preset plus the globe renderer's prepared geography cache; it performs no IO or propagation.
struct BootOrbitalFieldView: View {
    let timeline: BootOrbitalTimeline

    @ObservedObject private var coastlineStore = EarthCoastlineStore.shared
    private let dust = StarDust()
    private let preset = BootOrbitalScenePreset.standard
    private let zoom = ObservationScale.defaultOverviewZoom

    private struct Geometry {
        let center: CGPoint
        let sceneRadius: CGFloat
    }

    private typealias ProjectedPoint = SkyOverviewView.Projected3D

    private struct ProjectedSatellite {
        let satellite: BootOrbitalScenePreset.Satellite
        let projected: ProjectedPoint
    }

    var body: some View {
        Canvas(
            opaque: true,
            colorMode: .linear,
            rendersAsynchronously: false
        ) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Palette.voidBlack)
            )

            context.drawLayer { stars in
                stars.opacity = timeline.sceneOpacity
                SkyRenderer.drawDust(
                    stars,
                    dust: dust,
                    size: size,
                    transform: StarDust.skyTransform(
                        pointing: .initial,
                        canvasSize: size,
                        verticalFOV: Projection.baseVerticalFOV
                    )
                )
            }

            let geometry = Self.geometry(
                in: size,
                scale: timeline.globeScale
            )
            let viewOrientation = Self.viewOrientation(
                rotation: timeline.earthRotationRadians
            )
            let globeGeometry = SkyOverviewView.GlobeGeometry(
                center: geometry.center,
                radius: geometry.sceneRadius,
                orientation: viewOrientation
            )
            let satelliteSamples = projectedSatellites(
                geometry: geometry,
                orientation: viewOrientation
            )
            let trailPhaseTimes = historicalTrailPhaseTimes()
            context.drawLayer { ambient in
                ambient.opacity = timeline.sceneOpacity
                SkyOverviewView.drawGlobeAmbient(
                    ambient,
                    geometry: globeGeometry,
                    zoom: zoom,
                    simplified: false
                )
            }
            context.drawLayer { back in
                back.opacity = timeline.sceneOpacity
                drawSatellites(
                    back,
                    samples: satelliteSamples,
                    geometry: geometry,
                    globeGeometry: globeGeometry,
                    viewOrientation: viewOrientation,
                    trailPhaseTimes: trailPhaseTimes,
                    front: false
                )
            }
            context.drawLayer { earth in
                earth.opacity = timeline.sceneOpacity
                drawEarth(
                    earth,
                    geometry: globeGeometry
                )
            }
            context.drawLayer { front in
                front.opacity = timeline.sceneOpacity
                drawSatellites(
                    front,
                    samples: satelliteSamples,
                    geometry: geometry,
                    globeGeometry: globeGeometry,
                    viewOrientation: viewOrientation,
                    trailPhaseTimes: trailPhaseTimes,
                    front: true
                )
            }
            context.drawLayer { rim in
                rim.opacity = timeline.sceneOpacity
                SkyOverviewView.drawGlobeForegroundRim(
                    rim,
                    geometry: globeGeometry,
                    zoom: zoom,
                    presence: 1
                )
            }

            SkyRenderer.drawVignette(context, size: size)
        }
        .overlay(alignment: .bottom) {
            Text("STARCATCH")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(3.2)
                .foregroundStyle(Palette.inkMid.opacity(timeline.brandOpacity))
                .padding(.bottom, 48)
                .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
        .onAppear { coastlineStore.prepare() }
    }

    private func drawSatellites(
        _ context: GraphicsContext,
        samples: [ProjectedSatellite],
        geometry: Geometry,
        globeGeometry: SkyOverviewView.GlobeGeometry,
        viewOrientation: simd_quatd,
        trailPhaseTimes: [TimeInterval],
        front: Bool
    ) {
        if timeline.trailPresence > 0.01 {
            for sample in samples where sample.satellite.hasTrail {
                drawTrail(
                    context,
                    satellite: sample.satellite,
                    geometry: geometry,
                    viewOrientation: viewOrientation,
                    phaseTimes: trailPhaseTimes,
                    front: front
                )
            }
        }

        var highlighted = Path()
        for sample in samples {
            guard sample.satellite.hasTrail,
                  (sample.projected.depth >= 0) == front
            else { continue }
            let radius: CGFloat = front ? 0.96 : 0.52
            let rect = CGRect(
                x: sample.projected.point.x - radius,
                y: sample.projected.point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            highlighted.addEllipse(in: rect)
        }

        SkyOverviewView.drawGlobeSatelliteField(
            context,
            projected: samples.lazy.map(\.projected),
            geometry: globeGeometry,
            zoom: zoom,
            front: front,
            simplified: false,
            tint: Palette.inkHigh,
            emphasis: 1.35
        )
        context.fill(
            highlighted,
            with: .color(Palette.inkHigh.opacity(front ? 0.92 : 0.18))
        )
    }

    private func projectedSatellites(
        geometry: Geometry,
        orientation: simd_quatd
    ) -> [ProjectedSatellite] {
        var result: [ProjectedSatellite] = []
        result.reserveCapacity(preset.satellites.count)
        let phaseTime = timeline.satellitePhaseTime
        for satellite in preset.satellites {
            let projected = project(
                preset.position(
                    of: satellite,
                    phaseTime: phaseTime
                ),
                geometry: geometry,
                orientation: orientation
            )
            result.append(ProjectedSatellite(
                satellite: satellite,
                projected: projected
            ))
        }
        return result
    }

    private func drawTrail(
        _ context: GraphicsContext,
        satellite: BootOrbitalScenePreset.Satellite,
        geometry: Geometry,
        viewOrientation: simd_quatd,
        phaseTimes: [TimeInterval],
        front: Bool
    ) {
        // 与时间拨动的视觉语义一致：轨迹取真实过去时刻，而不是固定长度装饰。
        // 8 个历史相位由整帧共享，固定成本仍为 24 × 8 次轻量轨道投影。
        let projected = phaseTimes.map { phaseTime in
            project(
                preset.position(
                    of: satellite,
                    phaseTime: phaseTime
                ),
                geometry: geometry,
                orientation: viewOrientation
            )
        }
        guard projected.count > 1 else { return }
        let tint: Color = switch satellite.tintIndex {
        case 1: Palette.observationTint
        case 2: Palette.inkMid
        default: Palette.inkHigh
        }

        for index in 1 ..< projected.count {
            let start = projected[index - 1]
            let end = projected[index]
            guard (start.depth >= 0) == front,
                  (end.depth >= 0) == front
            else { continue }
            var segment = Path()
            segment.move(to: start.point)
            segment.addLine(to: end.point)
            let ageProgress = Double(index) / Double(projected.count - 1)
            let opacity = timeline.trailPresence
                * pow(ageProgress, 1.7)
                * (front ? 0.66 : 0.14)
            context.stroke(
                segment,
                with: .color(tint.opacity(opacity)),
                style: StrokeStyle(
                    lineWidth: front ? 0.78 : 0.48,
                    lineCap: .round
                )
            )
        }
    }

    private func historicalTrailPhaseTimes() -> [TimeInterval] {
        guard timeline.trailPresence > 0.01 else { return [] }
        let sampleCount = BootOrbitalScenePreset.trailSampleCount
        let sampleInterval = BootOrbitalScenePreset.trailSampleInterval
        return (0 ..< sampleCount).map { index in
            let age = Double(sampleCount - 1 - index) * sampleInterval
            return BootOrbitalTimeline(
                elapsed: max(0, timeline.elapsed - age),
                reducedMotion: timeline.reducedMotion
            ).satellitePhaseTime
        }
    }

    private func drawEarth(
        _ context: GraphicsContext,
        geometry: SkyOverviewView.GlobeGeometry
    ) {
        SkyOverviewView.drawGlobeSurface(
            context,
            geometry: geometry,
            zoom: zoom,
            siderealRadians: 0,
            landDots: coastlineStore.landDots,
            detailedCoastlines: coastlineStore.coastlines,
            fallbackCoastlines: SkyOverviewView.coastlineSamples,
            presence: 1,
            simplified: false
        )
    }

    private func project(
        _ position: SIMD3<Double>,
        geometry: Geometry,
        orientation: simd_quatd
    ) -> ProjectedPoint {
        let displayRadius = simd_length(position)
        guard displayRadius > 0 else {
            return SkyOverviewView.projectDirection(
                SIMD3(0, 0, 1),
                displayRadius: 0,
                center: geometry.center,
                radius: geometry.sceneRadius,
                orientation: orientation,
                zoom: zoom
            )
        }
        return SkyOverviewView.projectDirection(
            position / displayRadius,
            displayRadius: displayRadius,
            center: geometry.center,
            radius: geometry.sceneRadius,
            orientation: orientation,
            zoom: zoom
        )
    }

    private static func geometry(in size: CGSize, scale: CGFloat) -> Geometry {
        let horizontalRadius = (size.width - 16)
            / CGFloat(2 * SkyOverviewView.maximumOrbitDisplayRadius)
        let verticalRadius = (size.height - 96)
            / CGFloat(2 * SkyOverviewView.maximumOrbitDisplayRadius)
        let sceneRadius = max(148, min(horizontalRadius, verticalRadius)) * scale
        return Geometry(
            center: CGPoint(x: size.width / 2, y: size.height * 0.45),
            sceneRadius: sceneRadius
        )
    }

    private static func viewOrientation(rotation: Double) -> simd_quatd {
        BootGlobePresentation.orientation(rotation: rotation)
    }

}
