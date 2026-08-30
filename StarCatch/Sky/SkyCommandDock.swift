import SwiftUI

/// 主天空与全局星图共用的一组空间控制。三个常驻入口使用同一尺寸、间距与材质；
/// 当前状态需要明确动作时，整组连续收束成中央主动作。
struct SkyCommandDock: View {
    let state: SkyChromeState
    let filtersActive: Bool
    let globalEntryEmphasized: Bool
    let onOpenFilters: () -> Void
    let onEnterGlobal: () -> Void
    let onToggleTime: () -> Void
    let onOpenSettings: () -> Void
    let onPrimaryAction: (SkyChromeState.PrimaryAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @Namespace private var dockNamespace

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: AppChromeMetrics.itemSpacing) {
                    dockContent
                }
            } else {
                dockContent
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppChromeMetrics.commandControlSize)
        .animation(dockAnimation, value: state.dockMode)
    }

    @ViewBuilder
    private var dockContent: some View {
        switch state.dockMode {
        case .exploration:
            HStack(spacing: AppChromeMetrics.itemSpacing) {
                iconButton(
                    id: "filters",
                    symbol: "line.3.horizontal.decrease",
                    accessibilityLabel: L10n.text("filter.title"),
                    active: filtersActive,
                    action: onOpenFilters
                )
                iconButton(
                    id: "center",
                    symbol: "globe.asia.australia",
                    accessibilityLabel: L10n.text("overview.entry.title"),
                    active: globalEntryEmphasized,
                    action: onEnterGlobal
                )
                iconButton(
                    id: "settings",
                    symbol: "slider.horizontal.3",
                    accessibilityLabel: L10n.text("settings.open.accessibility"),
                    action: onOpenSettings
                )
            }

        case .global:
            HStack(spacing: AppChromeMetrics.itemSpacing) {
                iconButton(
                    id: "filters",
                    symbol: "line.3.horizontal.decrease",
                    accessibilityLabel: L10n.text("filter.title"),
                    active: filtersActive,
                    action: onOpenFilters
                )
                iconButton(
                    id: "center",
                    symbol: "clock",
                    accessibilityLabel: L10n.text("time.accessibility.label"),
                    active: state.showsTimePanel || !state.isLive,
                    action: onToggleTime
                )
                iconButton(
                    id: "settings",
                    symbol: "slider.horizontal.3",
                    accessibilityLabel: L10n.text("settings.open.accessibility"),
                    action: onOpenSettings
                )
            }

        case .capture(let action):
            primaryAction(action)
                .matchedGeometryEffect(id: "center", in: dockNamespace)

        case .sensing, .targetSummary, .hidden:
            Color.clear
                .frame(height: AppChromeMetrics.commandControlSize)
                .accessibilityHidden(true)
        }
    }

    private func iconButton(
        id: String,
        symbol: String,
        accessibilityLabel: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        SkyDockIconButton(
            symbol: symbol,
            accessibilityLabel: accessibilityLabel,
            active: active,
            action: action
        )
        .matchedGeometryEffect(id: id, in: dockNamespace)
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

private struct SkyDockIconButton: View {
    let symbol: String
    let accessibilityLabel: String
    let active: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.forceLegacyMaterial) private var forceLegacyMaterial

    var body: some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency, !forceLegacyMaterial {
                button
                    .glassEffect(
                        .regular
                            .tint(active ? Palette.signal.opacity(0.08) : Palette.voidBlack.opacity(0.08))
                            .interactive(),
                        in: Circle()
                    )
            } else {
                fallbackButton
            }
        }
        .overlay {
            Circle()
                .stroke(
                    active ? Palette.signal.opacity(0.48) : Palette.inkFaint.opacity(0.34),
                    lineWidth: active ? 0.75 : AppChromeMetrics.strokeWidth
                )
        }
        .overlay(alignment: .bottom) {
            if active {
                Circle()
                    .fill(Palette.signal.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .offset(y: -6)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    (active ? Palette.signal : Palette.inkMid)
                        .opacity(active ? 0.92 : 0.86)
                )
                .frame(
                    width: AppChromeMetrics.commandControlSize,
                    height: AppChromeMetrics.commandControlSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(SkyCapsulePressStyle())
    }

    @ViewBuilder
    private var fallbackButton: some View {
        if reduceTransparency {
            button
                .background(Palette.voidBlack.opacity(0.96), in: Circle())
        } else {
            button
                .background(.ultraThinMaterial, in: Circle())
                .background(Palette.voidBlack.opacity(0.74), in: Circle())
        }
    }
}
