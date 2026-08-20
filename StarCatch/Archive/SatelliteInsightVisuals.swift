import SwiftUI

/// The archive animation consumes an immutable motion signature. The timeline
/// only interpolates paths and never invokes SGP4 or walks the catalog.
struct SatelliteInsightGraphic: View {
    let insight: SatelliteInsightSnapshot
    let tint: Color
    var compact = false

    var body: some View {
        Group {
            if let pass = insight.pass, pass.phase != .stationary {
                SatellitePassArcView(
                    pass: pass,
                    motion: insight.motion,
                    tint: tint,
                    compact: compact
                )
            } else {
                OrbitFingerprintView(
                    fingerprint: insight.fingerprint,
                    tint: tint,
                    compact: compact,
                    motion: insight.motion
                )
            }
        }
        .id(insight.objectID)
        .transition(.opacity)
    }
}

struct SatellitePassArcView: View {
    let pass: PassWindow
    let motion: SatelliteMotionSignature
    let tint: Color
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("reducedMotion") private var appReducedMotion = false

    private var suppressMotion: Bool { reduceMotion || appReducedMotion }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: suppressMotion || scenePhase != .active
            )
        ) { timeline in
            VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                Canvas { context, size in
                    drawPass(
                        context: &context,
                        size: size,
                        date: suppressMotion ? motion.referenceDate : timeline.date
                    )
                }
                .frame(height: compact ? 34 : 56)

                if !compact {
                    HStack {
                        Text(
                            L10n.text(
                                pass.phase == .approaching ? "axis.next_rise" : "axis.rise",
                                table: "SatelliteText"
                            )
                        )
                        Spacer()
                        if let maximum = pass.maximumElevationDegrees {
                            Text(
                                L10n.format(
                                    "axis.peak",
                                    table: "SatelliteText",
                                    maximum
                                )
                            )
                        }
                        Spacer()
                        Text(L10n.text("axis.set", table: "SatelliteText"))
                    }
                    .font(Typography.statusTag)
                    .tracking(0.55)
                    .foregroundStyle(Palette.inkLow.opacity(0.68))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(at: timeline.date))
        }
    }

    private func drawPass(
        context: inout GraphicsContext,
        size: CGSize,
        date: Date
    ) {
        let inset: CGFloat = compact ? 7 : 10
        let baseline = size.height - (compact ? 7 : 10)
        let peakHeight = max(8, size.height - (compact ? 13 : 19))
        let arc = passPath(size: size, inset: inset, baseline: baseline, peakHeight: peakHeight)
        context.stroke(
            arc,
            with: .color(tint.opacity(0.42)),
            style: StrokeStyle(lineWidth: 0.65, lineCap: .round)
        )

        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: baseline))
        horizon.addLine(to: CGPoint(x: size.width, y: baseline))
        context.stroke(
            horizon,
            with: .color(Palette.inkFaint.opacity(0.34)),
            style: StrokeStyle(lineWidth: 0.5, dash: [2, 4])
        )

        let factualProgress = pass.phase == .approaching
            ? 0.035
            : pass.progress(at: date) ?? pass.progress(at: motion.referenceDate) ?? 0.5
        let scan = OrbitMotionModel.scanProgress(for: motion, at: date)

        // Before rise, only a focus scan travels along the predicted path. The
        // object stays at the horizon and is not depicted as moving early.
        if pass.phase == .approaching, !suppressMotion {
            for index in 0 ..< 7 {
                let p = min(1, max(0, scan - Double(index) * 0.025))
                let point = point(progress: p, size: size, inset: inset, baseline: baseline, peakHeight: peakHeight)
                let alpha = 0.22 * (1 - Double(index) / 7)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)),
                    with: .color(tint.opacity(alpha))
                )
            }
        }

        let marker = point(
            progress: factualProgress,
            size: size,
            inset: inset,
            baseline: baseline,
            peakHeight: peakHeight
        )
        if pass.phase == .visible {
            drawDirectionalTrail(
                context: &context,
                progress: factualProgress,
                size: size,
                inset: inset,
                baseline: baseline,
                peakHeight: peakHeight
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: marker.x - 2.2, y: marker.y - 2.2, width: 4.4, height: 4.4)),
            with: .color(tint.opacity(0.96))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: marker.x - 6, y: marker.y - 6, width: 12, height: 12)),
            with: .color(tint.opacity(0.07))
        )
    }

    private func passPath(
        size: CGSize,
        inset: CGFloat,
        baseline: CGFloat,
        peakHeight: CGFloat
    ) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: inset, y: baseline))
        path.addQuadCurve(
            to: CGPoint(x: size.width - inset, y: baseline),
            control: CGPoint(x: size.width / 2, y: baseline - peakHeight * 2)
        )
        return path
    }

    private func point(
        progress: Double,
        size: CGSize,
        inset: CGFloat,
        baseline: CGFloat,
        peakHeight: CGFloat
    ) -> CGPoint {
        let p = min(1, max(0, progress))
        let x = inset + (size.width - inset * 2) * p
        let normalized = 2 * p - 1
        return CGPoint(x: x, y: baseline - peakHeight * (1 - normalized * normalized))
    }

    private func drawDirectionalTrail(
        context: inout GraphicsContext,
        progress: Double,
        size: CGSize,
        inset: CGFloat,
        baseline: CGFloat,
        peakHeight: CGFloat
    ) {
        for index in 1 ... 5 {
            let p = max(0, progress - Double(index) * 0.012)
            let trail = point(progress: p, size: size, inset: inset, baseline: baseline, peakHeight: peakHeight)
            context.fill(
                Path(ellipseIn: CGRect(x: trail.x - 0.7, y: trail.y - 0.7, width: 1.4, height: 1.4)),
                with: .color(tint.opacity(0.22 * (1 - Double(index) / 6)))
            )
        }
    }

    private func accessibilitySummary(at date: Date) -> String {
        switch pass.phase {
        case .approaching:
            return L10n.text("accessibility.pass.approaching", table: "SatelliteText")
        case .visible:
            let percent = Int((pass.progress(at: date) ?? 0) * 100)
            return L10n.format("accessibility.pass.visible", table: "SatelliteText", percent)
        case .stationary:
            return L10n.text("accessibility.pass.stationary", table: "SatelliteText")
        }
    }
}

struct OrbitFingerprintView: View {
    let fingerprint: OrbitFingerprint
    let tint: Color
    var compact = false
    var motion: SatelliteMotionSignature?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("reducedMotion") private var appReducedMotion = false

    private var suppressMotion: Bool { reduceMotion || appReducedMotion }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: suppressMotion || scenePhase != .active || motion == nil
            )
        ) { timeline in
            Canvas { context, size in
                drawOrbit(
                    context: &context,
                    size: size,
                    date: suppressMotion ? motion?.referenceDate ?? timeline.date : timeline.date
                )
            }
            .frame(height: compact ? 34 : 62)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format(
                "accessibility.orbit_fingerprint",
                table: "SatelliteText",
                fingerprint.periodMinutes,
                fingerprint.inclinationDegrees,
                fingerprint.eccentricity
            )
        )
    }

    private func drawOrbit(
        context: inout GraphicsContext,
        size: CGSize,
        date: Date
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let eccentricity = min(0.82, max(0, fingerprint.eccentricity))
        let width = size.width - (compact ? 20 : 34)
        let height = max(compact ? 13 : 22, width * CGFloat(0.38 - eccentricity * 0.22))
        let rect = CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        var transformed = context
        transformed.translateBy(x: center.x, y: center.y)
        transformed.rotate(by: .degrees(fingerprint.inclinationDegrees * 0.28 - 14))
        transformed.translateBy(x: -center.x, y: -center.y)
        transformed.stroke(
            Path(ellipseIn: rect),
            with: .color(tint.opacity(0.42)),
            style: StrokeStyle(lineWidth: 0.65, dash: [5, 3])
        )

        let focusX = center.x - width * CGFloat(eccentricity * 0.24)
        transformed.fill(
            Path(ellipseIn: CGRect(x: focusX - 2.1, y: center.y - 2.1, width: 4.2, height: 4.2)),
            with: .color(Palette.inkHigh.opacity(0.66))
        )

        let signature = motion ?? staticSignature
        let phase = OrbitMotionModel.phase(for: signature, at: date)
        let marker = CGPoint(
            x: center.x + cos(phase) * width / 2,
            y: center.y + sin(phase) * height / 2
        )

        if signature.presentation == .geostationary {
            drawStationKeepingFrame(context: &transformed, at: marker, scan: OrbitMotionModel.scanProgress(for: signature, at: date))
        } else {
            drawOrbitTrail(context: &transformed, center: center, width: width, height: height, phase: phase, direction: signature.angularDirection)
        }
        transformed.fill(
            Path(ellipseIn: CGRect(x: marker.x - 2.4, y: marker.y - 2.4, width: 4.8, height: 4.8)),
            with: .color(tint.opacity(0.96))
        )
    }

    private var staticSignature: SatelliteMotionSignature {
        SatelliteMotionSignature(
            referenceDate: .distantPast,
            phaseRadians: 0,
            angularDirection: 1,
            periodSeconds: fingerprint.periodMinutes * 60,
            inclinationDegrees: fingerprint.inclinationDegrees,
            eccentricity: fingerprint.eccentricity,
            rangeRateKmS: nil,
            presentation: fingerprint.eccentricity >= 0.08 ? .highElliptical : .mediumOrbit
        )
    }

    private func drawOrbitTrail(
        context: inout GraphicsContext,
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        phase: Double,
        direction: Double
    ) {
        for index in 1 ... 7 {
            let angle = phase - direction * Double(index) * 0.035
            let point = CGPoint(
                x: center.x + cos(angle) * width / 2,
                y: center.y + sin(angle) * height / 2
            )
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 0.65, y: point.y - 0.65, width: 1.3, height: 1.3)),
                with: .color(tint.opacity(0.2 * (1 - Double(index) / 8)))
            )
        }
    }

    private func drawStationKeepingFrame(
        context: inout GraphicsContext,
        at point: CGPoint,
        scan: Double
    ) {
        let radius: CGFloat = compact ? 6 : 8
        var frame = Path()
        frame.move(to: CGPoint(x: point.x - radius, y: point.y - radius / 2))
        frame.addLine(to: CGPoint(x: point.x - radius, y: point.y - radius))
        frame.addLine(to: CGPoint(x: point.x - radius / 2, y: point.y - radius))
        frame.move(to: CGPoint(x: point.x + radius / 2, y: point.y + radius))
        frame.addLine(to: CGPoint(x: point.x + radius, y: point.y + radius))
        frame.addLine(to: CGPoint(x: point.x + radius, y: point.y + radius / 2))
        context.stroke(frame, with: .color(tint.opacity(0.62)), lineWidth: 0.65)
        guard !suppressMotion else { return }
        let scanY = point.y - radius + radius * 2 * scan
        var line = Path()
        line.move(to: CGPoint(x: point.x - radius + 2, y: scanY))
        line.addLine(to: CGPoint(x: point.x + radius - 2, y: scanY))
        context.stroke(line, with: .color(tint.opacity(0.34)), lineWidth: 0.55)
    }
}
