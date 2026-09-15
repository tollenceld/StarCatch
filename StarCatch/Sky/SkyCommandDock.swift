import SwiftUI

/// 底部控制栏中的稳定功能位置。它只描述 UI 入口，不保存筛选、时间或页面状态。
enum SkyCommandItem: String, CaseIterable, Identifiable, Hashable {
    case filters
    case observations
    case global
    case settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .filters: "line.3.horizontal.decrease"
        case .observations: "tray.full"
        case .global: "globe.asia.australia"
        case .settings: "slider.horizontal.3"
        }
    }

    var shortLabel: String {
        switch self {
        case .filters: L10n.text("sky.command.filters")
        case .observations: L10n.text("sky.command.observations")
        case .global: L10n.text("sky.command.global")
        case .settings: L10n.text("sky.command.settings")
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

/// 从主天空 Chrome 推导出的纯值布局。全球轨道页拥有独立时间轴，不复用此栏。
struct SkyCommandConfiguration: Equatable {
    let items: [SkyCommandItem]
    let activeItems: Set<SkyCommandItem>

    nonisolated static func resolve(
        state: SkyChromeState,
        filtersActive: Bool,
        globalEntryEmphasized: Bool
    ) -> SkyCommandConfiguration? {
        switch state.dockMode {
        case .exploration:
            var activeItems: Set<SkyCommandItem> = []
            if filtersActive { activeItems.insert(.filters) }
            if globalEntryEmphasized { activeItems.insert(.global) }
            return SkyCommandConfiguration(
                items: [.filters, .observations, .global, .settings],
                activeItems: activeItems
            )

        case .sensing, .targetSummary, .hidden:
            return nil
        }
    }
}

/// 主天空专用的四槽控制基座。全球轨道页使用独立的常驻时间轴。
struct SkyCommandDock: View {
    let state: SkyChromeState
    let filtersActive: Bool
    let globalEntryEmphasized: Bool
    let onOpenFilters: () -> Void
    let onOpenObservations: () -> Void
    let onEnterGlobal: () -> Void
    let onOpenSettings: () -> Void
    var showsSurface = true

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @Namespace private var dockNamespace

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }

    private var configuration: SkyCommandConfiguration? {
        SkyCommandConfiguration.resolve(
            state: state,
            filtersActive: filtersActive,
            globalEntryEmphasized: globalEntryEmphasized
        )
    }

    var body: some View {
        Group {
            if let configuration {
                commandSurface(configuration)
                    .matchedGeometryEffect(id: "command-surface", in: dockNamespace)
            } else {
                Color.clear
                    .frame(height: AppChromeMetrics.commandRailHeight)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppChromeMetrics.commandRailHeight)
        .animation(dockAnimation, value: state.dockMode)
        .animation(dockAnimation, value: configuration?.activeItems)
        .opacity(showsSurface ? 1 : 0)
    }

    @ViewBuilder
    private func commandSurface(_ configuration: SkyCommandConfiguration) -> some View {
        commandRow(configuration)
            .frame(height: AppChromeMetrics.commandRailHeight)
            .modifier(DockSurface())
    }

    private func commandRow(_ configuration: SkyCommandConfiguration) -> some View {
        SkyCommandRow(configuration: configuration, onSelect: perform)
    }

    private func perform(_ item: SkyCommandItem) {
        switch item {
        case .filters: onOpenFilters()
        case .observations: onOpenObservations()
        case .global: onEnterGlobal()
        case .settings: onOpenSettings()
        }
    }

    private var dockAnimation: Animation {
        if suppressMotion {
            return .easeOut(
                duration: Motion.interfaceDuration(
                    expanding: false,
                    reduced: true
                )
            )
        }
        switch state.dockMode {
        case .exploration:
            return Motion.interfaceExpand
        case .sensing, .targetSummary, .hidden:
            return Motion.interfaceCollapse
        }
    }
}

/// Surface-free content can crossfade inside the same growing rail.
struct SkyCommandRow: View {
    let configuration: SkyCommandConfiguration
    var onSelect: (SkyCommandItem) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(configuration.items) { item in
                SkyCommandSlotButton(
                    item: item,
                    active: configuration.activeItems.contains(item),
                    action: { onSelect(item) }
                )
            }
        }
        .padding(4)
    }
}

private struct SkyCommandSlotButton: View {
    let item: SkyCommandItem
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .vertical) {
                VStack(spacing: 4) {
                    icon
                    Text(item.shortLabel)
                        .font(Typography.statusTag)
                        .tracking(0.35)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                icon
            }
            .foregroundStyle(
                (active ? Palette.signal : Palette.inkMid)
                    .opacity(active ? 0.96 : 0.84)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.signal.opacity(0.075))
                }
            }
            .overlay(alignment: .bottom) {
                if active {
                    Capsule()
                        .fill(Palette.signal.opacity(0.9))
                        .frame(width: 12, height: 2)
                        .padding(.bottom, 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var icon: some View {
        Image(systemName: item.symbol)
            .font(.system(size: 14, weight: .medium))
            .frame(minWidth: 24, minHeight: 18)
    }
}
