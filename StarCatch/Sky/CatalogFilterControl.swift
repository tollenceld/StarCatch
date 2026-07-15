import SwiftUI

/// 目录镜片默认是一条纵向图标轨道：它与圆形入口建立明确差异，同时在
/// 点击前就预告全部筛选维度。展开时轨道留在原位，说明与数量只向右显影。
struct CatalogFilterControl: View {
    private static let collapsedHeight: CGFloat = 158
    private static let expandedHeight: CGFloat = 218

    static func surfaceHeight(expanded: Bool) -> CGFloat {
        expanded ? expandedHeight : collapsedHeight
    }

    let selection: CatalogFilter
    let categoryCounts: [CatalogCategory: Int]
    let totalCount: Int
    let expanded: Bool
    let onToggle: () -> Void
    let onSelect: (CatalogFilter) -> Void

    @Namespace private var glassNamespace

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlassControl
            } else {
                fallbackControl
            }
        }
        .accessibilityElement(children: .contain)
    }

    @available(iOS 26.0, *)
    private var liquidGlassControl: some View {
        GlassEffectContainer(spacing: 18) {
            controlSurface
                .glassEffect(
                    .regular.tint(Palette.voidBlack.opacity(0.32)).interactive(),
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                )
                .glassEffectID("catalog-filter", in: glassNamespace)
        }
    }

    private var fallbackControl: some View {
        controlSurface
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .background(
                Palette.voidBlack.opacity(0.78),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Palette.inkFaint.opacity(0.38), lineWidth: 0.6)
            }
            .matchedGeometryEffect(id: "catalog-filter", in: glassNamespace)
    }

    private var controlSurface: some View {
        HStack(spacing: 0) {
            iconRail

            if expanded {
                expandedLabels
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: -14).combined(with: .opacity),
                            removal: .offset(x: -8).combined(with: .opacity)
                        )
                    )
            }
        }
        .frame(
            width: expanded ? 296 : 44,
            height: Self.surfaceHeight(expanded: expanded),
            alignment: .leading
        )
        .clipped()
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    /// 收起态整条轨道都是展开按钮；展开后它仍停在左缘，再点同一条轨道即可收回。
    private var iconRail: some View {
        Button(action: onToggle) {
            VStack(spacing: 0) {
                ForEach(CatalogFilter.allCases) { filter in
                    let selected = filter == selection
                    let tint = filter.tint
                    ZStack {
                        if selected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Palette.inkHigh.opacity(0.07))
                                .frame(width: 28, height: 28)
                        }

                        Image(systemName: filter.symbolName)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(tint.opacity(selected ? 0.96 : 0.62))
                    }
                    .frame(width: 44, height: expanded ? 42 : 30)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 44, height: Self.surfaceHeight(expanded: expanded))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "收起卫星筛选" : "卫星筛选，当前为\(selection.title)")
        .accessibilityHint(expanded ? "收回右侧筛选说明" : "向右展开本地卫星目录分类")
    }

    private var expandedLabels: some View {
        VStack(spacing: 0) {
            ForEach(CatalogFilter.allCases) { filter in
                filterLabel(filter)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 252, height: Self.expandedHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.24))
                .frame(width: 0.5)
                .padding(.vertical, 14)
        }
    }

    private func filterLabel(_ filter: CatalogFilter) -> some View {
        let selected = filter == selection
        let tint = filter.tint
        return Button {
            onSelect(filter)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(filter.title)
                        .font(.system(size: 11.5, weight: .medium, design: .default))
                        .foregroundStyle(selected ? Palette.inkHigh : Palette.inkMid)
                    Text(filter.subtitle)
                        .font(.system(size: 8.5, weight: .regular, design: .default))
                        .foregroundStyle(Palette.inkLow.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer(minLength: 5)

                Text(count(for: filter).formatted())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        selected ? tint.opacity(0.78) : Palette.inkLow.opacity(0.5)
                    )
            }
            .padding(.leading, 12)
            .padding(.trailing, 11)
            .frame(width: 252, height: 42)
            .background(
                selected ? tint.opacity(0.05) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title)，\(filter.subtitle)，\(count(for: filter)) 个目标")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func count(for filter: CatalogFilter) -> Int {
        guard let category = filter.category else { return totalCount }
        return categoryCounts[category, default: 0]
    }
}
