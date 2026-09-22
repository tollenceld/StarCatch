import SwiftUI

private struct TimeDialHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 89
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Only the bottom control changes shape; the globe uses its untouched scene choreography.
struct GlobalDockMorph: View, Animatable {
    var progress: Double
    let reducedMotion: Bool
    let interactive: Bool
    let clock: SkyClock
    let filtersActive: Bool
    @State private var dialHeight: CGFloat = 89

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let height = reducedMotion ? dialHeight : DockMorphMetrics.height(progress: progress, target: dialHeight)
        ZStack(alignment: .bottom) {
            TimeDial(clock: clock, showsSurface: false)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: TimeDialHeightKey.self, value: geometry.size.height)
                    }
                }
                .opacity(DockMorphMetrics.timelineReveal(progress))
                .offset(y: reducedMotion ? 0 : 8 * (1 - DockMorphMetrics.timelineReveal(progress)))
                .allowsHitTesting(interactive)
                .accessibilityHidden(!interactive)

            SkyCommandRow(configuration: SkyCommandConfiguration(
                items: SkyCommandItem.allCases,
                activeItems: filtersActive ? [.filters] : []
            ))
            .frame(height: AppChromeMetrics.commandRailHeight)
            .opacity(DockMorphMetrics.commandsPresence(progress))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: height, alignment: .bottom)
        .modifier(DockSurface(navigationPresence: 1 - progress))
        .onPreferenceChange(TimeDialHeightKey.self) { dialHeight = max(AppChromeMetrics.commandRailHeight, $0) }
    }
}
