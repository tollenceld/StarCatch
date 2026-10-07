import SwiftUI

/// Stable actions; the center compass is a camera action, never a page destination.
enum SkyCommandItem: String, CaseIterable, Identifiable, Hashable {
    case filters, observations, global, settings
    var id: String { rawValue }
    var group: SkyCommandGroup {
        switch self {
        case .filters, .observations: .left
        case .global, .settings: .right
        }
    }
    var symbol: String {
        switch self {
        case .filters: "line.3.horizontal.decrease"
        case .observations: "tray.full"
        case .global: "globe.asia.australia"
        case .settings: "gearshape"
        }
    }
    var accessibilityLabel: String {
        switch self {
        case .filters: L10n.text("filter.title")
        case .observations: L10n.text("navigation.observations")
        case .global: L10n.text("overview.entry.title")
        case .settings: L10n.text("settings.open.accessibility")
        }
    }
}

enum SkyCommandGroup: String, CaseIterable, Hashable {
    case left, right
    var items: [SkyCommandItem] {
        self == .left ? [.filters, .observations] : [.global, .settings]
    }
    var glassID: String { "sky-command-\(rawValue)" }
}

struct SkyCommandConfiguration: Equatable {
    let items: [SkyCommandItem]
    /// Persistent feature flags (filter badge); selection belongs to the presented page.
    let activeItems: Set<SkyCommandItem>

    nonisolated static func resolve(state: SkyChromeState, filtersActive: Bool,
                                    globalEntryEmphasized: Bool) -> SkyCommandConfiguration? {
        guard state.dockMode == .exploration else { return nil }
        var active: Set<SkyCommandItem> = []
        if filtersActive { active.insert(.filters) }
        if globalEntryEmphasized { active.insert(.global) }
        return Self(items: SkyCommandItem.allCases, activeItems: active)
    }
}

struct SkyCommandDock: View, Animatable {
    let state: SkyChromeState
    let filtersActive: Bool
    let globalEntryEmphasized: Bool
    let onOpenFilters: () -> Void
    let onOpenObservations: () -> Void
    let onEnterGlobal: () -> Void
    let onOpenSettings: () -> Void
    var onRecenter: () -> Void = {}
    var followsDevice = false
    var showsSurface = true
    var presentedItem: SkyCommandItem? = nil
    var panelProgress = 0.0
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.chromePreviewReducedMotion) private var previewReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    var animatableData: Double {
        get { panelProgress }
        set { panelProgress = newValue }
    }
    private var remainingPresence: Double {
        reducedMotion || systemReducedMotion || previewReducedMotion
            ? 1 - panelProgress : DockMorphMetrics.commandsPresence(panelProgress)
    }
    var body: some View {
        Group {
            if let configuration = SkyCommandConfiguration.resolve(
                state: state, filtersActive: filtersActive,
                globalEntryEmphasized: globalEntryEmphasized
            ), showsSurface || presentedItem != nil {
                HStack(alignment: .bottom, spacing: AppChromeMetrics.commandGroupSpacing) {
                    remainingCapsule(.left, configuration: configuration)
                    if showsSurface || remainingPresence > 0 {
                        recenter.opacity(showsSurface ? 1 : remainingPresence)
                    } else {
                        Color.clear.frame(width: AppChromeMetrics.recenterDiameter,
                                          height: AppChromeMetrics.recenterDiameter)
                    }
                    remainingCapsule(.right, configuration: configuration)
                }
                // These values already come from the interpolated geometry clock.
                // A second implicit opacity animation would leave controls behind the panel.
                .transaction { $0.animation = nil }
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
        .frame(height: AppChromeMetrics.recenterDiameter)
    }

    @ViewBuilder private func remainingCapsule(_ group: SkyCommandGroup,
                                               configuration: SkyCommandConfiguration) -> some View {
        if !showsSurface, presentedItem?.group == group || remainingPresence <= 0 {
            Color.clear.frame(maxWidth: .infinity).frame(height: AppChromeMetrics.commandRailHeight)
        } else {
            capsule(group, configuration: configuration)
                .opacity(showsSurface ? 1 : remainingPresence)
        }
    }

    private func capsule(_ group: SkyCommandGroup,
                         configuration: SkyCommandConfiguration) -> some View {
        SkyCommandRow(configuration: SkyCommandConfiguration(
            items: group.items, activeItems: configuration.activeItems
        ), onSelect: perform)
        .frame(maxWidth: .infinity)
        .frame(height: AppChromeMetrics.commandRailHeight)
        .modifier(SkyGlassSurface(shape: Capsule(), glassID: group.glassID))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: CommandCapsuleFrameKey.self,
                                       value: [group: geometry.frame(in: .named("appChrome"))])
            }
        }
    }

    private var recenter: some View {
        Button(action: onRecenter) {
            CompassGlyph()
                .foregroundStyle(Palette.Text.primary)
                .frame(width: AppChromeMetrics.recenterDiameter,
                       height: AppChromeMetrics.recenterDiameter)
                .background {
                    Circle().fill(Palette.glassLight.opacity(followsDevice ? 0.12 : 0.025))
                }
                .modifier(SkyGlassSurface(shape: Circle(), glassID: "sky-recenter"))
                .contentShape(Circle())
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(L10n.text("view.reset"))
        .accessibilityHint(L10n.text("view.recenter.hint"))
        .accessibilityValue(L10n.text(followsDevice ? "view.recenter.following" : "view.recenter.browsing"))
    }

    private func perform(_ item: SkyCommandItem) {
        switch item {
        case .filters: onOpenFilters()
        case .observations: onOpenObservations()
        case .global: onEnterGlobal()
        case .settings: onOpenSettings()
        }
    }
}

/// The same two-slot content is retained at the origin during panel / dial growth.
struct SkyCommandRow: View {
    let configuration: SkyCommandConfiguration
    var selectedItem: SkyCommandItem? = nil
    var onSelect: (SkyCommandItem) -> Void = { _ in }
    @GestureState private var pressed: SkyCommandItem?
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.chromePreviewReducedMotion) private var previewReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    private var suppressMotion: Bool { reducedMotion || systemReducedMotion || previewReducedMotion }
    private var selection: SkyCommandItem? { pressed ?? selectedItem }

    var body: some View {
        GeometryReader { geometry in
            let slotWidth = (geometry.size.width - 8) / CGFloat(max(1, configuration.items.count))
            ZStack(alignment: .leading) {
                if let selection, let index = configuration.items.firstIndex(of: selection) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Palette.glassLight.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Palette.glassLight.opacity(0.24), lineWidth: 0.6)
                        }
                        .frame(width: slotWidth, height: 48)
                        .offset(x: 4 + CGFloat(index) * slotWidth)
                        .transition(.opacity)
                }
                HStack(spacing: 0) {
                    ForEach(configuration.items) { item in
                        Button { onSelect(item) } label: {
                            Image(systemName: item.symbol)
                                .font(.system(size: 23, weight: .regular))
                                .foregroundStyle(Palette.Text.primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(alignment: .bottom) {
                                    if item == .filters, configuration.activeItems.contains(.filters) {
                                        Circle().fill(Palette.signal).frame(width: 4, height: 4)
                                            .padding(.bottom, 5)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(DragGesture(minimumDistance: 0)
                            .updating($pressed) { _, state, _ in state = item })
                        .accessibilityLabel(item.accessibilityLabel)
                        .accessibilityAddTraits(selection == item ? .isSelected : [])
                        .accessibilityValue(item == .filters && configuration.activeItems.contains(.filters)
                                            ? L10n.text("filter.title") : "")
                    }
                }
                .padding(4)
            }
            .animation(.easeOut(duration: suppressMotion ? 0.14 : 0.2), value: selection)
        }
    }
}

/// Drawn at its final size: radial marks, rounded ends and a clear north pointer.
private struct CompassGlyph: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var ticks = Path()
            for index in 0..<12 {
                let angle = Double(index) * .pi / 6 - .pi / 2
                let outer = 24.0
                let inner = index.isMultiple(of: 3) ? 19.0 : 21.0
                ticks.move(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
                ticks.addLine(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
            }
            context.stroke(ticks, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var arrow = Path()
            arrow.move(to: CGPoint(x: center.x, y: center.y - 13))
            arrow.addLine(to: CGPoint(x: center.x + 8, y: center.y + 10))
            arrow.addQuadCurve(to: CGPoint(x: center.x, y: center.y + 5),
                               control: CGPoint(x: center.x + 2, y: center.y + 8))
            arrow.addQuadCurve(to: CGPoint(x: center.x - 8, y: center.y + 10),
                               control: CGPoint(x: center.x - 2, y: center.y + 8))
            arrow.closeSubpath()
            context.fill(arrow, with: .foreground)
        }
        .accessibilityHidden(true)
    }
}
