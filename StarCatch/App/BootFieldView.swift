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
    static let revealDuration: TimeInterval = 0.35
    static let accelerationEnd: TimeInterval = 2.65
    static let cruiseTransitionDuration: TimeInterval = 0.55

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
        reducedMotion ? 1 : 0.82 + CGFloat(revealProgress) * 0.18
    }

    var trailPresence: Double {
        guard !reducedMotion else { return 0 }
        return Self.smoothstep((elapsed - 0.48) / 0.72)
    }

    var brandOpacity: Double {
        let arrival = Self.smoothstep((elapsed - 0.45) / 0.6)
        let quieting = Self.smoothstep(
            (elapsed - Self.accelerationEnd)
                / (Self.minimumPresentationDuration - Self.accelerationEnd)
        )
        return reducedMotion ? 0.2 : (0.28 - quieting * 0.12) * arrival
    }

    /// Multiplier applied to each preset satellite's individual turns-per-second.
    var satelliteSpeedMultiplier: Double {
        guard !reducedMotion else { return 0 }
        if elapsed <= Self.revealDuration { return 0.25 }
        if elapsed <= Self.accelerationEnd {
            let progress = (elapsed - Self.revealDuration)
                / (Self.accelerationEnd - Self.revealDuration)
            return 0.25 + progress * 0.75
        }
        if elapsed <= Self.minimumPresentationDuration { return 1 }
        let slowing = min(
            1,
            (elapsed - Self.minimumPresentationDuration)
                / Self.cruiseTransitionDuration
        )
        return 1 - slowing * 0.56
    }

    /// Integrated speed multiplier. Positions remain continuous when the film
    /// leaves its high-speed ending and settles into an indefinite slow cruise.
    var satellitePhaseTime: TimeInterval {
        guard !reducedMotion else { return 1.08 }
        let revealEnd = Self.revealDuration * 0.25
        guard elapsed > Self.revealDuration else { return elapsed * 0.25 }

        let accelerationDuration = Self.accelerationEnd - Self.revealDuration
        let accelerationSlope = 0.75 / accelerationDuration
        let accelerated = revealEnd
            + 0.25 * accelerationDuration
            + 0.5 * accelerationSlope * accelerationDuration * accelerationDuration
        if elapsed <= Self.accelerationEnd {
            let delta = elapsed - Self.revealDuration
            return revealEnd + 0.25 * delta + 0.5 * accelerationSlope * delta * delta
        }

        let highSpeedDuration = Self.minimumPresentationDuration - Self.accelerationEnd
        let cinematicEnd = accelerated + highSpeedDuration
        if elapsed <= Self.minimumPresentationDuration {
            return accelerated + elapsed - Self.accelerationEnd
        }

        let slowdownDelta = min(
            Self.cruiseTransitionDuration,
            elapsed - Self.minimumPresentationDuration
        )
        let slowdownSlope = -0.56 / Self.cruiseTransitionDuration
        let slowdownTravel = slowdownDelta
            + 0.5 * slowdownSlope * slowdownDelta * slowdownDelta
        let cruiseDelta = max(
            0,
            elapsed - Self.minimumPresentationDuration - Self.cruiseTransitionDuration
        )
        return cinematicEnd + slowdownTravel + cruiseDelta * 0.44
    }

    var earthAngularVelocityDegrees: Double {
        reducedMotion ? 0 : 360 / OverviewShowcaseRotation.revolutionDuration
    }

    /// 与全局页的空闲展示旋转共享 180 秒一周的克制节奏。点阵大陆让短时间内的
    /// 细微转动仍然可读，同时慢加载无需在电影结束处变速或重置相位。
    var earthRotationRadians: Double {
        guard !reducedMotion else { return 0.32 }
        return elapsed * 2 * .pi / OverviewShowcaseRotation.revolutionDuration
    }

    var isCruising: Bool {
        elapsed > Self.minimumPresentationDuration + Self.cruiseTransitionDuration
    }

    private static func smoothstep(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        return value * value * (3 - 2 * value)
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
    struct Satellite: Identifiable, Equatable, Sendable {
        let id: Int
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

    let satellites: [Satellite]

    init(
        count: Int = satelliteCount,
        trailCount: Int = trailSatelliteCount,
        seed: UInt64 = 0xB007_0B17_A15
    ) {
        var random = SplitMix64(seed: seed)
        let inclinationBands = [18.0, 42.0, 53.0, 63.4, 82.0, 98.0]
        satellites = (0 ..< max(0, count)).map { index in
            let band = inclinationBands[index % inclinationBands.count]
            let jitter = (Double(random.nextUnit()) - 0.5) * 8
            let inclination = (band + jitter) * .pi / 180
            let ascendingNode = Double(random.nextUnit()) * 2 * .pi
            let nodeCosine = cos(ascendingNode)
            let nodeSine = sin(ascendingNode)
            let inclinationCosine = cos(inclination)
            let inclinationSine = sin(inclination)
            return Satellite(
                id: index,
                inclination: inclination,
                ascendingNode: ascendingNode,
                initialPhase: Double(random.nextUnit()) * 2 * .pi,
                displayRadius: 0.61 + Double(random.nextUnit()) * 0.27,
                turnsPerSecond: 0.18 + Double(random.nextUnit()) * 0.14,
                direction: index.isMultiple(of: 7) ? -1 : 1,
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
        front: Bool
    ) {
        if timeline.trailPresence > 0.01 {
            for sample in samples where sample.satellite.hasTrail {
                drawTrail(
                    context,
                    satellite: sample.satellite,
                    geometry: geometry,
                    viewOrientation: viewOrientation,
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
            simplified: false
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
        for satellite in preset.satellites {
            let projected = project(
                preset.position(
                    of: satellite,
                    phaseTime: timeline.satellitePhaseTime
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
        front: Bool
    ) {
        let sampleCount = BootOrbitalScenePreset.trailSampleCount
        // 与时间拨动的视觉语义一致：轨迹必须能明确说明运动方向，而不是只在
        // 星核后留下几像素装饰。固定解析采样仍保持 24 × 8 的有界成本。
        let sampleInterval = 0.028
        let projected = (0 ..< sampleCount).map { index in
            let age = Double(sampleCount - 1 - index) * sampleInterval
            return project(
                preset.position(
                    of: satellite,
                    phaseTime: timeline.satellitePhaseTime - age
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

    private static let baseViewOrientation = SkyOverviewView.presentationOrientation(
        latitude: 0,
        longitude: 121.4737,
        siderealRadians: 0
    )

    private static func viewOrientation(rotation: Double) -> simd_quatd {
        simd_normalize(
            baseViewOrientation
                * simd_quatd(angle: rotation, axis: SIMD3(0, 0, 1))
        )
    }

}
