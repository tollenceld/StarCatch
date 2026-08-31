import SwiftUI

/// 底部控制栏中的稳定功能位置。它只描述 UI 入口，不保存筛选、时间或页面状态。
enum SkyCommandItem: String, CaseIterable, Identifiable, Hashable {
    case filters
    case observations
    case global
    case time
    case settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .filters: "line.3.horizontal.decrease"
        case .observations: "tray.full"
        case .global: "globe.asia.australia"
        case .time: "clock"
        case .settings: "slider.horizontal.3"
        }
    }

    var shortLabel: String {
        switch self {
        case .filters: L10n.text("sky.command.filters")
        case .observations: L10n.text("sky.command.observations")
        case .global: L10n.text("sky.command.global")
        case .time: L10n.text("sky.command.time")
        case .settings: L10n.text("sky.command.settings")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .filters: L10n.text("filter.title")
        case .observations: L10n.text("navigation.observations")
        case .global: L10n.text("overview.entry.title")
        case .time: L10n.text("time.accessibility.label")
        case .settings: L10n.text("settings.open.accessibility")
        }
    }
}

/// 从现有天空 Chrome 推导出的纯值布局。按钮可见性、激活语义和全球遥测都在
/// 一处解析，View 不再分别猜测当前应该显示哪一组入口。
struct SkyCommandConfiguration: Equatable {
    let items: [SkyCommandItem]
    let activeItems: Set<SkyCommandItem>
    let displayedCount: Int?
    let catalogCount: Int?
    let showsGlobalReset: Bool
    let showsReturnToLive: Bool

    var isGlobal: Bool { displayedCount != nil && catalogCount != nil }

    nonisolated static func resolve(
        state: SkyChromeState,
        filtersActive: Bool,
        globalEntryEmphasized: Bool,
        displayedCount: Int,
        catalogCount: Int
    ) -> SkyCommandConfiguration? {
        switch state.dockMode {
        case .exploration:
            var activeItems: Set<SkyCommandItem> = []
            if filtersActive { activeItems.insert(.filters) }
            if globalEntryEmphasized { activeItems.insert(.global) }
            return SkyCommandConfiguration(
                items: [.filters, .observations, .global, .settings],
                activeItems: activeItems,
                displayedCount: nil,
                catalogCount: nil,
                showsGlobalReset: false,
                showsReturnToLive: false
            )

        case .global:
            var activeItems: Set<SkyCommandItem> = []
            if filtersActive { activeItems.insert(.filters) }
            if state.showsTimePanel || !state.isLive { activeItems.insert(.time) }
            return SkyCommandConfiguration(
                items: [.filters, .observations, .time, .settings],
                activeItems: activeItems,
                displayedCount: displayedCount,
                catalogCount: catalogCount,
                showsGlobalReset: state.resetAction == .globalField,
                showsReturnToLive: !state.isLive
            )

        case .sensing, .capture, .targetSummary, .hidden:
            return nil
        }
    }
}

/// 主天空和全球轨道共用的底部控制基座。本地为四槽导航栏；进入全球后同一
/// 基座向上扩展出目录遥测，不再退化成三枚悬空圆钮。
struct SkyCommandDock: View {
    let state: SkyChromeState
    let filtersActive: Bool
    let globalEntryEmphasized: Bool
    let overviewDisplayedCount: Int
    let overviewCatalogCount: Int
    let onOpenFilters: () -> Void
    let onOpenObservations: () -> Void
    let onEnterGlobal: () -> Void
    let onToggleTime: () -> Void
    let onOpenSettings: () -> Void
    let onResetGlobal: () -> Void
    let onReturnToLive: () -> Void
    let onPrimaryAction: (SkyChromeState.PrimaryAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.forceLegacyMaterial) private var forceLegacyMaterial
    @AppStorage("reducedMotion") private var reducedMotion = false
    @Namespace private var dockNamespace

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }

    private var configuration: SkyCommandConfiguration? {
        SkyCommandConfiguration.resolve(
            state: state,
            filtersActive: filtersActive,
            globalEntryEmphasized: globalEntryEmphasized,
            displayedCount: overviewDisplayedCount,
            catalogCount: overviewCatalogCount
        )
    }

    private var dockHeight: CGFloat {
        configuration?.isGlobal == true
            ? AppChromeMetrics.globalConsoleHeight
            : AppChromeMetrics.commandRailHeight
    }

    private var surfaceMode: AppChromeSurfaceMode {
        if #available(iOS 26.0, *) {
            return .resolve(
                liquidGlassAvailable: true,
                reduceTransparency: reduceTransparency,
                forceLegacyMaterial: forceLegacyMaterial
            )
        }
        return .resolve(
            liquidGlassAvailable: false,
            reduceTransparency: reduceTransparency,
            forceLegacyMaterial: forceLegacyMaterial
        )
    }

    var body: some View {
        Group {
            if let configuration {
                commandSurface(configuration)
                    .matchedGeometryEffect(id: "command-surface", in: dockNamespace)
            } else {
                switch state.dockMode {
                case .capture(let action):
                    primaryAction(action)
                        .matchedGeometryEffect(id: "command-surface", in: dockNamespace)
                case .exploration, .global, .sensing, .targetSummary, .hidden:
                    Color.clear
                        .frame(height: AppChromeMetrics.commandRailHeight)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: dockHeight)
        .animation(dockAnimation, value: state.dockMode)
        .animation(dockAnimation, value: configuration?.activeItems)
    }

    @ViewBuilder
    private func commandSurface(_ configuration: SkyCommandConfiguration) -> some View {
        let shape = commandShape
        if #available(iOS 26.0, *), surfaceMode == .liquidGlass {
            GlassEffectContainer(spacing: 0) {
                commandContent(configuration)
                    .glassEffect(
                        .regular
                            .tint(Palette.voidBlack.opacity(0.1))
                            .interactive(),
                        in: shape
                    )
                    .glassEffectID("command-surface", in: dockNamespace)
            }
        } else {
            fallbackSurface(configuration, shape: shape)
        }
    }

    @ViewBuilder
    private func fallbackSurface(
        _ configuration: SkyCommandConfiguration,
        shape: RoundedRectangle
    ) -> some View {
        if surfaceMode == .opaque {
            commandContent(configuration)
                .background(Palette.voidBlack.opacity(0.97), in: shape)
        } else {
            commandContent(configuration)
                .background(.ultraThinMaterial, in: shape)
                .background(Palette.voidBlack.opacity(0.76), in: shape)
        }
    }

    private func commandContent(_ configuration: SkyCommandConfiguration) -> some View {
        VStack(spacing: 0) {
            if configuration.isGlobal {
                globalTelemetry(configuration)
                    .frame(height: 39)

                Rectangle()
                    .fill(Palette.inkFaint.opacity(0.28))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
            }

            commandRow(configuration)
                .frame(height: AppChromeMetrics.commandRailHeight)
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: configuration.isGlobal
                ? AppChromeMetrics.globalConsoleHeight
                : AppChromeMetrics.commandRailHeight
        )
        .overlay {
            commandShape.stroke(
                Palette.inkFaint.opacity(reduceTransparency ? 0.56 : 0.34),
                lineWidth: 0.6
            )
        }
        .clipShape(commandShape)
    }

    private func commandRow(_ configuration: SkyCommandConfiguration) -> some View {
        HStack(spacing: 2) {
            ForEach(configuration.items) { item in
                SkyCommandSlotButton(
                    item: item,
                    active: configuration.activeItems.contains(item),
                    action: { perform(item) }
                )
                .matchedGeometryEffect(id: item.id, in: dockNamespace)
            }
        }
        .padding(4)
    }

    private func globalTelemetry(_ configuration: SkyCommandConfiguration) -> some View {
        HStack(spacing: 4) {
            Text(
                L10n.format(
                    "overview.counts",
                    configuration.displayedCount ?? 0,
                    configuration.catalogCount ?? 0
                )
            )
            .font(Typography.statusTag)
            .tracking(Typography.statusTagTracking)
            .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            Spacer(minLength: 4)

            if configuration.showsReturnToLive {
                telemetryButton(
                    title: L10n.text("time.return_now"),
                    symbol: "arrow.counterclockwise",
                    action: onReturnToLive
                )
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Palette.signal.opacity(0.78))
                        .frame(width: 4, height: 4)
                    Text("LIVE")
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 32)
                .accessibilityElement(children: .combine)
            }

            if configuration.showsGlobalReset {
                Button(action: onResetGlobal) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.signal.opacity(0.86))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SkyCapsulePressStyle())
                .accessibilityLabel(L10n.text("view.reset"))
                .accessibilityHint(L10n.text("view.reset.hint"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
    }

    private func telemetryButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 9.5, weight: .medium, design: .default))
                .foregroundStyle(Palette.signal.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(title)
    }

    private func perform(_ item: SkyCommandItem) {
        switch item {
        case .filters: onOpenFilters()
        case .observations: onOpenObservations()
        case .global: onEnterGlobal()
        case .time: onToggleTime()
        case .settings: onOpenSettings()
        }
    }

    @ViewBuilder
    private func primaryAction(_ action: SkyChromeState.PrimaryAction) -> some View {
        switch action {
        case .confirm(let progress):
            FocusActionControl(mode: .confirm(progress: progress)) {
                onPrimaryAction(action)
            }
        case .replace(let progress):
            FocusActionControl(mode: .replace(progress: progress)) {
                onPrimaryAction(action)
            }
        case .release:
            CaptureSecondaryControl(mode: .cancelCapture) {
                onPrimaryAction(action)
            }
        case .releasing:
            CaptureSecondaryControl(mode: .cancelling) {}
        }
    }

    private var commandShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: AppChromeMetrics.commandRailCornerRadius,
            style: .continuous
        )
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
        case .exploration, .global:
            return Motion.interfaceExpand
        case .sensing, .capture, .targetSummary, .hidden:
            return Motion.interfaceCollapse
        }
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
