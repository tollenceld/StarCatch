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


/// Compact summaries retain the trace; full reading uses discrete elevation samples.
/// This is an elevation/time plot of actual cached samples, not a looping orbit animation.
struct SatelliteMotionTraceView: View {
    let trace: SatelliteTrackSnapshot
    let tint: Color
    var compact = false

    private func copy(_ key: String) -> String { L10n.text(key, table: "SatelliteText") }

    var body: some View {
        if compact {
            compactTrace
        } else {
            SatelliteElevationPlot(trace: trace, tint: tint)
        }
    }

    @ViewBuilder
    private var compactTrace: some View {
        let points = trace.finitePoints
        let bounds = trace.elevationBounds
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(copy("archive.reading.trace_title"))
                Spacer(minLength: 8)
                Text(trace.referenceDate, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
            }
            .font(Typography.statusTag)
            .foregroundStyle(Palette.Text.tertiary)

            Canvas { context, size in
                guard points.count > 1,
                      let first = points.first, let last = points.last,
                      last.offset > first.offset else { return }
                let inset: CGFloat = 5
                func position(_ point: TrackSampler.TrackPoint) -> CGPoint {
                    CGPoint(
                        x: inset + (size.width - 2 * inset) * (point.offset - first.offset) / (last.offset - first.offset),
                        y: inset + (size.height - 2 * inset) * (1 - (point.elevation * 180 / .pi - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
                    )
                }
                for level in [bounds.lowerBound, 0, bounds.upperBound] {
                    guard bounds.contains(level) else { continue }
                    let y = inset + (size.height - 2 * inset) * (1 - (level - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(Palette.inkFaint.opacity(level == 0 ? 0.6 : 0.22)), style: StrokeStyle(lineWidth: 0.5))
                }
                for pair in zip(points, points.dropFirst()) {
                    // A missing propagation sample must remain a gap, not a fabricated line.
                    guard pair.1.offset - pair.0.offset <= 21 else { continue }
                    var line = Path()
                    line.move(to: position(pair.0))
                    line.addLine(to: position(pair.1))
                    let future = pair.0.offset >= 0
                    context.stroke(line, with: .color(future ? tint : Palette.Text.primary), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: future ? [3, 4] : []))
                }
                if let current = points.first(where: { abs($0.offset) < 0.01 }) {
                    let center = position(current)
                    var stem = Path()
                    stem.move(to: CGPoint(x: center.x, y: 0))
                    stem.addLine(to: CGPoint(x: center.x, y: size.height))
                    context.stroke(stem, with: .color(tint.opacity(0.25)), lineWidth: 0.5)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(tint))
                }
            }
            .frame(height: 42)
            .accessibilityHidden(true)

            HStack(alignment: .top) {
                sampleLabel(points.first, alignment: .leading)
                Spacer(minLength: 8)
                Text(copy("archive.reading.observation"))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                sampleLabel(points.last, alignment: .trailing)
            }
            .font(Typography.statusTag)
            .foregroundStyle(Palette.Text.secondary)

        }
    }

    private func sampleLabel(_ point: TrackSampler.TrackPoint?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            if let point {
                Text(String(format: "%+.0f MIN", point.offset / 60))
                Text(String(format: "EL %+.1f°", point.elevation * 180 / .pi))
            } else {
                Text("—")
            }
        }
    }
}


/// A six-minute scientific strip plot. Each mark is an actual 20-second sample;
/// gaps stay empty and the elevation scale retains at least 20 degrees of range.
private struct SatelliteElevationPlot: View {
    let trace: SatelliteTrackSnapshot
    let tint: Color
    @ScaledMetric(relativeTo: .caption) private var axisWidth: CGFloat = 38
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func copy(_ key: String) -> String { L10n.text(key, table: "SatelliteText") }

    var body: some View {
        let bounds = trace.elevationBounds
        let points = trace.finitePoints.filter { (-180 ... 180).contains($0.offset) }
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(copy("archive.reading.elevation"))
                    Spacer(minLength: 8)
                    timestamp
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy("archive.reading.elevation"))
                    timestamp
                }
            }
            .font(Typography.statusTag)
            .foregroundStyle(Palette.Text.tertiary)

            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 0) {
                    degreeLabel(bounds.upperBound)
                    Spacer(minLength: 0)
                    degreeLabel((bounds.lowerBound + bounds.upperBound) / 2)
                    Spacer(minLength: 0)
                    degreeLabel(bounds.lowerBound)
                }
                .frame(width: axisWidth, alignment: .trailing)
                plot(points: points, bounds: bounds)
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 144 : 116)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy("archive.reading.elevation"))
            .accessibilityValue(points.map {
                String(format: "%+.0f S, EL %+.1f°", $0.offset, $0.elevation * 180 / .pi)
            }.joined(separator: "; "))

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        Text(copy("archive.reading.observation"))
                            .foregroundStyle(tint)
                            .frame(maxWidth: .infinity)
                        HStack {
                            legend(future: false)
                            Spacer(minLength: 12)
                            legend(future: true)
                        }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        legend(future: false)
                        Spacer(minLength: 8)
                        Text(copy("archive.reading.observation"))
                            .foregroundStyle(tint)
                        Spacer(minLength: 8)
                        legend(future: true)
                    }
                }
            }
            .font(Typography.statusTag)
            .foregroundStyle(Palette.Text.tertiary)
            .padding(.leading, axisWidth + 10)

            Text(copy("archive.reading.sample_note"))
                .font(Typography.readingCompact)
                .foregroundStyle(Palette.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timestamp: some View {
        Text(trace.referenceDate, format: .dateTime.hour().minute().second())
            .monospacedDigit()
    }

    private func degreeLabel(_ value: Double) -> some View {
        Text(String(format: "%+.0f°", value))
            .font(Typography.statusTag)
            .foregroundStyle(Palette.Text.tertiary)
            .fixedSize()
    }

    private func legend(future: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(future ? Color.clear : Palette.Text.primary)
                .overlay(Circle().stroke(future ? tint : Color.clear, lineWidth: 1.2))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(future ? "+3 MIN" : "−3 MIN")
                .accessibilityLabel(copy(future ? "archive.reading.after" : "archive.reading.before") + " 3 MIN")
                .font(Typography.statusTag)
                .foregroundStyle(Palette.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func plot(points: [TrackSampler.TrackPoint], bounds: ClosedRange<Double>) -> some View {
        Canvas { context, size in
            let inset: CGFloat = 6
            let width = size.width - inset * 2
            let height = size.height - inset * 2
            func x(_ offset: Double) -> CGFloat { inset + width * (offset + 180) / 360 }
            func y(_ elevation: Double) -> CGFloat {
                inset + height * (1 - (elevation - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
            }

            // Quiet dot matrix supplies a time/elevation reference, not invented data.
            for column in 0 ... 18 {
                for row in 0 ... 6 {
                    let center = CGPoint(x: inset + width * Double(column) / 18,
                                         y: inset + height * Double(row) / 6)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 0.65, y: center.y - 0.65,
                                                       width: 1.3, height: 1.3)),
                                 with: .color(Palette.Text.tertiary.opacity(0.3)))
                }
            }
            if bounds.contains(0) {
                var horizon = Path()
                horizon.move(to: CGPoint(x: inset, y: y(0)))
                horizon.addLine(to: CGPoint(x: size.width - inset, y: y(0)))
                context.stroke(horizon, with: .color(Palette.Text.tertiary.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
            }
            var observation = Path()
            observation.move(to: CGPoint(x: x(0), y: 0))
            observation.addLine(to: CGPoint(x: x(0), y: size.height))
            context.stroke(observation, with: .color(tint.opacity(0.4)), lineWidth: 0.7)

            for point in points {
                let center = CGPoint(x: x(point.offset), y: y(point.elevation * 180 / .pi))
                let current = abs(point.offset) < 0.01
                let color = point.offset < 0 ? Palette.Text.primary : tint
                // A light dotted stem helps scan each column without implying a zero baseline.
                var stem = Path()
                stem.move(to: CGPoint(x: center.x, y: center.y + 5))
                stem.addLine(to: CGPoint(x: center.x, y: size.height - inset))
                context.stroke(stem, with: .color(color.opacity(0.16)),
                               style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                let radius: CGFloat = current ? 4 : 2.7
                let marker = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2))
                context.fill(marker, with: .color(point.offset <= 0 ? color : Palette.voidBlack))
                if point.offset > 0 {
                    context.stroke(marker, with: .color(tint), lineWidth: 1.3)
                }
                if current {
                    let ring = Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
                    context.stroke(ring, with: .color(tint.opacity(0.5)), lineWidth: 0.7)
                }
            }
        }
    }
}
