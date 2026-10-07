import SwiftUI
import simd

/// A reusable schematic mesh, not a reconstruction of a catalog object.
/// Geometry is built once; interaction only transforms these local vertices.
struct SatelliteWireframeMesh {
    struct Face {
        let vertices: [SIMD3<Double>]
        let grid: Bool
    }
    struct Line {
        let a: SIMD3<Double>
        let b: SIMD3<Double>
    }
    let faces: [Face]
    let details: [Line]

    static let generic: Self = {
        var faces: [Face] = []
        var details: [Line] = []
        func box(_ center: SIMD3<Double>, _ half: SIMD3<Double>, grid: Bool = false) {
            let v = [SIMD3(-1.0,-1,-1), SIMD3(1.0,-1,-1), SIMD3(1.0,1,-1), SIMD3(-1.0,1,-1),
                     SIMD3(-1.0,-1,1), SIMD3(1.0,-1,1), SIMD3(1.0,1,1), SIMD3(-1.0,1,1)]
                .map { center + $0 * half }
            for indices in [[0,3,2,1], [4,5,6,7], [0,1,5,4], [3,7,6,2], [0,4,7,3], [1,2,6,5]] {
                faces.append(Face(vertices: indices.map { v[$0] }, grid: grid && indices.count == 4))
            }
        }
        box(.zero, SIMD3(0.65,0.8,0.58))
        box(SIMD3(0,0.88,0), SIMD3(0.5,0.08,0.46))
        box(SIMD3(0,-0.88,0), SIMD3(0.5,0.08,0.46))
        for sign in [-1.0, 1.0] {
            box(SIMD3(sign * 0.94,0,0), SIMD3(0.3,0.045,0.045))
            box(SIMD3(sign * 2.35,0,0), SIMD3(1.18,0.73,0.035), grid: true)
        }
        // Instrument rim and a shallow parabolic dish, both oriented toward +Z.
        let segments = 32
        for radius in [0.22, 0.44, 0.58] {
            let depth = 0.78 + radius * radius * 0.8
            for index in 0..<segments {
                func point(_ i: Int) -> SIMD3<Double> {
                    let angle = Double(i) * 2 * .pi / Double(segments)
                    return SIMD3(radius * cos(angle), 0.28 + radius * sin(angle), depth)
                }
                details.append(Line(a: point(index), b: point(index + 1)))
            }
        }
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            details.append(Line(a: SIMD3(0,0.28,0.78),
                                b: SIMD3(0.58*cos(angle),0.28+0.58*sin(angle),1.05)))
        }
        details.append(Line(a: SIMD3(0,0.28,0.78), b: SIMD3(0,0.28,1.4)))
        details.append(Line(a: SIMD3(-0.48,0.96,0), b: SIMD3(-0.48,1.48,0)))
        details.append(Line(a: SIMD3(0.48,0.96,0), b: SIMD3(0.48,1.22,0)))
        return Self(faces: faces, details: details)
    }()

    static let fitVertices = Array(Set(generic.faces.flatMap(\.vertices)
        + generic.details.flatMap { [$0.a, $0.b] }))
}

struct SatelliteWireframePose {
    var rotation = simd_quatd(angle: -0.48, axis: SIMD3(0,1,0))
        * simd_quatd(angle: 0.36, axis: SIMD3(1,0,0))
    var scale = 1.0

    func dragged(_ translation: CGSize) -> Self {
        var next = self
        let yaw = simd_quatd(angle: Double(translation.width) * 0.009, axis: SIMD3(0,1,0))
        let pitch = simd_quatd(angle: Double(translation.height) * 0.009, axis: SIMD3(1,0,0))
        next.rotation = simd_normalize(pitch * yaw * rotation)
        return next
    }

    mutating func zoom(to value: Double) {
        guard value.isFinite else { return }
        scale = min(1.65, max(0.8, value))
    }

    func projectionUnit(size: CGSize) -> Double {
        // Fit the rotated bounding volume, including perspective, before user zoom.
        // This keeps a wing turned upright inside the same reading hero.
        var horizontalExtent = 0.0
        var verticalExtent = 0.0
        for vertex in SatelliteWireframeMesh.fitVertices {
            let p = rotation.act(vertex)
            let perspective = 9 / (9 - p.z)
            horizontalExtent = max(horizontalExtent, abs(p.x * perspective))
            verticalExtent = max(verticalExtent, abs(p.y * perspective))
        }
        return min(size.width / (2 * horizontalExtent + 0.8),
                   size.height / (2 * verticalExtent + 0.8)) * scale
    }

    func project(_ vertex: SIMD3<Double>, size: CGSize, unit: Double? = nil) -> CGPoint {
        let p = rotation.act(vertex)
        let perspective = 9 / (9 - p.z)
        let unit = unit ?? projectionUnit(size: size)
        return CGPoint(x: size.width / 2 + p.x * unit * perspective,
                       y: size.height / 2 - p.y * unit * perspective)
    }
}

struct SatelliteWireframeView: View {
    var compact = false
    var drawingHeight: CGFloat = 140
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pose = SatelliteWireframePose()
    @State private var dragOrigin: SatelliteWireframePose?
    @GestureState private var magnification = 1.0

    private func copy(_ key: String) -> String { L10n.text(key, table: "SatelliteText") }

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Text(copy("archive.model.schematic"))
                        .foregroundStyle(Palette.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Button(action: reset) {
                        Text(copy("archive.model.reset"))
                            .foregroundStyle(Palette.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .font(Typography.statusTag)
            }
            GeometryReader { _ in
                let displayed = displayedPose
                Canvas { context, size in
                    draw(context: &context, size: size, pose: displayed)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = pose }
                        pose.rotation = (dragOrigin ?? pose).dragged(value.translation).rotation
                    }
                    .onEnded { _ in dragOrigin = nil })
                .simultaneousGesture(MagnificationGesture()
                    .updating($magnification) { value, state, _ in state = value }
                    .onEnded { value in pose.zoom(to: pose.scale * value) })
                .onTapGesture(count: 2, perform: reset)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(copy("archive.model.schematic"))
                .accessibilityHint(copy("archive.model.accessibility"))
                .accessibilityAdjustableAction { direction in
                    pose = pose.dragged(CGSize(width: direction == .increment ? 35 : -35, height: 0))
                }
                .accessibilityAction(named: Text(copy("archive.model.reset")), reset)
            }
            .frame(height: drawingHeight)
            if !compact {
                Text(copy("archive.model.gesture"))
                    .font(Typography.statusTag)
                    .foregroundStyle(Palette.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background {
            if !compact {
                RadialGradient(colors: [Palette.skyGlow.opacity(0.11), .clear],
                               center: .center, startRadius: 0, endRadius: 190)
            }
        }
        .clipped()
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--previewWireframeTurned") {
                pose = pose.dragged(CGSize(width: 240, height: -90))
            }
        }
        #endif
    }

    private var displayedPose: SatelliteWireframePose {
        var result = pose
        result.zoom(to: pose.scale * magnification)
        return result
    }

    private func reset() {
        // Deliberately no idle spin or momentum: a reading surface stays still.
        dragOrigin = nil
        pose = SatelliteWireframePose()
    }

    private func draw(context: inout GraphicsContext, size: CGSize, pose: SatelliteWireframePose) {
        let mesh = SatelliteWireframeMesh.generic
        let unit = pose.projectionUnit(size: size)
        let faces = mesh.faces.sorted {
            meanDepth($0, pose: pose) < meanDepth($1, pose: pose)
        }
        for face in faces {
            let vertices = face.vertices.map { pose.project($0, size: size, unit: unit) }
            var outline = Path()
            outline.addLines(vertices)
            outline.closeSubpath()
            let a = pose.rotation.act(face.vertices[1] - face.vertices[0])
            let b = pose.rotation.act(face.vertices[2] - face.vertices[0])
            let facing = simd_cross(a,b).z > 0
            context.fill(outline, with: .color(Palette.voidBlack.opacity(0.97)))
            context.stroke(outline, with: .color(Palette.Text.primary.opacity(facing ? 0.88 : 0.22)),
                           style: StrokeStyle(lineWidth: compact ? 0.65 : 0.9, lineJoin: .round))
            if face.grid, facing, abs(face.vertices[0].z - face.vertices[1].z) < 0.001,
               abs(face.vertices[0].z - face.vertices[2].z) < 0.001 {
                var grid = Path()
                for column in 1..<8 {
                    let t = Double(column) / 8
                    line(from: face.vertices[0] + (face.vertices[1]-face.vertices[0])*t,
                         to: face.vertices[3] + (face.vertices[2]-face.vertices[3])*t,
                         path: &grid, pose: pose, size: size, unit: unit)
                }
                for row in 1..<4 {
                    let t = Double(row) / 4
                    line(from: face.vertices[0] + (face.vertices[3]-face.vertices[0])*t,
                         to: face.vertices[1] + (face.vertices[2]-face.vertices[1])*t,
                         path: &grid, pose: pose, size: size, unit: unit)
                }
                context.stroke(grid, with: .color(Palette.glassLight.opacity(0.32)), lineWidth: 0.5)
            }
        }
        // Front instrument contours fade behind the bus rather than glowing through it.
        var details = Path()
        for segment in mesh.details {
            line(from: segment.a, to: segment.b, path: &details, pose: pose, size: size, unit: unit)
        }
        let front = pose.rotation.act(SIMD3<Double>(0,0,1)).z
        context.stroke(details, with: .color(Palette.Text.primary.opacity(front > 0 ? 0.8 : 0.1)),
                       style: StrokeStyle(lineWidth: compact ? 0.6 : 0.8, lineCap: .round))
    }

    private func meanDepth(_ face: SatelliteWireframeMesh.Face, pose: SatelliteWireframePose) -> Double {
        face.vertices.map { pose.rotation.act($0).z }.reduce(0,+) / Double(face.vertices.count)
    }
    private func line(from a: SIMD3<Double>, to b: SIMD3<Double>, path: inout Path,
                      pose: SatelliteWireframePose, size: CGSize, unit: Double) {
        path.move(to: pose.project(a, size: size, unit: unit))
        path.addLine(to: pose.project(b, size: size, unit: unit))
    }
}
