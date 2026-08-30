import SwiftUI

/// 实时作用于背景天空的渐进式筛选 Sheet。局部状态只负责即时选中反馈；每次动作
/// 同步写回 `SkySession`，因此关闭 Sheet 不需要“应用”步骤。
struct CatalogFilterSheet: View {
    let session: SkySession

    @Environment(\.dismiss) private var dismiss
    @State private var scope: CatalogScope
    @State private var selections: Set<CatalogFilter>
    @State private var resultCount: Int

    private struct FilterSection: Identifiable {
        let group: CatalogFilterGroup
        var id: String { group.id }
    }

    private static let detailedSections = [
        FilterSection(group: .mission),
        FilterSection(group: .authority),
        FilterSection(group: .constellation),
    ]

    private static let adaptiveColumns = [
        GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 10),
    ]

    init(session: SkySession) {
        self.session = session
        _scope = State(initialValue: session.catalogScope)
        _selections = State(initialValue: session.catalogFilters)
        _resultCount = State(initialValue: session.visibleObjects.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    liveSummary
                    frequentLenses
                    scopeSection
                    ForEach(Self.detailedSections) { section in
                        filterSection(section.group)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .background(Palette.voidBlack)
            .navigationTitle(L10n.text("filter.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if hasSelection {
                        Button(L10n.text("action.reset"), action: reset)
                            .foregroundStyle(Palette.signal)
                            .accessibilityLabel(L10n.text("filter.reset.accessibility"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L10n.text("filter.close.accessibility"))
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Palette.voidBlack.opacity(0.96), for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var hasSelection: Bool {
        scope != .all || !selections.isEmpty
    }

    private var liveSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Palette.signal.opacity(0.28), lineWidth: 0.7)
                    .frame(width: 34, height: 34)
                Circle()
                    .fill(Palette.signal.opacity(0.82))
                    .frame(width: 4, height: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("filter.live_note"))
                    .font(Typography.guide)
                    .foregroundStyle(Palette.inkHigh.opacity(0.92))
                Text(L10n.format("filter.visible", resultCount))
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(sheetSurface)
        .accessibilityElement(children: .combine)
    }

    private var frequentLenses: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(.overview)
            LazyVGrid(columns: Self.adaptiveColumns, spacing: 10) {
                ForEach(CatalogFilter.frequentLenses) { filter in
                    filterTile(
                        filter,
                        selected: frequentLensSelection == filter,
                        action: { selectFrequentLens(filter) }
                    )
                }
            }
        }
    }

    private var frequentLensSelection: CatalogFilter? {
        guard scope == .all else { return nil }
        if selections.isEmpty { return .all }
        guard selections.count == 1,
              let only = selections.first,
              CatalogFilter.frequentLenses.contains(only)
        else { return nil }
        return only
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                symbol: "scope",
                title: L10n.text("filter.section.scope"),
                subtitle: nil,
                tint: Palette.signal
            )
            VStack(spacing: 0) {
                ForEach(CatalogScope.allCases) { item in
                    scopeRow(item)
                    if item != CatalogScope.allCases.last {
                        divider.padding(.leading, 46)
                    }
                }
            }
            .background(sheetSurface)
        }
    }

    private func filterSection(_ group: CatalogFilterGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(group)
            LazyVGrid(columns: Self.adaptiveColumns, spacing: 10) {
                ForEach(group.filters) { filter in
                    filterTile(
                        filter,
                        selected: selections.contains(filter),
                        action: { toggle(filter) }
                    )
                }
            }
        }
    }

    private func sectionHeader(_ group: CatalogFilterGroup) -> some View {
        sectionTitle(
            symbol: group.symbolName,
            title: group.title,
            subtitle: group.subtitle,
            tint: group.tint
        )
    }

    private func sectionTitle(
        symbol: String,
        title: String,
        subtitle: String?,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint.opacity(0.86))
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.guide)
                    .foregroundStyle(Palette.inkHigh.opacity(0.9))
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.readingCompact)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func scopeRow(_ item: CatalogScope) -> some View {
        let selected = item == scope
        return Button { selectScope(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle((selected ? Palette.signal : Palette.inkLow).opacity(0.9))
                    .frame(width: 22)
                Text(item.title)
                    .font(Typography.guide)
                    .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle((selected ? Palette.signal : Palette.inkFaint).opacity(0.82))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func filterTile(
        _ filter: CatalogFilter,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: filterSymbol(filter))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(filter.tint.opacity(selected ? 0.96 : 0.68))
                    .frame(width: 20)
                Text(filter.title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(Palette.inkHigh.opacity(selected ? 0.94 : 0.76))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark" : "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        (selected ? filter.tint : Palette.inkLow).opacity(selected ? 0.9 : 0.5)
                    )
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 58)
            .background(
                selected ? filter.tint.opacity(0.105) : Palette.voidBlack.opacity(0.48),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selected ? filter.tint.opacity(0.34) : Palette.inkFaint.opacity(0.22),
                        lineWidth: 0.6
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(
            L10n.format("filter.accessibility.item", filter.title, filter.subtitle)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sheetSurface: some ShapeStyle {
        Palette.inkFaint.opacity(0.11)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.24))
            .frame(height: 0.5)
    }

    private func selectFrequentLens(_ filter: CatalogFilter) {
        scope = .all
        selections = filter == .all ? [] : [filter]
        session.setFrequentLens(filter)
        refreshResultCount()
        ObservationHaptics.shared.selectionChanged()
    }

    private func selectScope(_ newScope: CatalogScope) {
        scope = newScope
        session.setCatalogScope(newScope)
        refreshResultCount()
        ObservationHaptics.shared.selectionChanged()
    }

    private func toggle(_ filter: CatalogFilter) {
        if selections.contains(filter) {
            selections.remove(filter)
        } else {
            selections.insert(filter)
        }
        session.toggleCatalogFilter(filter)
        refreshResultCount()
        ObservationHaptics.shared.selectionChanged()
    }

    private func reset() {
        scope = .all
        selections.removeAll()
        session.resetCatalogFilters()
        refreshResultCount()
        ObservationHaptics.shared.lightImpact(intensity: 0.55)
    }

    private func refreshResultCount() {
        resultCount = session.visibleObjects.count
    }

    private func filterSymbol(_ filter: CatalogFilter) -> String {
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
}

#Preview {
    CatalogFilterSheet(session: SkySession())
        .preferredColorScheme(.dark)
}
