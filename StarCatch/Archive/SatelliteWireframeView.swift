import SwiftUI
import UIKit
import simd

/// Original native geometry inspired by Hairline's rounded silhouettes and quiet creases.
/// This is a generic schematic, not a reconstruction of any catalog object.
struct SatelliteWireframeMesh {
    enum Stroke: Int { case silhouette, crease, detail, highlight }
    struct Face { let vertices: [SIMD3<Double>] }
    struct Line {
        let a: SIMD3<Double>
        let b: SIMD3<Double>
        var stroke: Stroke = .detail
    }
    struct Solid {
        let faces: [Face]
        let vertices: [SIMD3<Double>]
        let triangles: [SIMD3<Int>]

        init(faces: [Face]) {
            self.faces = faces
            var vertices: [SIMD3<Double>] = []
            var indices: [SIMD3<Double>: Int] = [:]
            var triangles: [SIMD3<Int>] = []
            for face in faces where face.vertices.count >= 3 {
                let polygon = face.vertices.map { vertex -> Int in
                    if let index = indices[vertex] { return index }
                    let index = vertices.count
                    vertices.append(vertex)
                    indices[vertex] = index
                    return index
                }
                for i in 1..<(polygon.count - 1) {
                    triangles.append(SIMD3(polygon[0], polygon[i], polygon[i + 1]))
                }
            }
            self.vertices = vertices
            self.triangles = triangles
        }
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
        // At the maximum archive zoom this yields subpixel rim error; more triangles
        // add drag cost without adding visible detail at this display size.
        let segments = 64
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
        let minX: Double, maxX: Double, minY: Double, maxY: Double
        private let ux: Double, uy: Double, u0: Double
        private let vx: Double, vy: Double, v0: Double
        private let zx: Double, zy: Double, z0: Double

        init?(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
            let d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            guard d > 0.000_000_1 else { return nil }  // only camera-facing triangles
            minX = min(a.x, min(b.x, c.x))
            maxX = max(a.x, max(b.x, c.x))
            minY = min(a.y, min(b.y, c.y))
            maxY = max(a.y, max(b.y, c.y))
            // Affine barycentric and depth planes: no repeated vector indexing or division.
            let ux = (b.y - c.y) / d
            let uy = (c.x - b.x) / d
            let vx = (c.y - a.y) / d
            let vy = (a.x - c.x) / d
            let u0 = -ux * c.x - uy * c.y
            let v0 = -vx * c.x - vy * c.y
            self.ux = ux
            self.uy = uy
            self.u0 = u0
            self.vx = vx
            self.vy = vy
            self.v0 = v0
            zx = ux * (a.z - c.z) + vx * (b.z - c.z)
            zy = uy * (a.z - c.z) + vy * (b.z - c.z)
            z0 = c.z + u0 * (a.z - c.z) + v0 * (b.z - c.z)
        }
        func hides(_ point: SIMD3<Double>) -> Bool { hides(x: point.x, y: point.y, z: point.z) }
        func hides(x: Double, y: Double, z: Double) -> Bool {
            guard x >= minX, x <= maxX, y >= minY, y <= maxY else { return false }
            let u = ux * x + uy * y + u0
            let v = vx * x + vy * y + v0
            guard u >= -0.000_01, v >= -0.000_01, u + v <= 1.000_01 else { return false }
            return zx * x + zy * y + z0 > z + 0.006
        }
    }
    let occluders: [Occluder]
    let lines: [SatelliteWireframeMesh.Line]
    private let depthIndex: DepthIndex
    init(mesh: SatelliteWireframeMesh = .generic, pose: SatelliteWireframePose) {
        let rotationMatrix = simd_double3x3(pose.rotation)
        var occluders: [Occluder] = []
        var lines: [SatelliteWireframeMesh.Line] = []
        for solid in mesh.solids {
            let vertices = solid.vertices.map { rotationMatrix * $0 }
            for triangle in solid.triangles {
                if let t = Occluder(vertices[triangle.x], vertices[triangle.y], vertices[triangle.z]) {
                    occluders.append(t)
                }
            }
            let hull = Self.hull(vertices)
            for i in hull.indices {
                lines.append(.init(a: hull[i], b: hull[(i + 1) % hull.count], stroke: .silhouette))
            }
        }
        lines += mesh.details.map { .init(a: rotationMatrix * $0.a, b: rotationMatrix * $0.b, stroke: $0.stroke) }
        self.occluders = occluders
        self.lines = lines
        depthIndex = DepthIndex(occluders: occluders)
    }
    func isHidden(_ point: SIMD3<Double>) -> Bool {
        isHidden(x: point.x, y: point.y, z: point.z)
    }
    private func isHidden(x: Double, y: Double, z: Double) -> Bool {
        guard let cell = depthIndex.cell(x: x, y: y) else { return false }
        for index in depthIndex.cells[cell] where occluders[index].hides(x: x, y: y, z: z) { return true }
        return false
    }

    /// Exact triangle tests, narrowed to a small projected neighborhood.
    /// The grid is independent of zoom; no low-resolution depth approximation is used.
    private struct DepthIndex {
        static let columns = 32
        static let rows = 24
        let minX: Double, minY: Double, maxX: Double, maxY: Double
        let xScale: Double, yScale: Double
        let cells: [[Int]]

        init(occluders: [Occluder]) {
            let minX = occluders.map(\.minX).min() ?? 0
            let minY = occluders.map(\.minY).min() ?? 0
            let maxX = occluders.map(\.maxX).max() ?? 0
            let maxY = occluders.map(\.maxY).max() ?? 0
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
            let xScale = Double(Self.columns) / max(0.000_001, maxX - minX)
            let yScale = Double(Self.rows) / max(0.000_001, maxY - minY)
            self.xScale = xScale
            self.yScale = yScale
            var cells = Array(repeating: [Int](), count: Self.columns * Self.rows)
            for (index, face) in occluders.enumerated() {
                let firstX = min(Self.columns - 1, max(0, Int((face.minX - minX) * xScale)))
                let lastX = min(Self.columns - 1, max(0, Int((face.maxX - minX) * xScale)))
                let firstY = min(Self.rows - 1, max(0, Int((face.minY - minY) * yScale)))
                let lastY = min(Self.rows - 1, max(0, Int((face.maxY - minY) * yScale)))
                for y in firstY...lastY {
                    for x in firstX...lastX { cells[y * Self.columns + x].append(index) }
                }
            }
            self.cells = cells
        }

        func cell(x: Double, y: Double) -> Int? {
            guard x >= minX, x <= maxX, y >= minY, y <= maxY else { return nil }
            let column = min(Self.columns - 1, max(0, Int((x - minX) * xScale)))
            let row = min(Self.rows - 1, max(0, Int((y - minY) * yScale)))
            return row * Self.columns + column
        }
    }
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
        var result: [SatelliteWireframeMesh.Line] = []
        forEachVisibleSegment(of: line, unit: unit) { a, b in
            result.append(.init(a: a, b: b, stroke: line.stroke))
        }
        return result
    }

    /// Stream runs straight into batched paths rather than allocating an array per line.
    func forEachVisibleSegment(
        of line: SatelliteWireframeMesh.Line, unit: Double,
        _ visit: (SIMD3<Double>, SIMD3<Double>) -> Void
    ) {
        let delta = line.b - line.a
        let projectedLength = simd_length(SIMD2(delta.x, delta.y)) * unit
        let steps = max(1, min(160, Int(ceil(projectedLength / 1.5))))
        let sx = delta.x / Double(steps)
        let sy = delta.y / Double(steps)
        let sz = delta.z / Double(steps)
        let ax = line.a.x
        let ay = line.a.y
        let az = line.a.z
        var start: Int?
        func point(at index: Int) -> SIMD3<Double> {
            let t = Double(index)
            return SIMD3(ax + sx * t, ay + sy * t, az + sz * t)
        }
        for i in 0..<steps {
            let mid = Double(i) + 0.5
            if !isHidden(x: ax + sx * mid, y: ay + sy * mid, z: az + sz * mid) {
                if start == nil { start = i }
                if i == steps - 1, let start { visit(point(at: start), line.b) }
            } else if let run = start {
                visit(point(at: run), point(at: i))
                start = nil
            }
        }
    }
}

struct SatelliteWireframeView: View {
    var compact = false
    var drawingHeight: CGFloat = 180
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var controller = SatelliteWireframeController()
    private func copy(_ key: String) -> String { L10n.text(key, table: "SatelliteText") }
    var body: some View {
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
                        controller.change { $0.reset() }
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
            SatelliteWireframeDrawing(controller: controller, compact: compact)
                .frame(height: drawingHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(copy("archive.model.schematic"))
                .accessibilityHint(copy("archive.model.accessibility"))
                .accessibilityAdjustableAction { direction in
                    controller.change {
                        $0.pose = $0.pose.dragged(CGSize(width: direction == .increment ? 35 : -35, height: 0))
                    }
                }
                .accessibilityAction(named: Text(copy("archive.model.reset"))) { controller.change { $0.reset() } }
                .accessibilityAction(named: Text(copy("archive.chart.zoom_in"))) {
                    controller.change { $0.pose.zoom(to: $0.pose.scale * 1.2) }
                }
                .accessibilityAction(named: Text(copy("archive.chart.zoom_out"))) {
                    controller.change { $0.pose.zoom(to: $0.pose.scale / 1.2) }
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
                    controller.change { $0.pose = $0.pose.dragged(CGSize(width: 260, height: -60)) }
                }
            }
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--previewWireframeDrag") else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                controller.change { $0.beginRotation() }
                for step in 0...120 {
                    guard !Task.isCancelled else {
                        controller.change { $0.endRotation() }
                        return
                    }
                    controller.change {
                        $0.rotate(CGSize(width: Double(step) * 4, height: sin(Double(step) / 20) * 35))
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                }
                controller.change {
                    $0.endRotation()
                    $0.beginZoom()
                }
                for step in 0...60 {
                    guard !Task.isCancelled else {
                        controller.change { $0.endZoom() }
                        return
                    }
                    controller.change { $0.zoom(1 + sin(Double(step) * .pi / 60) * 0.4) }
                    try? await Task.sleep(for: .milliseconds(16))
                }
                controller.change { $0.endZoom() }
            }
        #endif
    }
}

/// View-owned interaction stays local to UIKit. A drag does not rebuild the SwiftUI
/// header, controls or accessibility tree. setNeedsDisplay coalesces input updates.
@MainActor private final class SatelliteWireframeController {
    var interaction = SatelliteWireframeInteraction()
    weak var drawing: SatelliteWireframeDrawingView?
    func change(_ action: (inout SatelliteWireframeInteraction) -> Void) {
        action(&interaction)
        drawing?.setNeedsDisplay()
    }
}

private struct SatelliteWireframeDrawing: UIViewRepresentable {
    let controller: SatelliteWireframeController
    let compact: Bool
    func makeUIView(context: Context) -> SatelliteWireframeDrawingView {
        let view = SatelliteWireframeDrawingView(controller: controller)
        controller.drawing = view
        view.compact = compact
        return view
    }
    func updateUIView(_ view: SatelliteWireframeDrawingView, context: Context) {
        // Parent forecast/time updates must not invalidate an unchanged model.
        if view.compact != compact {
            view.compact = compact
            view.setNeedsDisplay()
        }
    }
}

/// Fixed hit region; one-touch pan and two-touch pinch keep separate lifetimes.
private final class SatelliteWireframeDrawingView: UIView, UIGestureRecognizerDelegate {
    let controller: SatelliteWireframeController
    var compact = false
    private var preparedFrame: SatelliteWireframeFrame?
    private var preparedYaw = Double.nan
    private var preparedPitch = Double.nan
    #if DEBUG
        private let profileDrawing = ProcessInfo.processInfo.arguments.contains("--previewWireframeDrag")
        private var drawingDurations: [Double] = []
    #endif
    private let colors = [0.75, 0.28, 0.48, 0.95].map {
        UIColor(Palette.Text.primary).withAlphaComponent($0).cgColor
    }

    init(controller: SatelliteWireframeController) {
        self.controller = controller
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = false
        contentMode = .redraw
        let pan = UIPanGestureRecognizer(target: self, action: #selector(rotate(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:)))
        pinch.delegate = self
        let reset = UITapGestureRecognizer(target: self, action: #selector(reset(_:)))
        reset.numberOfTapsRequired = 2
        reset.numberOfTouchesRequired = 1
        addGestureRecognizer(pan)
        addGestureRecognizer(pinch)
        addGestureRecognizer(reset)
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        #if DEBUG
            let started = profileDrawing ? CACurrentMediaTime() : 0
            defer {
                if profileDrawing && drawingDurations.count < 120 {
                    drawingDurations.append((CACurrentMediaTime() - started) * 1000)
                    if drawingDurations.count == 120 {
                        let sorted = drawingDurations.sorted()
                        print("WIREFRAME_DRAW cpu_median_ms=\(sorted[60]) cpu_p95_ms=\(sorted[114]) draws=120")
                    }
                }
            }
        #endif
        let pose = controller.interaction.pose
        if preparedFrame == nil || preparedYaw != pose.yaw || preparedPitch != pose.pitch {
            preparedFrame = SatelliteWireframeFrame(pose: pose)
            preparedYaw = pose.yaw
            preparedPitch = pose.pitch
        }
        guard let frame = preparedFrame else { return }
        let unit = pose.projectionUnit(size: bounds.size)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let paths = (0..<4).map { _ in CGMutablePath() }
        for line in frame.lines {
            frame.forEachVisibleSegment(of: line, unit: unit) { a, b in
                let path = paths[line.stroke.rawValue]
                path.move(to: CGPoint(x: center.x + a.x * unit, y: center.y - a.y * unit))
                path.addLine(to: CGPoint(x: center.x + b.x * unit, y: center.y - b.y * unit))
            }
        }
        context.setLineWidth(compact ? 0.65 : 0.85)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for index in [1, 2, 0, 3] {
            context.addPath(paths[index])
            context.setStrokeColor(colors[index])
            context.strokePath()
        }
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer.view === self else { return super.gestureRecognizerShouldBegin(recognizer) }
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
        return ArchiveChartGesturePolicy.acceptsHorizontalDrag(velocity: pan.velocity(in: self))
    }
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        recognizer.view === other.view
    }
    @objc private func rotate(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            controller.change { $0.beginRotation() }
            fallthrough
        case .changed:
            guard pan.numberOfTouches == 1 else {
                controller.change { $0.endRotation() }
                return
            }
            let p = pan.translation(in: self)
            controller.change { $0.rotate(CGSize(width: p.x, height: p.y)) }
        case .ended, .cancelled, .failed: controller.change { $0.endRotation() }
        default: break
        }
    }
    @objc private func zoom(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            controller.change { $0.beginZoom() }
            fallthrough
        case .changed: controller.change { $0.zoom(Double(pinch.scale)) }
        case .ended:
            controller.change {
                $0.zoom(Double(pinch.scale))
                $0.endZoom()
            }
        case .cancelled, .failed: controller.change { $0.endZoom() }
        default: break
        }
    }
    @objc private func reset(_ tap: UITapGestureRecognizer) {
        if tap.state == .ended { controller.change { $0.reset() } }
    }
}
