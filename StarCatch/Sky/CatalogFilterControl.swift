import SwiftUI

/// 顶部筛选摘要的稳定值模型。范围始终排在任务、机构和星座筛选之前，
/// 让页面与测试共享同一顺序。
struct CatalogFilterSummaryItem: Identifiable, Equatable {
    enum Selection: Equatable {
        case scope(CatalogScope)
        case filter(CatalogFilter)
    }

    let selection: Selection

    var id: String {
        switch selection {
        case .scope(let scope): "scope.\(scope.id)"
        case .filter(let filter): "filter.\(filter.id)"
        }
    }

    var title: String {
        switch selection {
        case .scope(let scope): scope.title
        case .filter(let filter): filter.title
        }
    }

    var tint: Color {
        switch selection {
        case .scope: Palette.signal
        case .filter(let filter): filter.tint
        }
    }

    nonisolated static func resolve(
        scope: CatalogScope,
        filters: Set<CatalogFilter>
    ) -> [CatalogFilterSummaryItem] {
        var result: [CatalogFilterSummaryItem] = []
        if scope != .all {
            result.append(CatalogFilterSummaryItem(selection: .scope(scope)))
        }
        result.append(contentsOf: CatalogFilter.allCases.compactMap { filter in
            guard filter != .all, filters.contains(filter) else { return nil }
            return CatalogFilterSummaryItem(selection: .filter(filter))
        })
        return result
    }
}

/// 即时作用于当前天空的筛选面板。局部状态只负责选中反馈，每次动作同步写回
/// `SkySession`，返回页面不会撤销已做出的选择。
struct CatalogFilterPage: View {
    let session: SkySession
    let onBack: () -> Void

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

    init(session: SkySession, onBack: @escaping () -> Void = {}) {
        self.session = session
        self.onBack = onBack
        _scope = State(initialValue: session.catalogScope)
        _selections = State(initialValue: session.catalogFilters)
        _resultCount = State(initialValue: session.visibleObjects.count)
    }

    var body: some View {
        AppPageShell(
            backTitle: L10n.text("navigation.sky"),
            title: L10n.text("filter.title"),
            onBack: onBack
        ) {
            VStack(spacing: 0) {
                selectionSummary

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        frequentLenses
                        scopeSection
                        ForEach(Self.detailedSections) { section in
                            filterSection(section.group)
                        }
                    }
                    .padding(.horizontal, AppChromeMetrics.edgeInset)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
            }
        }
    }

    private var summaryItems: [CatalogFilterSummaryItem] {
        CatalogFilterSummaryItem.resolve(scope: scope, filters: selections)
    }

    private var hasSelection: Bool {
        !summaryItems.isEmpty
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("filter.filtered"))
                        .font(Typography.guide)
                        .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.present))
                    Text(L10n.format("filter.visible", resultCount))
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                }

                Spacer(minLength: 12)

                if hasSelection {
                    Button(L10n.text("action.reset"), action: reset)
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.signal.opacity(Palette.Level.present))
                        .buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .accessibilityLabel(L10n.text("filter.reset.accessibility"))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if summaryItems.isEmpty {
                        summaryChip(
                            title: CatalogScope.all.title,
                            tint: Palette.inkMid,
                            action: nil
                        )
                    } else {
                        ForEach(summaryItems) { item in
                            summaryChip(
                                title: item.title,
                                tint: item.tint,
                                action: { remove(item) }
                            )
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, AppChromeMetrics.edgeInset)
        .padding(.top, 14)
        .padding(.bottom, 13)
        .background(Palette.sheetBackground)
        .overlay(alignment: .bottom) { ContentHairline() }
        .accessibilityElement(children: .contain)
    }

    private func summaryChip(
        title: String,
        tint: Color,
        action: (() -> Void)?
    ) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    chipContent(title: title, tint: tint, removable: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(L10n.text("action.delete"))")
            } else {
                chipContent(title: title, tint: tint, removable: false)
                    .accessibilityLabel(title)
            }
        }
    }

    private func chipContent(title: String, tint: Color, removable: Bool) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint.opacity(0.86))
                .frame(width: 5, height: 5)
            Text(title)
                .font(Typography.statusTag)
                .tracking(0.35)
                .lineLimit(1)
            if removable {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(tint.opacity(removable ? 0.1 : 0.055), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(removable ? 0.32 : 0.2), lineWidth: 0.6)
        }
        .contentShape(Capsule())
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
            .background(Palette.sheetSurface)
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
                Image(systemName: filter.symbolName)
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
                selected ? filter.tint.opacity(0.105) : Palette.sheetSurface.opacity(0.72),
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

    private func remove(_ item: CatalogFilterSummaryItem) {
        switch item.selection {
        case .scope:
            selectScope(.all)
        case .filter(let filter):
            toggle(filter)
        }
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
}

#Preview {
    CatalogFilterPage(session: SkySession())
}
