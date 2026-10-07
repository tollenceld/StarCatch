import SwiftUI

/// Measures the complete dial before interpolating the surface height. A preference
/// measured inside an already constrained frame can clip new hint / Dynamic Type rows.
private struct GlobalDockLayout: Layout {
    var progress: Double
    var reducedMotion: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let dial = subviews.first else { return .zero }
        let size = dial.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let target = max(AppChromeMetrics.commandRailHeight, size.height)
        let widthProgress = DockMorphMetrics.phase(progress, from: 0, to: 0.58)
        let sourceWidth = AppChromeMetrics.commandCapsuleWidth(in: size.width)
        return CGSize(
            width: reducedMotion ? size.width : sourceWidth + (size.width - sourceWidth) * widthProgress,
            height: reducedMotion ? target : DockMorphMetrics.height(progress: progress, target: target)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.maxY),
                anchor: .bottomLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
        }
    }
}

/// Only the bottom control changes shape; the globe uses its untouched scene choreography.
struct GlobalDockMorph: View, Animatable {
    var progress: Double
    let reducedMotion: Bool
    let interactive: Bool
    let clock: SkyClock
    let filtersActive: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GlobalDockLayout(progress: progress, reducedMotion: reducedMotion) {
            TimeDial(clock: clock, showsSurface: false)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(DockMorphMetrics.timelineReveal(progress))
                .offset(y: reducedMotion ? 0 : 8 * (1 - DockMorphMetrics.timelineReveal(progress)))
                .allowsHitTesting(interactive)
                .accessibilityHidden(!interactive)

            SkyCommandRow(configuration: SkyCommandConfiguration(
                items: SkyCommandGroup.right.items,
                activeItems: []
            ), selectedItem: .global)
            .frame(height: AppChromeMetrics.commandRailHeight)
            .opacity(DockMorphMetrics.commandsPresence(progress))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .modifier(DockSurface(navigationPresence: 1 - progress, timelinePresence: progress,
                              glassID: SkyCommandGroup.right.glassID))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
