import SwiftUI

/// Geometry shared by the exploration rail, utility panels and the time instrument.
enum DockMorphMetrics {
    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    static func phase(_ progress: Double, from start: Double, to end: Double) -> Double {
        clamp((progress - start) / (end - start))
    }

    static func panelHeight(bottom: CGFloat, top: CGFloat) -> CGFloat {
        max(AppChromeMetrics.commandRailHeight, (bottom - top) * 0.84)
    }

    static func height(progress: Double, target: CGFloat) -> CGFloat {
        AppChromeMetrics.commandRailHeight
            + (target - AppChromeMetrics.commandRailHeight) * clamp(progress)
    }

    static func headerReveal(_ progress: Double) -> Double {
        phase(progress, from: 0.22, to: 0.65)
    }

    static func contentReveal(_ progress: Double) -> Double {
        phase(progress, from: 0.32, to: 0.92)
    }

    static func timelineReveal(_ progress: Double) -> Double {
        phase(progress, from: 0.58, to: 1)
    }

    static func commandsPresence(_ progress: Double) -> Double {
        1 - phase(progress, from: 0, to: 0.28)
    }

    static func shouldDismiss(translation: CGSize, predicted: CGSize) -> Bool {
        translation.height > 36
            && translation.height > abs(translation.width) * 1.5
            && (translation.height > 72 || predicted.height > 140)
    }

    static func duration(expanding: Bool, reduced: Bool) -> TimeInterval {
        reduced ? 0.14 : (expanding ? 0.48 : 0.32)
    }

    static func animation(expanding: Bool, reduced: Bool) -> Animation {
        if reduced { return .easeOut(duration: 0.14) }
        return .timingCurve(0.18, 0.76, 0.2, 1, duration: duration(expanding: expanding, reduced: false))
    }
}

/// Cancellation generations prevent an old animation callback from closing a newer panel.
struct UtilityPanelLifecycle {
    enum Phase { case hidden, opening, open, closing }
    private(set) var phase: Phase = .hidden
    private(set) var generation = 0

    mutating func begin(expanding: Bool) -> Int {
        generation += 1
        phase = expanding ? .opening : .closing
        return generation
    }

    @discardableResult
    mutating func complete(generation expected: Int) -> Bool {
        guard generation == expected else { return false }
        if phase == .opening { phase = .open }
        else if phase == .closing { phase = .hidden }
        return true
    }

    mutating func settle() {
        generation += 1
        if phase == .opening { phase = .open }
        else if phase == .closing { phase = .hidden }
    }

    mutating func reset() {
        generation += 1
        phase = .hidden
    }
}

struct CommandDockFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 { value = next }
    }
}

private struct UtilityPanelProgressKey: EnvironmentKey { static let defaultValue = 1.0 }
extension EnvironmentValues {
    var utilityPanelProgress: Double {
        get { self[UtilityPanelProgressKey.self] }
        set { self[UtilityPanelProgressKey.self] = newValue }
    }
}

/// One continuous surface, with identical fallback rules on every supported OS.
struct DockSurface: ViewModifier {
    var panelBlend: Double = 0
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.chromePreviewReducedTransparency) private var previewReduceTransparency
    @Environment(\.forceLegacyMaterial) private var forceLegacyMaterial
    private var reduceTransparency: Bool { systemReduceTransparency || previewReduceTransparency }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppChromeMetrics.commandRailCornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        surface(content)
            .overlay { shape.stroke(Palette.inkFaint.opacity(reduceTransparency ? 0.56 : 0.34), lineWidth: 0.6) }
            .clipShape(shape)
    }

    @ViewBuilder private func surface(_ content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency, !forceLegacyMaterial {
            content
                .background(Palette.sheetBackground.opacity(panelBlend))
                .glassEffect(.regular.tint(Palette.voidBlack.opacity(0.1)).interactive(), in: shape)
        } else if reduceTransparency {
            content.background(Palette.sheetBackground.opacity(panelBlend), in: shape)
                .background(Palette.voidBlack.opacity(0.97), in: shape)
        } else {
            content.background(Palette.sheetBackground.opacity(panelBlend), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .background(Palette.voidBlack.opacity(0.76), in: shape)
        }
    }
}

/// The body receives interpolated progress, so reveal phases follow geometry rather than timers.
struct UtilityPanelContainer<Content: View>: View, Animatable {
    var progress: Double
    let source: CGRect
    let top: CGFloat
    let reducedMotion: Bool
    let interactive: Bool
    let filtersActive: Bool
    let showsCommands: Bool
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let targetHeight = DockMorphMetrics.panelHeight(bottom: source.maxY, top: top)
        let height = reducedMotion ? targetHeight : DockMorphMetrics.height(progress: progress, target: targetHeight)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.18 * progress)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: source.width, height: height)
                .modifier(DockSurface(panelBlend: progress))
                .overlay(alignment: .top) {
                    content()
                        .environment(\.utilityPanelProgress, reducedMotion ? 1 : progress)
                        .frame(width: source.width, height: targetHeight)
                        // NavigationStack owns a UIKit background too; fade the entire
                        // content layer so it cannot leave a black slab over the source rail.
                        .opacity(reducedMotion ? 1 : DockMorphMetrics.headerReveal(progress))
                }
                .overlay(alignment: .bottom) {
                    if showsCommands {
                        SkyCommandRow(configuration: SkyCommandConfiguration(
                            items: SkyCommandItem.allCases,
                            activeItems: filtersActive ? [.filters] : []
                        ))
                        .frame(height: AppChromeMetrics.commandRailHeight)
                        .opacity(DockMorphMetrics.commandsPresence(progress))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .opacity(reducedMotion ? progress : 1)
                .position(x: source.midX, y: source.maxY - height / 2)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, onDismiss)
        }
        .allowsHitTesting(interactive)
    }
}
