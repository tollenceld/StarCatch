import SwiftUI
import simd
import SatelliteKit

/// One cached observation, shared by the orbital and topocentric presentations.
struct ObservationSceneFrame {
    struct Target {
        let object: CatalogObject
        let ephemeris: Ephemeris
        let isOverview: Bool
        let revealOrder: Double
    }
    let observation: Date
    let observer: ObserverLocation.Coordinates
    let pointing: Pointing
    let targets: [Target]
    /// The coordinate value is the revision token, including measuredAt and accuracy.
    var observerVersion: ObserverLocation.Coordinates { observer }

    /// Historical return is a presentation interpolation between two real snapshots.
    /// Match by ID, not array order; keep orbital radii outside Earth on long returns.
    func returning(from source: Self, progress: Double) -> Self {
        let p = ObservationSceneMath.ease(progress)
        guard p < 1 else { return self }
        let previous = Dictionary(uniqueKeysWithValues: source.targets.map { ($0.object.id, $0) })
        let blended = targets.map { target -> Target in
            guard let old = previous[target.object.id] else { return target }
            var eph = target.ephemeris
            let a = old.ephemeris.orbitalPosition, b = eph.orbitalPosition
            let ar = simd_length(a), br = simd_length(b)
            if ar > 0, br > 0 {
                let rotation = simd_quatd(from: a / ar, to: b / br)
                let turn = simd_slerp(simd_quatd(angle: 0, axis: SIMD3(0, 0, 1)), rotation, p)
                eph.orbitalPosition = turn.act(a / ar) * (ar + (br - ar) * p)
            }
            let azimuthDelta = eph.azimuth - old.ephemeris.azimuth
            eph.azimuth = old.ephemeris.azimuth + atan2(sin(azimuthDelta), cos(azimuthDelta)) * p
            eph.elevation = old.ephemeris.elevation + (eph.elevation - old.ephemeris.elevation) * p
            eph.rangeKm = old.ephemeris.rangeKm + (eph.rangeKm - old.ephemeris.rangeKm) * p
            return Target(object: target.object, ephemeris: eph, isOverview: target.isOverview, revealOrder: target.revealOrder)
        }
        return Self(observation: source.observation.addingTimeInterval(observation.timeIntervalSince(source.observation) * p),
                    observer: observer, pointing: pointing, targets: blended)
    }
}

enum ObservationSceneCoordinates {
    static func sidereal(at date: Date) -> Double {
        zeroMeanSiderealTime(julianDate: date.julianDate) * .pi / 180
    }
}

enum ObservationSceneMath {
    static func ease(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * x * (10 + x * (-15 + 6 * x))
    }

    static func displayRadius(_ radiusKm: Double) -> Double {
        let altitude = max(0, radiusKm - 6378.137)
        let normalized = min(1, log1p(altitude / 350) / log1p(36_000 / 350))
        return SkyOverviewView.earthDisplayRadius
            + (SkyOverviewView.maximumOrbitDisplayRadius - SkyOverviewView.earthDisplayRadius)
                * pow(normalized, 0.68)
    }

    static func revealOrder(_ id: String) -> Double {
        let hash = id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return Double(hash % 1024) / 1024
    }
}

/// A continuous world-to-camera transform. Global units use the existing
/// compressed shells; the local endpoint is the ENU camera used by Projection.
/// Projection is homogeneous throughout (no interpolation of screen positions).
struct ObservationCameraState {
    struct Sample {
        let point: CGPoint
        let depth: Double
        let visibility: Double
    }
    let size: CGSize
    let geometry: SkyOverviewView.GlobeGeometry
    let zoom: CGFloat
    let localProgress: Double
    let observer: ObserverLocation.Coordinates
    let pointing: Pointing
    let sidereal: Double
    let observerPosition: SIMD3<Double>
    let east: SIMD3<Double>
    let north: SIMD3<Double>
    let up: SIMD3<Double>
    private let cameraOrientation: simd_quatd
    private let approachAxis: SIMD3<Double>
    private let travel: Double
    private let pixelScale: Double
    let localMagnification: CGFloat
    private let cameraOffset: SIMD3<Double>
    private let eye: SIMD3<Double>
    private let projectionScale: Double
    private let projectionCenter: CGPoint
    private let cameraDistance: Double

    init(size: CGSize, geometry: SkyOverviewView.GlobeGeometry, zoom: CGFloat,
         localProgress: Double, observer: ObserverLocation.Coordinates,
         pointing: Pointing, observation: Date,
         verticalFOV: Double = Projection.baseVerticalFOV) {
        self.size = size
        self.geometry = geometry
        self.zoom = zoom
        self.localProgress = min(1, max(0, localProgress))
        self.observer = observer
        self.pointing = pointing
        sidereal = zeroMeanSiderealTime(julianDate: observation.julianDate) * .pi / 180
        let longitude = observer.longitude * .pi / 180 + sidereal
        let latitude = observer.latitude * .pi / 180
        east = SIMD3(-sin(longitude), cos(longitude), 0)
        up = SIMD3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude))
        north = simd_cross(up, east)
        let site = geo2eci(julianDays: observation.julianDate,
                          geodetic: LatLonAlt(observer.latitude, observer.longitude, observer.altitudeMeters / 1000))
        observerPosition = SIMD3(site.x, site.y, site.z)
        travel = ObservationSceneMath.ease((self.localProgress - 0.22) / 0.78)
        pixelScale = Double(size.height) / 2 / tan(verticalFOV / 2)
        localMagnification = CGFloat(tan(Projection.baseVerticalFOV / 2) / tan(verticalFOV / 2))

        let focus = SkyOverviewView.presentationOrientation(
            latitude: observer.latitude, longitude: observer.longitude, siderealRadians: sidereal)
        let alignment = ObservationSceneMath.ease(self.localProgress / 0.32)
        let aligned = simd_slerp(geometry.orientation, focus, alignment)
        approachAxis = aligned.inverse.act(SIMD3(0, 0, 1))
        // Derive exactly the same ENU right/up basis, including zenith fallback
        // and roll, as Projection instead of approximating yaw/pitch in 2D.
        let basis = Projection.screenBasis(for: pointing.unitVector)
        let c = cos(-pointing.roll), s = sin(-pointing.roll)
        let rightENU = basis.right * c - basis.up * s
        let upENU = basis.right * s + basis.up * c
        let e = east, n = north, u = up
        func world(_ v: SIMD3<Double>) -> SIMD3<Double> { e * v.x + n * v.y + u * v.z }
        // Camera +Z points toward the viewer, so a proper rotation uses -bore.
        // The perspective denominator below therefore uses -camera.z.
        let matrix = simd_double3x3(columns: (world(rightENU), world(upENU), -world(pointing.unitVector))).transpose
        let localOrientation = simd_quatd(matrix)
        cameraOrientation = simd_slerp(aligned, localOrientation, ObservationSceneMath.ease((self.localProgress - 0.42) / 0.58))
        cameraOffset = cameraOrientation.act(approachAxis)
        cameraDistance = travel > 0.000001 ? (1 - travel) / travel : 0
        eye = observerPosition / 6378.137 * travel + approachAxis * ((1 - travel) / max(0.000001, travel))
        projectionScale = Double(geometry.radius * zoom) * SkyOverviewView.earthDisplayRadius * (1 - travel) + pixelScale * travel
        projectionCenter = CGPoint(x: geometry.center.x + (size.width / 2 - geometry.center.x) * travel,
                                   y: geometry.center.y + (size.height / 2 - geometry.center.y) * travel)
    }

    func project(_ position: SIMD3<Double>, surface: Bool = false) -> Sample? {
        let radius = simd_length(position)
        guard radius > 0, radius.isFinite else { return nil }
        let globalRadius = surface ? 1 : ObservationSceneMath.displayRadius(radius) / SkyOverviewView.earthDisplayRadius
        let worldRadius = globalRadius + (radius / 6378.137 - globalRadius) * travel
        let world = position / radius * worldRadius
        let camera = cameraOrientation.act(world - observerPosition / 6378.137 * travel)
        let offset = cameraOffset
        let denominator = (1 - travel) * offset.z - travel * camera.z
        let near = 0.000001 + 0.015 * (1 - ObservationSceneMath.ease((localProgress - 0.75) / 0.25))
        guard denominator > near else { return nil }
        let scale = projectionScale
        let center = projectionCenter
        let distance = cameraDistance
        let x = camera.x - offset.x * distance
        let y = camera.y - offset.y * distance
        let point = CGPoint(x: center.x + x * scale / denominator,
                            y: center.y - y * scale / denominator)
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let angle = atan2(hypot(x, y), denominator / max(travel, 0.000001))
        let localVisibility = 1 - min(1, max(0, (angle - Projection.fadeStart) / (Projection.fadeEnd - Projection.fadeStart)))
        if localProgress == 1, localVisibility <= 0 { return nil }
        let eyeDirection = travel > 0.000001 ? simd_normalize(eye - world) : approachAxis
        let normalDepth = simd_dot(world, eyeDirection)
        let skyDepth = surface ? 0 : ObservationSceneMath.ease((localProgress - 0.55) / 0.3)
        let depth = normalDepth * (1 - skyDepth) + denominator * skyDepth
        return Sample(point: point, depth: depth,
                      visibility: (1 - travel) + travel * localVisibility)
    }

    /// Exact sphere silhouette, clipped in homogeneous camera space before division.
    /// The camera approaches along the surface normal even as its gaze turns skyward;
    /// this keeps the eye outside Earth instead of cutting through it during pitch.
    func surfaceOutline() -> Path {
        let distance = simd_length(eye)
        guard distance > 1 else { return Path() }
        let normal = eye / distance
        let tangent = simd_normalize(simd_cross(normal, abs(normal.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(0, 1, 0)))
        let bitangent = simd_cross(normal, tangent)
        let radius = sqrt(1 - 1 / (distance * distance))
        let scale = Double(geometry.radius * zoom) * SkyOverviewView.earthDisplayRadius * (1 - travel) + pixelScale * travel
        let center = SIMD2(Double(geometry.center.x) * (1 - travel) + Double(size.width) / 2 * travel,
                           Double(geometry.center.y) * (1 - travel) + Double(size.height) / 2 * travel)
        let offset = cameraOrientation.act(approachAxis)
        let shift = travel > 0.000001 ? (1 - travel) / travel : 0
        var polygon = (0..<128).map { index -> SIMD3<Double> in
            let angle = Double(index) * 2 * .pi / 128
            let world = normal / distance + radius * (tangent * cos(angle) + bitangent * sin(angle))
            let v = cameraOrientation.act(world - observerPosition / 6378.137 * travel)
            let w = (1 - travel) * offset.z - travel * v.z
            return SIMD3(center.x * w + (v.x - offset.x * shift) * scale,
                         center.y * w - (v.y - offset.y * shift) * scale, w)
        }
        let planes: [(SIMD3<Double>) -> Double] = [
            { $0.z - 0.015 }, { $0.x + 16 * $0.z }, { (Double(size.width) + 16) * $0.z - $0.x },
            { $0.y + 16 * $0.z }, { (Double(size.height) + 16) * $0.z - $0.y }
        ]
        for plane in planes {
            guard !polygon.isEmpty else { break }
            let input = polygon
            polygon = []
            for (a, b) in zip(input, input.dropFirst() + input.prefix(1)) {
                let da = plane(a), db = plane(b)
                if da >= 0 { polygon.append(a) }
                if (da >= 0) != (db >= 0) { polygon.append(a + (b - a) * (da / (da - db))) }
            }
        }
        var path = Path()
        for (index, p) in polygon.enumerated() {
            let point = CGPoint(x: p.x / p.z, y: p.y / p.z)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if !polygon.isEmpty { path.closeSubpath() }
        return path
    }

    func projectSurface(_ direction: SIMD3<Double>) -> SkyOverviewView.Projected3D {
        guard let sample = project(direction * 6378.137, surface: true) else {
            return .init(point: .zero, depth: -1, displayRadius: SkyOverviewView.earthDisplayRadius)
        }
        return .init(point: sample.point, depth: sample.depth * SkyOverviewView.earthDisplayRadius,
                     displayRadius: SkyOverviewView.earthDisplayRadius)
    }

    func project(_ ephemeris: Ephemeris) -> Sample? {
        // Cached angles and ECI are interpolated independently by the engine.
        // Gradually reconcile that tiny difference in world space before arrival.
        let enu = SIMD3(cos(ephemeris.elevation) * sin(ephemeris.azimuth),
                        cos(ephemeris.elevation) * cos(ephemeris.azimuth), sin(ephemeris.elevation))
        let reconstructed = observerPosition + (east * enu.x + north * enu.y + up * enu.z) * ephemeris.rangeKm
        let correction = ObservationSceneMath.ease((localProgress - 0.65) / 0.35)
        let position = ephemeris.orbitalPosition * (1 - correction) + reconstructed * correction
        guard let sample = project(position) else { return nil }
        let horizon = ephemeris.elevation > 0 ? 1.0 : 1 - ObservationSceneMath.ease((localProgress - 0.7) / 0.25)
        return Sample(point: sample.point, depth: sample.depth, visibility: sample.visibility * horizon)
    }

    func surfacePosition(_ direction: SIMD3<Double>) -> SIMD3<Double> {
        let rotation = simd_quatd(angle: sidereal, axis: SIMD3(0, 0, 1))
        return rotation.act(direction) * 6378.137
    }
}

struct ObservationSceneReveal {
    var signal = 0.0
    var limb = 1.0
    var grid = 1.0
    var land = 1.0
    var orbits = 1.0
    var satellites = 1.0
    var observer = 1.0
    var confirmation = 1.0
    static let complete = Self()
}

/// Shared drawing operations; surfaces and orbital targets use the same camera.
@MainActor
enum ObservationSceneRenderer {
    private static let dust = StarDust()
    static func drawBackground(_ context: GraphicsContext, size: CGSize, pointing: Pointing,
                               verticalFOV: Double = Projection.baseVerticalFOV, presence: Double = 1) {
        var layer = context
        layer.opacity = presence
        SkyRenderer.drawDust(layer, dust: dust, size: size,
            transform: StarDust.skyTransform(pointing: pointing, canvasSize: size, verticalFOV: verticalFOV),
            quietObservation: true)
    }
    static func draw(_ context: GraphicsContext, camera: ObservationCameraState,
                     frame: ObservationSceneFrame, reveal: ObservationSceneReveal = .complete,
                     landStore: EarthCoastlineStore, focusedObjectID: String? = nil,
                     showsObserverCoordinates: Bool = false) {
        let local = camera.localProgress
        let surfacePresence = 1 - ObservationSceneMath.ease((local - 0.68) / 0.27)
        let localStyle = ObservationSceneMath.ease((local - 0.55) / 0.40)
        let wide = ObservationScale.wideFieldProgress(magnification: camera.localMagnification)
        let pointScale = CGFloat(1 - 0.28 * wide)
        let pointOpacity = 1 - 0.14 * wide
        let globeSamples = frame.targets.compactMap { target -> (ObservationSceneFrame.Target, ObservationCameraState.Sample)? in
            guard target.isOverview || local > 0.65,
                  let point = camera.project(target.ephemeris) else { return nil }
            return (target, point)
        }
        func drawPoints(front: Bool) {
            var shells = Array(repeating: [SkyOverviewView.Projected3D](), count: 8)
            var categoryTiers: [CatalogCategory: [SkyRenderer.StarMagnitude: [SkyRenderer.SatellitePoint]]] = [:]
            var familyTiers: [CatalogFamily: [SkyRenderer.StarMagnitude: [SkyRenderer.SatellitePoint]]] = [:]
            for (target, projected) in globeSamples {
                guard (projected.depth >= 0) == front else { continue }
                let arrival = ObservationSceneMath.ease((reveal.satellites * 1.25 - target.revealOrder) / 0.25)
                let additional = target.isOverview ? 1 : ObservationSceneMath.ease((local - 0.65) / 0.3)
                let alpha = arrival * additional * projected.visibility
                guard alpha > 0.01 else { continue }
                let bucket = min(7, max(0, Int(alpha * 7)))
                shells[bucket].append(.init(point: projected.point,
                    depth: projected.depth * SkyOverviewView.earthDisplayRadius,
                    displayRadius: ObservationSceneMath.displayRadius(simd_length(target.ephemeris.orbitalPosition))))
                if front, localStyle > 0, target.ephemeris.elevation > 0,
                   alpha > 0.5 {
                    let magnitude = StarMagnitudeScale.magnitude(rangeKm: target.ephemeris.rangeKm,
                        elevation: target.ephemeris.elevation, isCurated: target.object.isCurated || target.object.isFeatured)
                    let point = SkyRenderer.SatellitePoint(point: projected.point, seed: target.object.noradId,
                                                          signature: SkyRenderer.satelliteSignature(for: target.object))
                    if let family = target.object.family { familyTiers[family, default: [:]][magnitude, default: []].append(point) }
                    else { categoryTiers[target.object.category, default: [:]][magnitude, default: []].append(point) }
                }
            }
            for index in shells.indices where !shells[index].isEmpty {
                SkyOverviewView.drawGlobeSatelliteField(context, projected: shells[index],
                    geometry: camera.geometry, zoom: camera.zoom, front: front, simplified: false,
                    emphasis: Double(index) / 7 * (1 - localStyle))
            }
            for (category, tiers) in categoryTiers {
                SkyRenderer.drawStarField(context, tiers: tiers, tint: category.tint,
                    opacity: localStyle * pointOpacity, visualScale: pointScale)
            }
            for (family, tiers) in familyTiers {
                let emphasized = frame.targets.first { $0.object.id == focusedObjectID }?.object.family == family
                SkyRenderer.drawStarField(context, tiers: tiers, tint: family.tint,
                    opacity: localStyle * pointOpacity * (emphasized ? 0.70 : 0.62),
                    emphasis: emphasized ? 0.94 : 0.86, visualScale: pointScale)
            }
        }

        drawPoints(front: false)
        drawSurface(context, camera: camera, reveal: reveal, presence: surfacePresence, store: landStore)
        for (index, guide) in guides.enumerated() {
            let presence = ObservationSceneMath.ease(reveal.orbits * 1.5 - Double(index) * 0.1) * surfacePresence
            stroke(context, points: guide.compactMap { camera.project($0) },
                   color: Palette.inkLow.opacity(0.15 * presence), width: 0.45)
        }
        drawPoints(front: true)
        SkyOverviewView.drawGlobeForegroundRim(context, geometry: camera.geometry, zoom: camera.zoom,
            presence: surfacePresence * reveal.limb, camera: camera)
        drawObserver(context, camera: camera, reveal: reveal, presence: surfacePresence,
                     showsCoordinates: showsObserverCoordinates)
        if reveal.signal > 0 {
            let center = camera.geometry.center
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)),
                         with: .color(Palette.inkHigh.opacity(reveal.signal * 0.4)))
        }
        SkyRenderer.drawVignette(context, size: camera.size)
    }

    private static func drawSurface(_ context: GraphicsContext, camera: ObservationCameraState,
                                    reveal: ObservationSceneReveal, presence: Double, store: EarthCoastlineStore) {
        guard presence > 0.001, reveal.limb > 0 else { return }
        var surface = context
        surface.opacity = reveal.limb * presence
        SkyOverviewView.drawGlobeSurface(surface, geometry: camera.geometry, zoom: camera.zoom,
            siderealRadians: camera.sidereal, landDots: store.landDots, detailedCoastlines: store.coastlines,
            fallbackCoastlines: SkyOverviewView.coastlineSamples, presence: reveal.land, simplified: false,
            gridPresence: reveal.grid, camera: camera)
    }

    static func drawObserver(_ context: GraphicsContext, camera: ObservationCameraState,
                             reveal: ObservationSceneReveal, presence: Double, showsCoordinates: Bool = false) {
        let alpha = reveal.observer * presence
        guard alpha > 0.01, let point = camera.project(camera.observerPosition, surface: true), point.depth > 0 else { return }
        var ring: [ObservationCameraState.Sample] = []
        let cosine = cos(28.0 * Double.pi / 180)
        let sine = sin(28.0 * Double.pi / 180)
        for index in 0...64 {
            let angle = Double(index) * 2 * .pi / 64
            let tangent = camera.east * cos(angle) + camera.north * sin(angle)
            let direction = camera.up * cosine + tangent * sine
            if let sample = camera.project(direction * 6378.137, surface: true) { ring.append(sample) }
        }
        stroke(context, points: ring, color: Palette.signal.opacity(0.4 * alpha), width: 0.55)
        let r = 5.8 + (1 - reveal.confirmation) * 4
        let rect = CGRect(x: point.point.x - r, y: point.point.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(Palette.voidBlack.opacity(alpha * 0.8)))
        var marker = Path()
        marker.move(to: CGPoint(x: rect.midX, y: rect.minY))
        marker.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        marker.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        marker.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        marker.closeSubpath()
        context.stroke(marker, with: .color(Palette.signal.opacity(alpha * 0.8)), lineWidth: 0.7)
        context.fill(Path(ellipseIn: CGRect(x: point.point.x - 1, y: point.point.y - 1, width: 2, height: 2)),
                     with: .color(Palette.inkHigh.opacity(alpha)))
        if camera.observer.assumed || camera.observer.horizontalAccuracyMeters > 2000 || showsCoordinates {
            let label = showsCoordinates
                ? String(format: "%.2f° / %.2f°", camera.observer.latitude, camera.observer.longitude)
                : L10n.text(camera.observer.assumed ? "sky.observer.assumed" : "sky.issue.location_accuracy")
            context.draw(Text(label).font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Palette.inkMid.opacity(alpha)), at: CGPoint(x: point.point.x, y: point.point.y + 20))
        }
    }


    private static func stroke(_ context: GraphicsContext, points: [ObservationCameraState.Sample], color: Color, width: CGFloat) {
        var path = Path()
        for pair in zip(points, points.dropFirst()) {
            guard pair.0.depth > 0, pair.1.depth > 0,
                  hypot(pair.0.point.x - pair.1.point.x, pair.0.point.y - pair.1.point.y) < 240 else { continue }
            path.move(to: pair.0.point)
            path.addLine(to: pair.1.point)
        }
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    private static let guides: [[SIMD3<Double>]] = [18.0, 43, 53, 70, 82, 97.3].enumerated().map { index, degrees in
        let inclination = degrees * .pi / 180
        let node = simd_quatd(angle: Double(index) * 0.73, axis: SIMD3(0, 0, 1))
        return (0...72).map { sample in
            let angle = Double(sample) * 2 * .pi / 72
            return node.act(SIMD3(cos(angle), sin(angle) * cos(inclination), sin(angle) * sin(inclination)))
                * (6900 + Double(index) * 250)
        }
    }
}
