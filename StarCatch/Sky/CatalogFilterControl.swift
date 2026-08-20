import SwiftUI

/// 左下角的当前目标筛选入口。
///
/// 收起时只显示当前结果；展开时同一个玻璃外壳向上生长。显示范围为单选，
/// 任务、运营方和轨道网络为多选，并实时作用于天空。
struct CatalogFilterControl: View {
    static let collapsedSize: CGFloat = 128
    private static let collapsedHeight = AppChromeMetrics.controlHeight
    private static let expandedWidth: CGFloat = 328
    private static let outerCornerRadius = AppChromeMetrics.compactCornerRadius
    private static let innerCornerRadius: CGFloat = 9
    private static let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    private struct Section: Identifiable {
        let id: String
        let group: CatalogFilterGroup
        let label: String
        let filters: [CatalogFilter]
    }

    private static let sections: [Section] = [
        Section(
            id: CatalogFilterGroup.mission.id,
            group: .mission,
            label: L10n.text("filter.section.mission"),
            filters: CatalogFilterGroup.mission.filters
        ),
        Section(
            id: CatalogFilterGroup.authority.id,
            group: .authority,
            label: L10n.text("filter.section.operator"),
            filters: CatalogFilterGroup.authority.filters
        ),
        Section(
            id: CatalogFilterGroup.constellation.id,
            group: .constellation,
            label: L10n.text("filter.section.network"),
            filters: CatalogFilterGroup.constellation.filters
        ),
    ]

    let scope: CatalogScope
    let selections: Set<CatalogFilter>
    let resultCount: Int
    let expanded: Bool
    let onToggle: () -> Void
    let onSelectScope: (CatalogScope) -> Void
    let onToggleFilter: (CatalogFilter) -> Void
    let onReset: () -> Void
    let onClose: () -> Void
    var presence: Double = 1

    private var resultSummary: String {
        if selections.isEmpty {
            return L10n.format("filter.result.current", scope.title, resultCount)
        }
        return L10n.format("filter.result.additional", selections.count, resultCount)
    }

    private var hasSelection: Bool {
        scope != .all || !selections.isEmpty
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                controlSurface
                    .glassEffect(
                        .regular
                            .tint(Palette.voidBlack.opacity(0.12))
                            .interactive(),
                        in: shellShape
                    )
            } else {
                controlSurface
                    .background(.ultraThinMaterial, in: shellShape)
                    .background(Palette.voidBlack.opacity(0.68), in: shellShape)
            }
        }
        .overlay {
            shellShape
                .stroke(Palette.inkFaint.opacity(expanded ? 0.34 : 0.26), lineWidth: 0.55)
        }
        .opacity(expanded ? 1 : presence)
        .accessibilityElement(children: .contain)
    }

    private var shellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.outerCornerRadius, style: .continuous)
    }

    private var controlSurface: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                divider.padding(.horizontal, 12)
                resultFooter
            } else {
                compactEntry
            }
        }
        .frame(width: expanded ? Self.expandedWidth : Self.collapsedSize, alignment: .leading)
        .contentShape(shellShape)
    }

    private var compactEntry: some View {
        Button(action: onToggle) {
            HStack(spacing: 7) {
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.signal.opacity(hasSelection ? 0.92 : 0.74))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text(hasSelection ? "filter.filtered" : "filter.all_objects"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.inkHigh.opacity(0.9))
                        .lineLimit(1)
                    Text(L10n.format("filter.visible", resultCount))
                        .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.inkLow.opacity(0.68))
            }
            .padding(.horizontal, 11)
            .frame(height: Self.collapsedHeight)
            .contentShape(shellShape)
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(L10n.format("filter.accessibility", resultCount))
        .accessibilityHint(L10n.text("filter.accessibility.hint"))
    }

    private var resultFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.signal.opacity(0.88))

            Text(resultSummary)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Palette.inkHigh.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 5)
        }
        .padding(.horizontal, 13)
        .frame(height: Self.collapsedHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resultSummary)
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            panelHeader

            VStack(spacing: 0) {
                scopeSection
                ForEach(Self.sections) { section in
                    divider
                        .padding(.horizontal, 4)
                    filterSection(section)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: Self.expandedWidth)
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("filter.title"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkHigh.opacity(0.92))
                Text(L10n.text("filter.live_note"))
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
            }

            Spacer(minLength: 8)

            if hasSelection {
                Button(action: onReset) {
                    Text(L10n.text("action.reset"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.signal.opacity(0.9))
                        .frame(width: 42, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("filter.reset.accessibility"))
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.inkLow.opacity(0.62))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("filter.close.accessibility"))
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .overlay(alignment: .bottom) { divider.padding(.horizontal, 12) }
        .animation(.easeOut(duration: 0.18), value: hasSelection)
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader(symbol: "scope", label: L10n.text("filter.section.scope"), tint: Palette.signal)

            VStack(spacing: 0) {
                ForEach(CatalogScope.allCases) { item in
                    scopeCell(item)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func filterSection(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionHeader(
                symbol: section.group.symbolName,
                label: section.label,
                tint: section.group.tint
            )

            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(section.filters) { filter in
                    filterCell(filter)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func sectionHeader(symbol: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(tint.opacity(0.78))
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.readableSecondary))
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 3)
    }

    private func scopeCell(_ item: CatalogScope) -> some View {
        let selected = item == scope
        return Button { onSelectScope(item) } label: {
            selectionCell(
                symbol: item.symbolName,
                title: item.title,
                tint: Palette.signal,
                selected: selected,
                selectionSymbol: selected ? "circle.inset.filled" : "circle"
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func filterCell(_ filter: CatalogFilter) -> some View {
        let selected = selections.contains(filter)
        return Button { onToggleFilter(filter) } label: {
            selectionCell(
                symbol: filterSymbol(for: filter),
                title: filter.title,
                tint: filter.tint,
                selected: selected,
                selectionSymbol: selected ? "checkmark.square.fill" : "square"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            L10n.format("filter.accessibility.item", filter.title, filter.subtitle)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectionCell(
        symbol: String,
        title: String,
        tint: Color,
        selected: Bool,
        selectionSymbol: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(tint.opacity(selected ? 0.96 : 0.66))
                .frame(width: 15)

            Text(title)
                .font(.system(size: 9.5, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Palette.inkHigh.opacity(0.95) : Palette.inkMid.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 2)

            Image(systemName: selectionSymbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(selected ? tint.opacity(0.9) : Palette.inkLow.opacity(0.44))
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected ? tint.opacity(0.085) : Color.clear,
            in: RoundedRectangle(cornerRadius: Self.innerCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Self.innerCornerRadius, style: .continuous)
                .stroke(
                    selected ? tint.opacity(0.24) : Palette.inkFaint.opacity(0.04),
                    lineWidth: selected ? 0.55 : 0.35
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.innerCornerRadius, style: .continuous))
    }

    private func filterSymbol(for filter: CatalogFilter) -> String {
        switch filter {
        case .all: "scope"
        case .featured: "book.closed"
        case .humanScience: "sparkles"
        case .earthObservation: "globe.americas"
        case .navigation: "location.north.line"
        case .communications: "antenna.radiowaves.left.and.right"
        case .orbitalHeritage: "clock.arrow.circlepath"
        case .unitedStates: "star"
        case .europe: "circle.hexagongrid"
        case .china: "scope"
        case .otherPublic: "globe"
        case .starlink: "circle.grid.cross"
        case .oneweb: "circle.hexagongrid"
        case .chinaConstellations: "point.3.connected.trianglepath.dotted"
        case .kuiper: "circle.dotted.circle"
        case .mobileConstellations: "antenna.radiowaves.left.and.right"
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.18))
            .frame(height: 0.5)
    }
}
