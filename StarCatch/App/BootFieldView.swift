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
        guard !reducedMotion else { return 0 }
        if elapsed <= Self.revealDuration { return 4 }
        if elapsed <= Self.accelerationEnd {
            let progress = (elapsed - Self.revealDuration)
                / (Self.accelerationEnd - Self.revealDuration)
            return 4 + progress * 24
        }
        if elapsed <= Self.minimumPresentationDuration { return 28 }
        let slowing = min(
            1,
            (elapsed - Self.minimumPresentationDuration)
                / Self.cruiseTransitionDuration
        )
        return 28 - slowing * 23
    }

    /// About 53° during the 3.2-second film, followed by a continuous 5°/s cruise.
    var earthRotationRadians: Double {
        guard !reducedMotion else { return 0.32 }
        let initial = -0.5
        let revealTravel = min(elapsed, Self.revealDuration) * 4
        guard elapsed > Self.revealDuration else {
            return initial + revealTravel * .pi / 180
        }

        let accelerationDuration = Self.accelerationEnd - Self.revealDuration
        let accelerationSlope = 24 / accelerationDuration
        let accelerationDelta = min(
            accelerationDuration,
            elapsed - Self.revealDuration
        )
        var degrees = revealTravel
            + 4 * accelerationDelta
            + 0.5 * accelerationSlope * accelerationDelta * accelerationDelta
        guard elapsed > Self.accelerationEnd else {
            return initial + degrees * .pi / 180
        }

        let highSpeedDelta = min(
            Self.minimumPresentationDuration - Self.accelerationEnd,
            elapsed - Self.accelerationEnd
        )
        degrees += highSpeedDelta * 28
        guard elapsed > Self.minimumPresentationDuration else {
            return initial + degrees * .pi / 180
        }

        let slowdownDelta = min(
            Self.cruiseTransitionDuration,
            elapsed - Self.minimumPresentationDuration
        )
        let slowdownSlope = -23 / Self.cruiseTransitionDuration
        degrees += 28 * slowdownDelta
            + 0.5 * slowdownSlope * slowdownDelta * slowdownDelta
        degrees += max(
            0,
            elapsed - Self.minimumPresentationDuration - Self.cruiseTransitionDuration
        ) * 5
        return initial + degrees * .pi / 180
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
                displayRadius: 0.68 + Double(random.nextUnit()) * 0.27,
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

/// Lightweight boot-only globe. The 30fps path evaluates a bounded analytic
/// preset and compiled coordinate constants; it performs no IO or propagation.
struct BootOrbitalFieldView: View {
    let timeline: BootOrbitalTimeline

    private let dust = StarDust()
    private let preset = BootOrbitalScenePreset.standard

    private struct Geometry {
        let center: CGPoint
        let sceneRadius: CGFloat
        let earthRadius: CGFloat
    }

    private struct ProjectedPoint {
        let point: CGPoint
        let depth: Double
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
            let viewOrientation = Self.viewOrientation
            context.drawLayer { back in
                back.opacity = timeline.sceneOpacity
                drawSatellites(
                    back,
                    geometry: geometry,
                    viewOrientation: viewOrientation,
                    front: false
                )
            }
            context.drawLayer { earth in
                earth.opacity = timeline.sceneOpacity
                drawEarth(
                    earth,
                    geometry: geometry,
                    viewOrientation: viewOrientation
                )
            }
            context.drawLayer { front in
                front.opacity = timeline.sceneOpacity
                drawSatellites(
                    front,
                    geometry: geometry,
                    viewOrientation: viewOrientation,
                    front: true
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
    }

    private func drawSatellites(
        _ context: GraphicsContext,
        geometry: Geometry,
        viewOrientation: simd_quatd,
        front: Bool
    ) {
        if timeline.trailPresence > 0.01 {
            for satellite in preset.satellites where satellite.hasTrail {
                drawTrail(
                    context,
                    satellite: satellite,
                    geometry: geometry,
                    viewOrientation: viewOrientation,
                    front: front
                )
            }
        }

        var ordinary = Path()
        var cool = Path()
        var pale = Path()
        var highlighted = Path()
        for satellite in preset.satellites {
            let projected = project(
                preset.position(
                    of: satellite,
                    phaseTime: timeline.satellitePhaseTime
                ),
                geometry: geometry,
                orientation: viewOrientation
            )
            guard (projected.depth >= 0) == front else { continue }
            let radius: CGFloat = satellite.hasTrail ? 0.96 : (front ? 0.43 : 0.32)
            let rect = CGRect(
                x: projected.point.x - radius,
                y: projected.point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            if satellite.hasTrail {
                highlighted.addEllipse(in: rect)
            } else {
                switch satellite.tintIndex {
                case 1: cool.addEllipse(in: rect)
                case 2: pale.addEllipse(in: rect)
                default: ordinary.addEllipse(in: rect)
                }
            }
        }

        let depthOpacity = front ? 1.0 : 0.22
        context.fill(
            ordinary,
            with: .color(Palette.inkHigh.opacity(0.44 * depthOpacity))
        )
        context.fill(
            cool,
            with: .color(Palette.observationTint.opacity(0.46 * depthOpacity))
        )
        context.fill(
            pale,
            with: .color(Palette.inkMid.opacity(0.48 * depthOpacity))
        )
        context.fill(
            highlighted,
            with: .color(Palette.inkHigh.opacity(0.92 * depthOpacity))
        )
    }

    private func drawTrail(
        _ context: GraphicsContext,
        satellite: BootOrbitalScenePreset.Satellite,
        geometry: Geometry,
        viewOrientation: simd_quatd,
        front: Bool
    ) {
        let sampleCount = BootOrbitalScenePreset.trailSampleCount
        let sampleInterval = 0.012
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
                * (front ? 0.52 : 0.1)
            context.stroke(
                segment,
                with: .color(tint.opacity(opacity)),
                style: StrokeStyle(
                    lineWidth: front ? 0.72 : 0.46,
                    lineCap: .round
                )
            )
        }
    }

    private func drawEarth(
        _ context: GraphicsContext,
        geometry: Geometry,
        viewOrientation: simd_quatd
    ) {
        let earthRect = CGRect(
            x: geometry.center.x - geometry.earthRadius,
            y: geometry.center.y - geometry.earthRadius,
            width: geometry.earthRadius * 2,
            height: geometry.earthRadius * 2
        )
        let earth = Path(ellipseIn: earthRect)

        // Atmosphere without blur: three restrained shells keep the render path cheap.
        context.stroke(
            Path(ellipseIn: earthRect.insetBy(dx: -3, dy: -3)),
            with: .color(Palette.observationTint.opacity(0.055)),
            style: StrokeStyle(lineWidth: 3)
        )
        context.stroke(
            Path(ellipseIn: earthRect.insetBy(dx: -1.35, dy: -1.35)),
            with: .color(Palette.observationTint.opacity(0.16)),
            style: StrokeStyle(lineWidth: 0.5)
        )

        context.fill(
            earth,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Palette.observationTint.opacity(0.105), location: 0),
                    .init(color: Palette.dust.opacity(0.42), location: 0.42),
                    .init(color: Palette.voidBlack.opacity(0.96), location: 1),
                ]),
                center: CGPoint(
                    x: earthRect.minX + geometry.earthRadius * 0.64,
                    y: earthRect.minY + geometry.earthRadius * 0.56
                ),
                startRadius: 0,
                endRadius: geometry.earthRadius * 1.4
            )
        )

        context.drawLayer { night in
            night.clip(to: earth)
            night.fill(
                earth,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0.24),
                        .init(color: Palette.voidBlack.opacity(0.08), location: 0.52),
                        .init(color: Palette.voidBlack.opacity(0.5), location: 1),
                    ]),
                    startPoint: CGPoint(x: earthRect.minX, y: earthRect.minY),
                    endPoint: CGPoint(x: earthRect.maxX, y: earthRect.maxY)
                )
            )
        }

        let earthOrientation = simd_normalize(
            viewOrientation
                * simd_quatd(
                    angle: timeline.earthRotationRadians,
                    axis: SIMD3(0, 1, 0)
                )
        )
        drawEarthGrid(
            context,
            geometry: geometry,
            orientation: earthOrientation
        )
        drawCoastlines(
            context,
            geometry: geometry,
            orientation: earthOrientation
        )

        context.stroke(
            earth,
            with: .color(Palette.inkMid.opacity(0.56)),
            style: StrokeStyle(lineWidth: 0.8)
        )
        var illuminatedLimb = Path()
        illuminatedLimb.addArc(
            center: geometry.center,
            radius: geometry.earthRadius - 0.4,
            startAngle: .degrees(142),
            endAngle: .degrees(303),
            clockwise: false
        )
        context.stroke(
            illuminatedLimb,
            with: .color(Palette.inkHigh.opacity(0.25)),
            style: StrokeStyle(lineWidth: 0.72, lineCap: .round)
        )
    }

    private func drawEarthGrid(
        _ context: GraphicsContext,
        geometry: Geometry,
        orientation: simd_quatd
    ) {
        let sampleStep = Double.pi / 28
        for latitudeDegrees in stride(from: -60.0, through: 60.0, by: 30.0) {
            let latitude = latitudeDegrees * .pi / 180
            let points = stride(
                from: 0.0,
                through: Double.pi * 2,
                by: sampleStep
            ).map { longitude in
                projectSurface(
                    SIMD3(
                        cos(latitude) * cos(longitude),
                        cos(latitude) * sin(longitude),
                        sin(latitude)
                    ),
                    geometry: geometry,
                    orientation: orientation
                )
            }
            strokeSurface(
                context,
                points: points,
                color: Palette.inkLow.opacity(0.1)
            )
        }
        for longitude in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 6) {
            let points = stride(
                from: -Double.pi / 2,
                through: Double.pi / 2,
                by: sampleStep
            ).map { latitude in
                projectSurface(
                    SIMD3(
                        cos(latitude) * cos(longitude),
                        cos(latitude) * sin(longitude),
                        sin(latitude)
                    ),
                    geometry: geometry,
                    orientation: orientation
                )
            }
            strokeSurface(
                context,
                points: points,
                color: Palette.inkLow.opacity(0.1)
            )
        }
    }

    private func drawCoastlines(
        _ context: GraphicsContext,
        geometry: Geometry,
        orientation: simd_quatd
    ) {
        for coastline in SkyOverviewView.coastlineSamples {
            let points = stride(
                from: 0,
                to: max(0, coastline.count - 1),
                by: 2
            ).map { index in
                let latitude = Double(coastline[index]) * .pi / 180
                let longitude = Double(coastline[index + 1]) * .pi / 180
                return projectSurface(
                    SIMD3(
                        cos(latitude) * cos(longitude),
                        cos(latitude) * sin(longitude),
                        sin(latitude)
                    ),
                    geometry: geometry,
                    orientation: orientation
                )
            }
            strokeSurface(
                context,
                points: points,
                color: Palette.voidBlack.opacity(0.48),
                lineWidth: 1.15
            )
            strokeSurface(
                context,
                points: points,
                color: Palette.observationTint.opacity(0.34),
                lineWidth: 0.5,
                minimumDepth: 0.08
            )
        }
    }

    private func strokeSurface(
        _ context: GraphicsContext,
        points: [ProjectedPoint],
        color: Color,
        lineWidth: CGFloat = 0.42,
        minimumDepth: Double = 0
    ) {
        var path = Path()
        var drawing = false
        for point in points {
            if point.depth >= minimumDepth {
                if drawing {
                    path.addLine(to: point.point)
                } else {
                    path.move(to: point.point)
                    drawing = true
                }
            } else {
                drawing = false
            }
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func project(
        _ position: SIMD3<Double>,
        geometry: Geometry,
        orientation: simd_quatd
    ) -> ProjectedPoint {
        let transformed = orientation.act(position)
        return ProjectedPoint(
            point: CGPoint(
                x: geometry.center.x + transformed.x * Double(geometry.sceneRadius),
                y: geometry.center.y - transformed.y * Double(geometry.sceneRadius)
            ),
            depth: transformed.z
        )
    }

    private func projectSurface(
        _ direction: SIMD3<Double>,
        geometry: Geometry,
        orientation: simd_quatd
    ) -> ProjectedPoint {
        let transformed = orientation.act(direction)
        return ProjectedPoint(
            point: CGPoint(
                x: geometry.center.x + transformed.x * Double(geometry.earthRadius),
                y: geometry.center.y - transformed.y * Double(geometry.earthRadius)
            ),
            depth: transformed.z
        )
    }

    private static func geometry(in size: CGSize, scale: CGFloat) -> Geometry {
        let sceneRadius = min(size.width * 0.47, size.height * 0.29) * scale
        return Geometry(
            center: CGPoint(x: size.width / 2, y: size.height * 0.43),
            sceneRadius: sceneRadius,
            earthRadius: sceneRadius * 0.59
        )
    }

    private static let viewOrientation = simd_normalize(
        simd_quatd(angle: 0.24, axis: SIMD3(1, 0, 0))
            * simd_quatd(angle: -0.34, axis: SIMD3(0, 1, 0))
            * simd_quatd(angle: -0.08, axis: SIMD3(0, 0, 1))
    )

}
