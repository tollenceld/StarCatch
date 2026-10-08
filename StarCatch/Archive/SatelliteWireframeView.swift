import SwiftUI
import UIKit
import simd

/// Original native geometry inspired by Hairline's rounded silhouettes and quiet creases.
/// This is a generic schematic, not a reconstruction of any catalog object.
struct SatelliteWireframeMesh {
    enum Stroke { case silhouette, crease, detail, highlight }
    struct Face { let vertices: [SIMD3<Double>] }
    struct Line {
        let a: SIMD3<Double>
        let b: SIMD3<Double>
        var stroke: Stroke = .detail
    }
    struct Solid {
        let faces: [Face]
        var vertices: [SIMD3<Double>] { faces.flatMap(\.vertices) }
    }
    let solids: [Solid]
    let details: [Line]
    var faces: [Face] { solids.flatMap(\.faces) }

    static let generic: Self = {
        var solids: [Solid] = []
        var details: [Line] = []
        func ring(center: SIMD3<Double>, half: SIMD2<Double>, radius: Double, z: Double) -> [SIMD3<Double>] {
            let r = min(radius, min(half.x, half.y))
            let corners = [
                SIMD2(half.x - r, half.y - r), SIMD2(-half.x + r, half.y - r),
                SIMD2(-half.x + r, -half.y + r), SIMD2(half.x - r, -half.y + r),
            ]
            return corners.enumerated().flatMap { corner, c in
                (0...8).map { step in
                    let angle = Double(corner) * .pi / 2 + Double(step) * .pi / 16
                    return center + SIMD3(c.x + r * cos(angle), c.y + r * sin(angle), z)
                }
            }
        }
        func traceRing(_ points: [SIMD3<Double>], stroke: Stroke) {
            for i in points.indices {
                details.append(Line(a: points[i], b: points[(i + 1) % points.count], stroke: stroke))
            }
        }
        func plate(
            _ center: SIMD3<Double>, _ half: SIMD3<Double>, radius: Double,
            crease: Double? = nil
        ) {
            let back = ring(center: center, half: SIMD2(half.x, half.y), radius: radius, z: -half.z)
            let front = ring(center: center, half: SIMD2(half.x, half.y), radius: radius, z: half.z)
            var faces = [Face(vertices: front), Face(vertices: Array(back.reversed()))]
            for i in front.indices {
                let j = (i + 1) % front.count
                faces.append(Face(vertices: [back[i], back[j], front[j], front[i]]))
            }
            solids.append(Solid(faces: faces))
            if let crease {
                for sign in [-1.0, 1.0] {
                    traceRing(
                        ring(
                            center: center, half: SIMD2(half.x - crease, half.y - crease),
                            radius: max(0.02, radius - crease), z: sign * (half.z + 0.002)), stroke: .crease)
                }
            }
        }
        // Rounded equipment bus, thermal lips, two articulated solar wings.
        plate(.zero, SIMD3(0.59, 0.73, 0.44), radius: 0.13, crease: 0.08)
        plate(SIMD3(0, 0.79, 0), SIMD3(0.47, 0.055, 0.36), radius: 0.06)
        plate(SIMD3(0, -0.79, 0), SIMD3(0.47, 0.055, 0.36), radius: 0.06)
        for sign in [-1.0, 1.0] {
            plate(SIMD3(sign * 0.96, 0, 0), SIMD3(0.38, 0.035, 0.035), radius: 0.025)
            plate(SIMD3(sign * 1.22, 0, 0), SIMD3(0.07, 0.13, 0.05), radius: 0.06)
            let center = SIMD3(sign * 2.38, 0, 0)
            plate(center, SIMD3(1.10, 0.68, 0.024), radius: 0.09, crease: 0.05)
            for z in [-0.027, 0.027] {
                for column in 1..<8 {
                    let x = center.x - 1.04 + Double(column) * 2.08 / 8
                    details.append(Line(a: SIMD3(x, -0.61, z), b: SIMD3(x, 0.61, z), stroke: .crease))
                }
                for y in [-0.30, 0.0, 0.30] {
                    details.append(
                        Line(a: SIMD3(center.x - 1.04, y, z), b: SIMD3(center.x + 1.04, y, z), stroke: .crease))
                }
            }
        }
        // A real shallow reflector surface masks the equipment behind it.
        let segments = 96
        func dishPoint(_ radius: Double, _ index: Int, back: Bool = false) -> SIMD3<Double> {
            let angle = Double(index) * 2 * .pi / Double(segments)
            return SIMD3(
                radius * cos(angle), 0.19 + radius * sin(angle),
                0.69 + 0.30 * pow(radius / 0.54, 2) - (back ? 0.025 : 0))
        }
        var dishFaces: [Face] = []
        for back in [false, true] {
            for i in 0..<segments {
                var triangle = [
                    dishPoint(0, i, back: back), dishPoint(0.18, i, back: back), dishPoint(0.18, i + 1, back: back),
                ]
                if back { triangle.reverse() }
                dishFaces.append(Face(vertices: triangle))
                for (inner, outer) in [(0.18, 0.36), (0.36, 0.54)] {
                    var quad = [
                        dishPoint(inner, i, back: back), dishPoint(outer, i, back: back),
                        dishPoint(outer, i + 1, back: back), dishPoint(inner, i + 1, back: back),
                    ]
                    if back { quad.reverse() }
                    dishFaces.append(Face(vertices: quad))
                }
            }
        }
        for i in 0..<segments {
            dishFaces.append(
                Face(vertices: [
                    dishPoint(0.54, i), dishPoint(0.54, i, back: true),
                    dishPoint(0.54, i + 1, back: true), dishPoint(0.54, i + 1),
                ]))
        }
        solids.append(Solid(faces: dishFaces))
        for radius in [0.50, 0.54] {
            traceRing(
                (0..<segments).map { dishPoint(radius, $0) + SIMD3(0, 0, 0.003) },
                stroke: radius == 0.54 ? .highlight : .crease)
        }
        // Three support struts and a small feed. No decorative concentric spiderweb.
        for i in 0..<3 {
            let angle = Double(i) * 2 * .pi / 3
            details.append(
                Line(
                    a: SIMD3(0.48 * cos(angle), 0.19 + 0.48 * sin(angle), 0.94),
                    b: SIMD3(0, 0.19, 1.27)))
        }
        plate(SIMD3(0, 0.19, 1.28), SIMD3(0.075, 0.08, 0.065), radius: 0.04)
        // Hardware features on both faces make a rear view useful too.
        traceRing(
            (0..<64).map { i in
                let a = Double(i) * 2 * .pi / 64
                return SIMD3(0.18 * cos(a), 0.12 + 0.18 * sin(a), -0.443)
            }, stroke: .detail)
        for sign in [-1.0, 1.0] {
            plate(SIMD3(sign * 0.36, 1.05, -0.10), SIMD3(0.018, 0.27, 0.018), radius: 0.014)
            plate(SIMD3(sign * 0.36, 1.33, -0.10), SIMD3(0.055, 0.025, 0.028), radius: 0.02)
        }
        return Self(solids: solids, details: details)
    }()
}

struct SatelliteWireframePose {
    var yaw = -0.55
    var pitch = 0.38
    var scale = 1.0
    var rotation: simd_quatd {
        get { simd_quatd(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatd(angle: pitch, axis: SIMD3(1, 0, 0)) }
        set {
            let forward = newValue.act(SIMD3<Double>(0, 0, 1))
            yaw = atan2(forward.x, forward.z)
            pitch = min(0.65, max(-0.65, asin(min(1, max(-1, -forward.y)))))
        }
    }
    func dragged(_ translation: CGSize) -> Self {
        guard translation.width.isFinite, translation.height.isFinite else { return self }
        var next = self
        next.yaw = (yaw + Double(translation.width) * 0.009).truncatingRemainder(dividingBy: 2 * .pi)
        next.pitch = min(0.65, max(-0.65, pitch + Double(translation.height) * 0.006))
        return next
    }
    mutating func zoom(to value: Double) {
        guard value.isFinite else { return }
        scale = min(1.65, max(0.8, value))
    }
    func projectionUnit(size: CGSize) -> Double {
        // A fixed orthographic camera: a horizontal orbit never changes zoom.
        min(size.width / 8.0, size.height / 4.0) * scale
    }
    func project(_ vertex: SIMD3<Double>, size: CGSize, unit: Double? = nil) -> CGPoint {
        let p = rotation.act(vertex)
        let unit = unit ?? projectionUnit(size: size)
        return CGPoint(x: size.width / 2 + p.x * unit, y: size.height / 2 - p.y * unit)
    }
}

/// Gesture ownership is explicit; adding a second finger cancels rotation, not its pose.
struct SatelliteWireframeInteraction {
    enum Mode { case idle, rotating, zooming }
    private(set) var mode: Mode = .idle
    var pose = SatelliteWireframePose()
    private var origin = SatelliteWireframePose()
    mutating func beginRotation() {
        guard mode != .zooming else { return }
        origin = pose
        mode = .rotating
    }
    mutating func rotate(_ translation: CGSize) {
        guard mode == .rotating else { return }
        let moved = origin.dragged(translation)
        pose.yaw = moved.yaw
        pose.pitch = moved.pitch
    }
    mutating func endRotation() { if mode == .rotating { mode = .idle } }
    mutating func beginZoom() {
        origin = pose
        mode = .zooming
    }
    mutating func zoom(_ factor: Double) {
        guard mode == .zooming, factor.isFinite, factor > 0 else { return }
        pose.zoom(to: origin.scale * factor)
    }
    mutating func endZoom() { if mode == .zooming { mode = .idle } }
    mutating func reset() { self = Self() }
}

/// An orthographic depth test keeps rear creases out of foreground solids.
/// Triangles and bounds are prepared once per interaction redraw, never in a timer.
struct SatelliteWireframeFrame {
    struct Occluder {
        let a: SIMD3<Double>, b: SIMD3<Double>, c: SIMD3<Double>
        let minX: Double, maxX: Double, minY: Double, maxY: Double, denominator: Double
        init?(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
            let d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            guard d > 0.000_000_1 else { return nil }  // only camera-facing triangles
            self.a = a
            self.b = b
            self.c = c
            denominator = d
            minX = min(a.x, min(b.x, c.x))
            maxX = max(a.x, max(b.x, c.x))
            minY = min(a.y, min(b.y, c.y))
            maxY = max(a.y, max(b.y, c.y))
        }
        func hides(_ point: SIMD3<Double>) -> Bool {
            guard point.x >= minX, point.x <= maxX, point.y >= minY, point.y <= maxY else { return false }
            let u = ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / denominator
            let v = ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / denominator
            guard u >= -0.000_01, v >= -0.000_01, u + v <= 1.000_01 else { return false }
            return u * a.z + v * b.z + (1 - u - v) * c.z > point.z + 0.006
        }
    }
    let occluders: [Occluder]
    let lines: [SatelliteWireframeMesh.Line]
    init(mesh: SatelliteWireframeMesh = .generic, pose: SatelliteWireframePose) {
        let rotate = pose.rotation
        var occluders: [Occluder] = []
        var lines: [SatelliteWireframeMesh.Line] = []
        for solid in mesh.solids {
            for face in solid.faces {
                let v = face.vertices.map { rotate.act($0) }
                for i in 1..<(v.count - 1) {
                    if let t = Occluder(v[0], v[i], v[i + 1]) { occluders.append(t) }
                }
            }
            let hull = Self.hull(solid.vertices.map { rotate.act($0) })
            for i in hull.indices {
                lines.append(.init(a: hull[i], b: hull[(i + 1) % hull.count], stroke: .silhouette))
            }
        }
        lines += mesh.details.map { .init(a: rotate.act($0.a), b: rotate.act($0.b), stroke: $0.stroke) }
        self.occluders = occluders
        self.lines = lines
    }
    func isHidden(_ point: SIMD3<Double>) -> Bool { occluders.contains { $0.hides(point) } }
    /// Monotone convex hull retains depth, so each silhouette can be depth tested.
    static func hull(_ points: [SIMD3<Double>]) -> [SIMD3<Double>] {
        // Co-projected front/back vertices must keep the front depth consistently.
        var frontmost: [SIMD2<Double>: SIMD3<Double>] = [:]
        for point in points {
            let key = SIMD2(point.x, point.y)
            if frontmost[key] == nil || point.z > frontmost[key]!.z { frontmost[key] = point }
        }
        let sorted = frontmost.values.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count > 2 else { return sorted }
        func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        var lower: [SIMD3<Double>] = []
        var upper: [SIMD3<Double>] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }
    func visibleSegments(of line: SatelliteWireframeMesh.Line, unit: Double) -> [SatelliteWireframeMesh.Line] {
        let projectedLength = simd_length(SIMD2(line.b.x - line.a.x, line.b.y - line.a.y)) * unit
        let steps = max(1, min(160, Int(ceil(projectedLength / 1.5))))
        var result: [SatelliteWireframeMesh.Line] = []
        var start: SIMD3<Double>?
        for i in 0..<steps {
            let a = line.a + (line.b - line.a) * Double(i) / Double(steps)
            let b = line.a + (line.b - line.a) * Double(i + 1) / Double(steps)
            if !isHidden((a + b) / 2) {
                if start == nil { start = a }
                if i == steps - 1, let start { result.append(.init(a: start, b: b, stroke: line.stroke)) }
            } else if let run = start {
                result.append(.init(a: run, b: a, stroke: line.stroke))
                start = nil
            }
        }
        return result
    }
}

struct SatelliteWireframeView: View {
    var compact = false
    var drawingHeight: CGFloat = 180
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var interaction = SatelliteWireframeInteraction()
    private func copy(_ key: String) -> String { L10n.text(key, table: "SatelliteText") }
    var body: some View {
        // Read state in body, not only inside Canvas's deferred drawing closure.
        // Otherwise a gesture can update the pose without invalidating the canvas.
        let pose = interaction.pose
        VStack(spacing: 0) {
            if !compact {
                let layout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Text(copy("archive.model.schematic"))
                        .foregroundStyle(Palette.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Button {
                        interaction.reset()
                    } label: {
                        Text(copy("archive.model.reset"))
                            .foregroundStyle(Palette.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
                .font(Typography.statusTag)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Canvas { context, size in draw(context: &context, size: size, pose: pose) }
                .frame(height: drawingHeight)
                .overlay {
                    SatelliteWireframeGestures(
                        onRotationBegan: { interaction.beginRotation() },
                        onRotation: { interaction.rotate($0) },
                        onRotationEnded: { interaction.endRotation() },
                        onZoomBegan: { interaction.beginZoom() },
                        onZoom: { interaction.zoom($0) },
                        onZoomEnded: { interaction.endZoom() },
                        onReset: { interaction.reset() }
                    )
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(copy("archive.model.schematic"))
                .accessibilityHint(copy("archive.model.accessibility"))
                .accessibilityAdjustableAction { direction in
                    interaction.pose = interaction.pose.dragged(
                        CGSize(width: direction == .increment ? 35 : -35, height: 0))
                }
                .accessibilityAction(named: Text(copy("archive.model.reset"))) { interaction.reset() }
                .accessibilityAction(named: Text(copy("archive.chart.zoom_in"))) {
                    interaction.pose.zoom(to: interaction.pose.scale * 1.2)
                }
                .accessibilityAction(named: Text(copy("archive.chart.zoom_out"))) {
                    interaction.pose.zoom(to: interaction.pose.scale / 1.2)
                }
            if !compact {
                Text(copy("archive.model.gesture"))
                    .font(Typography.statusTag)
                    .foregroundStyle(Palette.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipped()
        #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--previewWireframeTurned") {
                    interaction.pose = interaction.pose.dragged(CGSize(width: 260, height: -60))
                }
            }
        #endif
    }
    private func draw(context: inout GraphicsContext, size: CGSize, pose: SatelliteWireframePose) {
        let frame = SatelliteWireframeFrame(pose: pose)
        let unit = pose.projectionUnit(size: size)
        for style in [SatelliteWireframeMesh.Stroke.crease, .detail, .silhouette, .highlight] {
            var path = Path()
            for line in frame.lines where line.stroke == style {
                for segment in frame.visibleSegments(of: line, unit: unit) {
                    func project(_ point: SIMD3<Double>) -> CGPoint {
                        CGPoint(x: size.width / 2 + point.x * unit, y: size.height / 2 - point.y * unit)
                    }
                    path.move(to: project(segment.a))
                    path.addLine(to: project(segment.b))
                }
            }
            let alpha: Double =
                style == .highlight ? 0.95 : style == .silhouette ? 0.75 : style == .detail ? 0.48 : 0.28
            context.stroke(
                path, with: .color(Palette.Text.primary.opacity(alpha)),
                style: StrokeStyle(lineWidth: compact ? 0.65 : 0.85, lineCap: .round, lineJoin: .round))
        }
    }
}

/// One-touch pan and two-touch pinch use separate recognizers and gesture lifetimes.
private struct SatelliteWireframeGestures: UIViewRepresentable {
    let onRotationBegan: () -> Void
    let onRotation: (CGSize) -> Void
    let onRotationEnded: () -> Void
    let onZoomBegan: () -> Void
    let onZoom: (Double) -> Void
    let onZoomEnded: () -> Void
    let onReset: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.rotate(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoom(_:)))
        pinch.delegate = context.coordinator
        let reset = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.reset(_:)))
        reset.numberOfTapsRequired = 2
        reset.numberOfTouchesRequired = 1
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(reset)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SatelliteWireframeGestures
        init(_ parent: SatelliteWireframeGestures) { self.parent = parent }
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            return ArchiveChartGesturePolicy.acceptsHorizontalDrag(velocity: pan.velocity(in: pan.view))
        }
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            recognizer.view === other.view
        }
        @objc func rotate(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                parent.onRotationBegan()
                fallthrough
            case .changed:
                guard pan.numberOfTouches == 1 else {
                    parent.onRotationEnded()
                    return
                }
                let p = pan.translation(in: pan.view)
                parent.onRotation(CGSize(width: p.x, height: p.y))
            case .ended, .cancelled, .failed: parent.onRotationEnded()
            default: break
            }
        }
        @objc func zoom(_ pinch: UIPinchGestureRecognizer) {
            switch pinch.state {
            case .began:
                parent.onZoomBegan()
                fallthrough
            case .changed: parent.onZoom(Double(pinch.scale))
            case .ended:
                parent.onZoom(Double(pinch.scale))
                parent.onZoomEnded()
            case .cancelled, .failed: parent.onZoomEnded()
            default: break
            }
        }
        @objc func reset(_ tap: UITapGestureRecognizer) { if tap.state == .ended { parent.onReset() } }
    }
}
