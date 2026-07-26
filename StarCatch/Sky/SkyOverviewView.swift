import SatelliteKit
import SwiftUI

/// 地心三维轨道场。所有点位来自与主视野相同的 ECI 传播帧；单指改变观察方位，
/// 双指缩放，拖尾也保留在三维空间中。
struct SkyOverviewView: View {
    @ObservedObject var session: SkySession
    @ObservedObject var clock: SkyClock

    let observation: Date
    let frameTime: TimeInterval
    let motionTime: TimeInterval
    let trails: TrailStore
    let focusedObjectId: String?
    @Binding var scaleModified: Bool
    let resetRequest: Int
    let interactive: Bool

    @State private var yaw: Double = -0.42
    @State private var settledYaw: Double = -0.42
    @State private var pitch: Double = 0.28
    @State private var settledPitch: Double = 0.28
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1

    private struct RenderSample {
        let object: CatalogObject
        let ephemeris: Ephemeris
        let projected: Projected3D
    }

    struct Projected3D {
        let point: CGPoint
        /// 大于零表示朝向观察者。
        let depth: Double
    }

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Palette.voidBlack)
                )

                let geometry = Self.globeGeometry(in: size)
                let window = Path(ellipseIn: geometry.rect)
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 22))
                    glow.fill(window, with: .color(Palette.signal.opacity(0.014)))
                }
                context.fill(window, with: .color(Palette.dust.opacity(0.026)))

                let focusedObject = focusedObjectId.flatMap { session.catalog.objectsByID[$0] }
                let focusedFamily = focusedObject?.family
                let live = clock.isLive

                var samples: [RenderSample] = []
                samples.reserveCapacity(session.overviewObjects.count)
                @MainActor func appendSample(_ object: CatalogObject) {
                    guard let ephemeris = session.ephemeris.cachedEphemeris(
                        object.id,
                        at: observation,
                        live: live
                    ), let projected = Self.project(
                        orbitalPosition: ephemeris.orbitalPosition,
                        center: geometry.center,
                        radius: geometry.radius,
                        yaw: yaw,
                        pitch: pitch,
                        zoom: zoom
                    ) else { return }
                    samples.append(RenderSample(
                        object: object,
                        ephemeris: ephemeris,
                        projected: projected
                    ))
                }
                for object in session.overviewObjects {
                    appendSample(object)
                }
                if let focusedObject,
                   !session.overviewObjects.contains(where: { $0.id == focusedObject.id }) {
                    appendSample(focusedObject)
                }

                context.drawLayer { field in
                    field.clip(to: window)
                    drawOrbitShells(field, geometry: geometry)
                    drawSpatialTrails(field, geometry: geometry, front: false)
                    drawField(field, samples: samples, front: false, focusedFamily: focusedFamily)
                    drawEarth(field, geometry: geometry)
                    drawSpatialTrails(field, geometry: geometry, front: true)
                    drawField(field, samples: samples, front: true, focusedFamily: focusedFamily)
                    drawFocusedObject(field, samples: samples)
                    drawObserver(field, geometry: geometry)
                }

                context.stroke(
                    window,
                    with: .color(Palette.inkLow.opacity(0.28)),
                    style: StrokeStyle(lineWidth: 0.62)
                )
                drawLegend(
                    context,
                    geometry: geometry,
                    displayed: samples.count,
                    total: session.visibleObjects.count,
                    focusedFamily: focusedFamily
                )
            }
            .contentShape(Rectangle())
            .gesture(orbitGesture)
            .simultaneousGesture(magnificationGesture)
            .onTapGesture(count: 2) { resetView() }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--previewOverviewTransform") {
                    yaw = 0.72
                    settledYaw = yaw
                    pitch = -0.36
                    settledPitch = pitch
                    zoom = 1.26
                    settledZoom = zoom
                }
                #endif
                scaleModified = abs(zoom - 1) > 0.015
            }
            .onChange(of: resetRequest) { _, _ in resetView() }
            .onDisappear { scaleModified = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("交互式三维地球轨道星图，显示观察者位置、卫星与实时轨迹")
        .accessibilityHint(interactive ? "单指上下左右旋转，双指缩放，双击复位" : "拖动时间轴查看轨道变化")
        .accessibilityAction(named: "复位星图") { resetView() }
    }

    // MARK: - 交互

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard interactive else { return }
                yaw = settledYaw + Double(value.translation.width) * 0.0072
                pitch = Self.clampedPitch(
                    settledPitch - Double(value.translation.height) * 0.0062
                )
            }
            .onEnded { value in
                guard interactive else { return }
                let remainingX = value.predictedEndTranslation.width - value.translation.width
                let remainingY = value.predictedEndTranslation.height - value.translation.height
                let targetYaw = yaw + Double(remainingX) * 0.0017
                let targetPitch = Self.clampedPitch(pitch - Double(remainingY) * 0.0015)
                settledYaw = targetYaw
                settledPitch = targetPitch
                withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) {
                    yaw = targetYaw
                    pitch = targetPitch
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard interactive else { return }
                zoom = min(1.72, max(0.78, settledZoom * value))
                scaleModified = abs(zoom - 1) > 0.015
            }
            .onEnded { _ in
                guard interactive else { return }
                settledZoom = zoom
            }
    }

    private func resetView() {
        guard interactive else { return }
        settledYaw = -0.42
        settledPitch = 0.28
        settledZoom = 1
        scaleModified = false
        withAnimation(Motion.fieldReset) {
            yaw = settledYaw
            pitch = settledPitch
            zoom = settledZoom
        }
    }

    nonisolated private static func clampedPitch(_ value: Double) -> Double {
        min(1.28, max(-1.28, value))
    }

    // MARK: - 三维投影

    struct GlobeGeometry {
        let center: CGPoint
        let radius: CGFloat

        var rect: CGRect {
            CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        }
    }

    nonisolated static func globeGeometry(in size: CGSize) -> GlobeGeometry {
        let radius = max(108, min((size.width - 10) / 2, (size.height - 224) / 2))
        let centerY = min(size.height * 0.43, size.height - 158 - radius)
        return GlobeGeometry(
            center: CGPoint(x: size.width / 2, y: max(104 + radius, centerY)),
            radius: radius
        )
    }

    /// 将真实 ECI 半径压缩到可读的视觉壳层。对数映射同时保留 LEO 的层次，
    /// 又不会让 GEO 把地球压成一个几乎不可见的小点。
    nonisolated static func project(
        orbitalPosition: SIMD3<Double>,
        center: CGPoint,
        radius: CGFloat,
        yaw: Double,
        pitch: Double,
        zoom: CGFloat
    ) -> Projected3D? {
        let magnitude = Self.magnitude(of: orbitalPosition)
        guard magnitude > 1 else { return nil }
        let altitude = max(0, magnitude - 6378.137)
        let normalizedAltitude = min(
            1,
            log1p(altitude / 350) / log1p(36_000 / 350)
        )
        let displayRadius = 0.26 + 0.70 * pow(normalizedAltitude, 0.72)
        return projectDirection(
            orbitalPosition / magnitude,
            displayRadius: displayRadius,
            center: center,
            radius: radius,
            yaw: yaw,
            pitch: pitch,
            zoom: zoom
        )
    }

    nonisolated private static func projectDirection(
        _ direction: SIMD3<Double>,
        displayRadius: Double,
        center: CGPoint,
        radius: CGFloat,
        yaw: Double,
        pitch: Double,
        zoom: CGFloat
    ) -> Projected3D {
        let cy = cos(yaw)
        let sy = sin(yaw)
        let cp = cos(pitch)
        let sp = sin(pitch)
        let x = direction.x * cy + direction.z * sy
        let firstDepth = -direction.x * sy + direction.z * cy
        let y = direction.y * cp - firstDepth * sp
        let depth = direction.y * sp + firstDepth * cp
        let scale = Double(radius * zoom) * displayRadius
        return Projected3D(
            point: CGPoint(
                x: center.x + CGFloat(x * scale),
                y: center.y - CGFloat(y * scale)
            ),
            depth: depth * displayRadius
        )
    }

    nonisolated private static func magnitude(of value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    // MARK: - 绘制

    private func drawOrbitShells(_ context: GraphicsContext, geometry: GlobeGeometry) {
        for (displayRadius, opacity) in [(0.49, 0.13), (0.72, 0.075), (0.95, 0.11)] {
            drawCircle3D(
                context,
                geometry: geometry,
                displayRadius: displayRadius,
                opacity: opacity,
                dashed: displayRadius != 0.49
            )
        }
    }

    private func drawCircle3D(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        displayRadius: Double,
        opacity: Double,
        dashed: Bool
    ) {
        let points = stride(from: 0.0, through: Double.pi * 2, by: Double.pi / 48).map { angle in
            Self.projectDirection(
                SIMD3(cos(angle), sin(angle), 0),
                displayRadius: displayRadius,
                center: geometry.center,
                radius: geometry.radius,
                yaw: yaw,
                pitch: pitch,
                zoom: zoom
            )
        }
        strokeSegments(
            context,
            projected: points,
            front: false,
            color: Palette.inkLow.opacity(opacity * 0.42),
            style: StrokeStyle(lineWidth: 0.38, dash: dashed ? [1, 6] : [])
        )
        strokeSegments(
            context,
            projected: points,
            front: true,
            color: Palette.inkLow.opacity(opacity),
            style: StrokeStyle(lineWidth: 0.48, dash: dashed ? [1, 6] : [])
        )
    }

    private func drawField(
        _ context: GraphicsContext,
        samples: [RenderSample],
        front: Bool,
        focusedFamily: CatalogFamily?
    ) {
        var exploration: [CGPoint] = []
        var observation: [CGPoint] = []
        var network: [CGPoint] = []
        var legacy: [CGPoint] = []
        var familyFields: [CatalogFamily: [CGPoint]] = [:]
        exploration.reserveCapacity(samples.count / 8)
        observation.reserveCapacity(samples.count / 6)
        network.reserveCapacity(samples.count / 5)
        legacy.reserveCapacity(64)
        familyFields.reserveCapacity(CatalogFamily.allCases.count)

        for sample in samples where sample.object.id != focusedObjectId {
            guard (sample.projected.depth >= 0) == front else { continue }
            if let family = sample.object.family {
                familyFields[family, default: []].append(sample.projected.point)
            } else {
                switch sample.object.category {
                case .exploration: exploration.append(sample.projected.point)
                case .observation: observation.append(sample.projected.point)
                case .network: network.append(sample.projected.point)
                case .legacy: legacy.append(sample.projected.point)
                }
            }
        }

        let sideOpacity = front ? 1.0 : 0.24
        SkyRenderer.drawTargetField(
            context,
            points: exploration,
            tint: Palette.explorationTint,
            opacity: 0.58 * sideOpacity,
            coreRadius: front ? 0.78 : 0.52,
            haloStrength: front ? 0.07 : 0
        )
        SkyRenderer.drawTargetField(
            context,
            points: observation,
            tint: Palette.observationTint,
            opacity: 0.56 * sideOpacity,
            coreRadius: front ? 0.75 : 0.5,
            haloStrength: front ? 0.075 : 0
        )
        SkyRenderer.drawTargetField(
            context,
            points: network,
            tint: Palette.networkTint,
            opacity: 0.54 * sideOpacity,
            coreRadius: front ? 0.74 : 0.49,
            haloStrength: front ? 0.065 : 0
        )
        SkyRenderer.drawTargetField(
            context,
            points: legacy,
            tint: Palette.legacyTint,
            opacity: 0.48 * sideOpacity,
            coreRadius: front ? 0.72 : 0.48,
            haloStrength: front ? 0.06 : 0
        )
        for family in CatalogFamily.allCases {
            let emphasized = family == focusedFamily
            SkyRenderer.drawTargetField(
                context,
                points: familyFields[family, default: []],
                tint: family.tint,
                opacity: (emphasized ? 0.74 : 0.32) * sideOpacity,
                coreRadius: emphasized
                    ? (front ? 0.94 : 0.62)
                    : (front ? 0.62 : 0.42),
                haloStrength: front ? (emphasized ? 0.16 : 0.09) : 0
            )
        }
    }

    private func drawFocusedObject(_ context: GraphicsContext, samples: [RenderSample]) {
        guard let sample = samples.first(where: { $0.object.id == focusedObjectId }) else { return }
        let point = sample.projected.point
        let tint = sample.object.identityTint
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 4))
            glow.fill(
                Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)),
                with: .color(tint.opacity(0.24))
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 1.7, y: point.y - 1.7, width: 3.4, height: 3.4)),
            with: .color(Palette.inkHigh.opacity(0.98))
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)),
            with: .color(tint.opacity(0.86)),
            style: StrokeStyle(lineWidth: 0.72, dash: [1.5, 2.5])
        )
    }

    private func drawSpatialTrails(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        front: Bool
    ) {
        for object in session.visibleTrailObjects {
            guard let spatialPoints = trails.spatialTrails[object.id], spatialPoints.count > 1 else {
                continue
            }
            let projected = spatialPoints.compactMap { point -> (Projected3D, TimeInterval)? in
                guard let projection = Self.project(
                    orbitalPosition: point.position,
                    center: geometry.center,
                    radius: geometry.radius,
                    yaw: yaw,
                    pitch: pitch,
                    zoom: zoom
                ) else { return nil }
                return (projection, point.at)
            }
            let tint = object.identityTint
            var segment: [TrailStore.TrailPoint] = []
            for item in projected {
                if (item.0.depth >= 0) == front {
                    segment.append(TrailStore.TrailPoint(point: item.0.point, at: item.1))
                } else {
                    drawTrailSegment(context, points: segment, tint: tint, front: front)
                    segment.removeAll(keepingCapacity: true)
                }
            }
            drawTrailSegment(context, points: segment, tint: tint, front: front)
        }
    }

    private func drawTrailSegment(
        _ context: GraphicsContext,
        points: [TrailStore.TrailPoint],
        tint: Color,
        front: Bool
    ) {
        guard points.count > 1 else { return }
        SkyRenderer.drawTrail(
            context,
            points: points,
            frameTime: frameTime,
            tint: tint,
            intensity: front ? 0.86 : 0.16,
            lifetime: trails.trailLifetime
        )
    }

    private func drawEarth(_ context: GraphicsContext, geometry: GlobeGeometry) {
        let earthRadius = geometry.radius * zoom * 0.26
        let earthRect = CGRect(
            x: geometry.center.x - earthRadius,
            y: geometry.center.y - earthRadius,
            width: earthRadius * 2,
            height: earthRadius * 2
        )
        let earth = Path(ellipseIn: earthRect)
        context.drawLayer { shadow in
            shadow.addFilter(.blur(radius: 8))
            shadow.fill(earth, with: .color(Palette.voidBlack.opacity(0.96)))
        }
        context.fill(earth, with: .color(Palette.dust.opacity(0.36)))

        let highlightRect = earthRect.offsetBy(
            dx: -earthRadius * 0.18,
            dy: -earthRadius * 0.16
        ).insetBy(dx: earthRadius * 0.14, dy: earthRadius * 0.14)
        context.drawLayer { light in
            light.clip(to: earth)
            light.addFilter(.blur(radius: earthRadius * 0.16))
            light.fill(
                Path(ellipseIn: highlightRect),
                with: .color(Palette.signal.opacity(0.045))
            )
        }

        drawEarthGrid(context, geometry: geometry)
        context.stroke(
            earth,
            with: .color(Palette.inkLow.opacity(0.42)),
            style: StrokeStyle(lineWidth: 0.62)
        )
    }

    private func drawEarthGrid(_ context: GraphicsContext, geometry: GlobeGeometry) {
        let tint = Palette.inkLow.opacity(0.15)
        for latitude in stride(from: -60.0, through: 60.0, by: 30.0) {
            let lat = latitude * .pi / 180
            let points = stride(from: 0.0, through: Double.pi * 2, by: Double.pi / 36).map { longitude in
                Self.projectDirection(
                    SIMD3(cos(lat) * cos(longitude), cos(lat) * sin(longitude), sin(lat)),
                    displayRadius: 0.26,
                    center: geometry.center,
                    radius: geometry.radius,
                    yaw: yaw,
                    pitch: pitch,
                    zoom: zoom
                )
            }
            strokeSegments(context, projected: points, front: true, color: tint)
        }
        for longitude in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 6) {
            let points = stride(from: -Double.pi / 2, through: Double.pi / 2, by: Double.pi / 36).map { latitude in
                Self.projectDirection(
                    SIMD3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude)),
                    displayRadius: 0.26,
                    center: geometry.center,
                    radius: geometry.radius,
                    yaw: yaw,
                    pitch: pitch,
                    zoom: zoom
                )
            }
            strokeSegments(context, projected: points, front: true, color: tint)
        }
    }

    /// 观察者标记在真实地表位置：断续定位环、菱形核心和外向刻度组成仪器符号，
    /// 不再用 “YOU” 文本解释。
    private func drawObserver(_ context: GraphicsContext, geometry: GlobeGeometry) {
        let coordinates = session.observer.coordinates
        let eci = geo2eci(
            julianDays: observation.julianDate,
            geodetic: LatLonAlt(
                coordinates.latitude,
                coordinates.longitude,
                coordinates.altitudeMeters / 1000
            )
        )
        let vector = SIMD3(eci.x, eci.y, eci.z)
        let magnitude = Self.magnitude(of: vector)
        guard magnitude > 0 else { return }
        let projected = Self.projectDirection(
            vector / magnitude,
            displayRadius: 0.26,
            center: geometry.center,
            radius: geometry.radius,
            yaw: yaw,
            pitch: pitch,
            zoom: zoom
        )
        let point = projected.point
        let front = projected.depth >= 0
        let alpha = front ? 1.0 : 0.24
        let pulse = 1 + CGFloat(sin(motionTime * 1.25)) * 0.07
        let ringRadius: CGFloat = 7.2 * pulse

        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 4))
            glow.fill(
                Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)),
                with: .color(Palette.signal.opacity(0.18 * alpha))
            )
        }
        context.stroke(
            Path(ellipseIn: CGRect(
                x: point.x - ringRadius,
                y: point.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )),
            with: .color(Palette.signal.opacity(0.82 * alpha)),
            style: StrokeStyle(
                lineWidth: 0.7,
                dash: [1.2, 2.2],
                dashPhase: CGFloat(motionTime * 1.6)
            )
        )
        var diamond = Path()
        diamond.move(to: CGPoint(x: point.x, y: point.y - 3.4))
        diamond.addLine(to: CGPoint(x: point.x + 3.4, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + 3.4))
        diamond.addLine(to: CGPoint(x: point.x - 3.4, y: point.y))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(Palette.signal.opacity(0.2 * alpha)))
        context.stroke(
            diamond,
            with: .color(Palette.inkHigh.opacity(0.9 * alpha)),
            style: StrokeStyle(lineWidth: 0.72)
        )
    }

    private func strokeSegments(
        _ context: GraphicsContext,
        projected: [Projected3D],
        front: Bool,
        color: Color,
        style: StrokeStyle = StrokeStyle(lineWidth: 0.42)
    ) {
        var path = Path()
        var drawing = false
        for point in projected {
            let matches = (point.depth >= 0) == front
            if matches {
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
        context.stroke(path, with: .color(color), style: style)
    }

    private func drawLegend(
        _ context: GraphicsContext,
        geometry: GlobeGeometry,
        displayed: Int,
        total: Int,
        focusedFamily: CatalogFamily?
    ) {
        let legendTitle = focusedFamily.map {
            "\($0.title)  ·  NETWORK HIGHLIGHT"
        } ?? "EARTH  ·  ORBIT OBJECTS"
        let legendTint = focusedFamily?.tint ?? Palette.inkLow
        context.draw(
            Text(legendTitle)
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(legendTint.opacity(0.74)),
            at: CGPoint(x: geometry.center.x, y: geometry.rect.maxY + 28),
            anchor: .center
        )
        context.draw(
            Text("DISPLAY  \(displayed)  /  CATALOG  \(total)")
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.signal.opacity(0.62)),
            at: CGPoint(x: geometry.center.x, y: geometry.rect.maxY + 48),
            anchor: .center
        )
        if interactive {
            context.draw(
                Text("DRAG  ↕↔  ·  PINCH  ±  ·  DOUBLE TAP  RESET")
                    .font(Typography.statusTag)
                    .tracking(0.7)
                    .foregroundStyle(Palette.inkLow.opacity(0.4)),
                at: CGPoint(x: geometry.center.x, y: geometry.rect.maxY + 68),
                anchor: .center
            )
        }
    }
}
