import SwiftUI
import UIKit

/// Clamped time windows only change the presentation of an immutable snapshot.
struct ArchiveChartViewport {
    let extent: ClosedRange<Double>
    let minimumSpan: Double
    var zoom = 1.0
    var center: Double? = nil

    var visibleRange: ClosedRange<Double> {
        let total = max(0, extent.upperBound - extent.lowerBound)
        guard total > 0 else { return extent }
        let safeZoom = zoom.isFinite ? max(1, zoom) : 1
        let span = max(min(total, minimumSpan), total / safeZoom)
        let middle = center.flatMap { $0.isFinite ? $0 : nil } ?? (extent.lowerBound + total / 2)
        let start = min(extent.upperBound - span, max(extent.lowerBound, middle - span / 2))
        return start...(start + span)
    }
    func value(at fraction: Double) -> Double {
        let range = visibleRange
        let fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0.5
        return range.lowerBound + (range.upperBound - range.lowerBound) * fraction
    }
}

enum ArchiveChartSelection {
    static func nearestSample(in trace: SatelliteTrackSnapshot, offset: Double) -> TrackSampler.TrackPoint? {
        trace.finitePoints.min { abs($0.offset-offset) < abs($1.offset-offset) }
    }
    static func nearestPass(in forecast: PassForecast, at date: Date) -> Int? {
        forecast.windows.indices.filter {
            guard let rise = forecast.windows[$0].rise, let set = forecast.windows[$0].set else { return false }
            return set > rise
        }.min { distance(to: forecast.windows[$0], date: date) < distance(to: forecast.windows[$1], date: date) }
    }
    private static func distance(to pass: PassWindow, date: Date) -> Double {
        guard let rise = pass.rise, let set = pass.set else { return .infinity }
        return max(0, max(rise.timeIntervalSince(date), date.timeIntervalSince(set)))
    }
}

enum ArchiveChartGesturePolicy {
    static func acceptsHorizontalDrag(velocity: CGPoint) -> Bool {
        velocity.x.isFinite && velocity.y.isFinite
            && abs(velocity.x) > abs(velocity.y) * 1.15
    }
}

/// A directional recognizer leaves vertical drags to the enclosing native ScrollView.
/// No clock mutation, propagation, file access or display link is performed here.
struct ArchiveChartScrubber: UIViewRepresentable {
    var zoom: Double
    var maximumZoom: Double = 8
    var onScrub: (Double) -> Void
    var onZoom: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.scrub(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pinch)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ArchiveChartScrubber
        private var pinchOrigin = 1.0
        init(_ parent: ArchiveChartScrubber) { self.parent = parent }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return ArchiveChartGesturePolicy.acceptsHorizontalDrag(velocity: velocity)
        }
        @objc func scrub(_ recognizer: UIPanGestureRecognizer) { select(recognizer) }
        @objc func tap(_ recognizer: UITapGestureRecognizer) { select(recognizer) }
        private func select(_ recognizer: UIGestureRecognizer) {
            guard let view = recognizer.view, view.bounds.width > 0 else { return }
            let fraction = Double(recognizer.location(in: view).x / view.bounds.width)
            parent.onScrub(min(1, max(0, fraction)))
        }
        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            if recognizer.state == .began { pinchOrigin = parent.zoom }
            let value = pinchOrigin * Double(recognizer.scale)
            guard value.isFinite else { return }
            parent.onZoom(min(parent.maximumZoom, max(1, value)))
        }
    }
}

struct ArchiveChartTools: View {
    let zoom: Double
    var hasSelection = false
    let onReset: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { hint; Spacer(minLength: 4); reset }
            VStack(alignment: .leading, spacing: 0) { hint; reset }
        }
        .font(Typography.statusTag)
    }
    private var hint: some View {
        Text(L10n.text("archive.chart.gesture", table: "SatelliteText"))
            .foregroundStyle(Palette.Text.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var reset: some View {
        Button {
            onReset()
        } label: {
            Text(L10n.text("archive.chart.reset", table: "SatelliteText"))
                .foregroundStyle(zoom > 1 || hasSelection ? Palette.signal : Palette.Text.secondary)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

/// Key event timing only. No elevation curve is inferred between rise, peak and set.
struct SatellitePassEventStrip: View {
    let pass: PassWindow
    let now: Date
    let tint: Color
    @State private var selectedOffset: Double?
    @State private var zoom = 1.0
    @State private var viewCenter: Double?

    private var duration: Double { pass.duration ?? 0 }
    private var viewport: ArchiveChartViewport {
        ArchiveChartViewport(extent: 0...max(1, duration), minimumSpan: min(60, max(1, duration)),
                             zoom: zoom, center: viewCenter)
    }
    private func copy(_ key: String) -> String { L10n.text(key, table: "SatelliteText") }

    var body: some View {
        if let rise = pass.rise, let set = pass.set, set > rise {
            let range = viewport.visibleRange
            VStack(alignment: .leading, spacing: 8) {
                Canvas { context, size in
                    let inset = 6.0
                    let middle = size.height / 2
                    func x(_ offset: Double) -> CGFloat {
                        inset + (size.width - 2 * inset) * (offset-range.lowerBound)
                            / (range.upperBound-range.lowerBound)
                    }
                    for index in 0...36 {
                        let offset = viewport.value(at: Double(index)/36)
                        let height: Double = index.isMultiple(of: 6) ? 16 : 6
                        var tick = Path()
                        tick.move(to: CGPoint(x: x(offset), y: middle - height / 2))
                        tick.addLine(to: CGPoint(x: x(offset), y: middle + height / 2))
                        context.stroke(tick, with: .color(Palette.Text.tertiary.opacity(0.5)), lineWidth: 0.8)
                    }
                    for date in [pass.rise, pass.peak, pass.set].compactMap({ $0 }) {
                        let offset = date.timeIntervalSince(rise)
                        guard range.contains(offset) else { continue }
                        let marker = Path(ellipseIn: CGRect(x: x(offset)-4, y: middle-4, width: 8, height: 8))
                        context.fill(marker, with: .color(date <= now ? Palette.Text.primary : Palette.sheetBackground))
                        context.stroke(marker, with: .color(tint), lineWidth: 1.2)
                    }
                    let offset = selectedOffset ?? now.timeIntervalSince(rise)
                    if range.contains(offset) {
                        var cursor = Path()
                        cursor.move(to: CGPoint(x: x(offset), y: 0))
                        cursor.addLine(to: CGPoint(x: x(offset), y: size.height))
                        context.stroke(cursor, with: .color(selectedOffset == nil ? Palette.Text.primary : Palette.signal),
                                       lineWidth: 1.2)
                    }
                }
                .frame(height: 60)
                .overlay {
                    ArchiveChartScrubber(zoom: zoom, onScrub: { selectedOffset = viewport.value(at: $0) },
                                         onZoom: { value in
                        if zoom == 1 { viewCenter = selectedOffset }
                        zoom = value
                    }).padding(.horizontal, 6).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(copy("archive.forecast.key_events"))
                .accessibilityValue(selectedOffset.map { rise.addingTimeInterval($0).formatted(date: .omitted, time: .standard) } ?? "—")
                .accessibilityAdjustableAction { direction in
                    selectedOffset = min(duration, max(0, (selectedOffset ?? 0)
                                                       + (direction == .increment ? 1 : -1) * duration / 36))
                }
                .accessibilityAction(named: Text(copy("archive.chart.zoom_in"))) { zoom = min(8, zoom * 2) }
                .accessibilityAction(named: Text(copy("archive.chart.zoom_out"))) { zoom = max(1, zoom / 2) }
                if let offset = selectedOffset {
                    let date = rise.addingTimeInterval(offset)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { cursorTime(date); phaseLabel(date) }
                        VStack(alignment: .leading, spacing: 4) { cursorTime(date); phaseLabel(date) }
                    }
                    .font(Typography.statusTag)
                    .foregroundStyle(Palette.signal)
                }
                ArchiveChartTools(zoom: zoom, hasSelection: selectedOffset != nil) {
                    selectedOffset = nil; zoom = 1; viewCenter = nil
                }
            }
        } else {
            Text(copy("archive.forecast.loading"))
                .font(Typography.readingCompact)
                .foregroundStyle(Palette.Text.tertiary)
        }
    }
    private func cursorTime(_ date: Date) -> some View {
        Text(date, format: .dateTime.hour().minute().second()).monospacedDigit()
    }
    @ViewBuilder private func phaseLabel(_ date: Date) -> some View {
        if let peak = pass.peak {
            let seconds = Int(abs(date.timeIntervalSince(peak)))
            Text(copy(date <= peak ? "archive.chart.event_before_peak" : "archive.chart.event_after_peak")
                 + String(format: " %02d:%02d", seconds / 60, seconds % 60))
        }
    }
}
