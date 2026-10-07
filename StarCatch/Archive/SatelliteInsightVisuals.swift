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


/// The same sampled elevation plot at reading and summary densities.
struct SatelliteMotionTraceView: View {
    let trace: SatelliteTrackSnapshot
    let tint: Color
    var compact = false

    var body: some View {
        SatelliteElevationPlot(trace: trace, tint: tint, compact: compact)
    }
}

/// A six-minute scientific strip plot. Each mark is an actual 20-second sample;
/// gaps stay empty and the elevation scale retains at least 20 degrees of range.
private struct SatelliteElevationPlot: View {
    let trace: SatelliteTrackSnapshot
    let tint: Color
    var compact = false
    @ScaledMetric(relativeTo: .caption) private var axisWidth: CGFloat = 38
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedOffset: Double?
    @State private var zoom = 1.0
    @State private var viewCenter = 0.0

    private func copy(_ key: String) -> String { L10n.text(key, table: "SatelliteText") }
    private var viewport: ArchiveChartViewport {
        ArchiveChartViewport(extent: -180...180, minimumSpan: 120, zoom: zoom, center: viewCenter)
    }
    private var selectedPoint: TrackSampler.TrackPoint? {
        selectedOffset.flatMap { ArchiveChartSelection.nearestSample(in: trace, offset: $0) }
    }

    var body: some View {
        let bounds = trace.elevationBounds
        let range = viewport.visibleRange
        let points = trace.finitePoints.filter { range.contains($0.offset) }
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(copy("archive.reading.elevation")); Spacer(minLength: 8); timestamp }
                VStack(alignment: .leading, spacing: 4) { Text(copy("archive.reading.elevation")); timestamp }
            }
            .font(Typography.statusTag)
            .foregroundStyle(Palette.Text.tertiary)
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 0) {
                    degreeLabel(bounds.upperBound)
                    Spacer(minLength: 0)
                    if !compact {
                        degreeLabel((bounds.lowerBound + bounds.upperBound) / 2)
                        Spacer(minLength: 0)
                    }
                    degreeLabel(bounds.lowerBound)
                }
                .frame(width: axisWidth, alignment: .trailing)
                plot(points: points, bounds: bounds, range: range)
                    .overlay {
                        ArchiveChartScrubber(zoom: zoom, maximumZoom: 3, onScrub: { fraction in
                            selectedOffset = viewport.value(at: fraction)
                        }, onZoom: { value in
                            if zoom == 1 { viewCenter = selectedPoint?.offset ?? 0 }
                            zoom = value
                        })
                        .padding(.horizontal, 6)
                        .accessibilityHidden(true)
                    }
            }
            .frame(height: compact ? (dynamicTypeSize.isAccessibilitySize ? 88 : 64)
                          : (dynamicTypeSize.isAccessibilitySize ? 144 : 116))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy("archive.reading.elevation"))
            .accessibilityValue(sampleDescription)
            .accessibilityAdjustableAction { direction in
                selectedOffset = min(180, max(-180, (selectedPoint?.offset ?? 0)
                                               + (direction == .increment ? 20 : -20)))
                if let selectedOffset, !viewport.visibleRange.contains(selectedOffset) {
                    viewCenter = selectedOffset
                }
            }
            .accessibilityAction(named: Text(copy("archive.chart.zoom_in"))) { setZoom(zoom * 1.5) }
            .accessibilityAction(named: Text(copy("archive.chart.zoom_out"))) { setZoom(zoom / 1.5) }
            .accessibilityAction(named: Text(copy("archive.chart.reset")), reset)

            HStack {
                Text(offsetText(range.lowerBound))
                Spacer(minLength: 8)
                Text(copy(selectedPoint == nil ? "archive.reading.observation" : "archive.chart.sample"))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                Text(offsetText(range.upperBound))
            }
            .font(Typography.statusTag)
            .foregroundStyle(Palette.Text.tertiary)
            .padding(.leading, axisWidth + 10)
            if let point = selectedPoint {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { sampleTime(point); sampleValues(point) }
                    VStack(alignment: .leading, spacing: 4) { sampleTime(point); sampleValues(point) }
                }
                .font(Typography.statusTag)
                .foregroundStyle(Palette.Text.primary)
            }
            if !compact {
                ArchiveChartTools(zoom: zoom, hasSelection: selectedOffset != nil, onReset: reset)
                Text(copy("archive.reading.sample_note"))
                    .font(Typography.readingCompact)
                    .foregroundStyle(Palette.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: trace.objectID) { _, _ in reset() }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--previewChartSelection") {
                selectedOffset = 60
                viewCenter = 60
                zoom = 2
            }
        }
        #endif
    }

    private var timestamp: some View {
        Text(trace.referenceDate, format: .dateTime.hour().minute().second()).monospacedDigit()
    }
    private func sampleTime(_ point: TrackSampler.TrackPoint) -> some View {
        Text(trace.referenceDate.addingTimeInterval(point.offset), format: .dateTime.hour().minute().second())
            .monospacedDigit()
    }
    private func sampleValues(_ point: TrackSampler.TrackPoint) -> some View {
        Text(String(format: "EL %+.1f°  ·  AZ %03.0f°", point.elevation * 180 / .pi,
                    (point.azimuth * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)))
    }
    private var sampleDescription: String {
        let point = selectedPoint ?? ArchiveChartSelection.nearestSample(in: trace, offset: 0)
        guard let point else { return "—" }
        return trace.referenceDate.addingTimeInterval(point.offset).formatted(date: .omitted, time: .standard)
            + String(format: ", EL %+.1f°, AZ %.1f°", point.elevation * 180 / .pi, point.azimuth * 180 / .pi)
    }
    private func reset() { selectedOffset = nil; zoom = 1; viewCenter = 0 }
    private func setZoom(_ value: Double) {
        if zoom == 1 { viewCenter = selectedPoint?.offset ?? 0 }
        zoom = min(3, max(1, value))
    }
    private func degreeLabel(_ value: Double) -> some View {
        Text(String(format: "%+.0f°", value)).font(Typography.statusTag)
            .foregroundStyle(Palette.Text.tertiary).fixedSize()
    }
    private func offsetText(_ value: Double) -> String {
        value == 0 ? "0" : String(format: "%+.1f MIN", value / 60)
    }

    private func plot(points: [TrackSampler.TrackPoint], bounds: ClosedRange<Double>,
                      range: ClosedRange<Double>) -> some View {
        Canvas { context, size in
            let inset: CGFloat = 6
            let width = size.width - inset * 2
            let height = size.height - inset * 2
            func x(_ offset: Double) -> CGFloat {
                inset + width * (offset - range.lowerBound) / (range.upperBound - range.lowerBound)
            }
            func y(_ elevation: Double) -> CGFloat {
                inset + height * (1 - (elevation - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
            }
            for column in 0...18 {
                for row in 0...6 {
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
            if range.contains(0) {
                var observation = Path()
                observation.move(to: CGPoint(x: x(0), y: 0))
                observation.addLine(to: CGPoint(x: x(0), y: size.height))
                context.stroke(observation, with: .color(tint.opacity(0.4)), lineWidth: 0.7)
            }
            for point in points {
                let center = CGPoint(x: x(point.offset), y: y(point.elevation * 180 / .pi))
                let current = abs(point.offset) < 0.01
                let color = point.offset < 0 ? Palette.Text.primary : tint
                var stem = Path()
                stem.move(to: CGPoint(x: center.x, y: center.y + 5))
                stem.addLine(to: CGPoint(x: center.x, y: size.height - inset))
                context.stroke(stem, with: .color(color.opacity(0.16)),
                               style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                let radius: CGFloat = current ? (compact ? 3.2 : 4) : (compact ? 2 : 2.7)
                let marker = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2))
                context.fill(marker, with: .color(point.offset <= 0 ? color : Palette.voidBlack))
                if point.offset > 0 { context.stroke(marker, with: .color(tint), lineWidth: 1.3) }
                if current {
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)),
                                   with: .color(tint.opacity(0.5)), lineWidth: 0.7)
                }
            }
            if let point = selectedPoint, range.contains(point.offset) {
                let center = CGPoint(x: x(point.offset), y: y(point.elevation * 180 / .pi))
                var cursor = Path()
                cursor.move(to: CGPoint(x: center.x, y: 0))
                cursor.addLine(to: CGPoint(x: center.x, y: size.height))
                context.stroke(cursor, with: .color(Palette.signal),
                               style: StrokeStyle(lineWidth: 0.9, dash: [3,3]))
                context.stroke(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)),
                               with: .color(Palette.signal), lineWidth: 1.4)
            }
        }
    }
}


/// Consistent numerical hierarchy across the locked card and full archive.
struct SatelliteReadout: View {
    let value: String
    let unit: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                number
                suffix
            }
            VStack(alignment: .leading, spacing: 4) {
                number
                suffix
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var number: some View {
        Text(value)
            .font(Typography.dataValue.weight(.medium))
            .foregroundStyle(Palette.Text.primary)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var suffix: some View {
        if !unit.isEmpty {
            Text(unit)
                .font(Typography.statusTag)
                .foregroundStyle(Palette.Text.tertiary)
        }
    }
}
