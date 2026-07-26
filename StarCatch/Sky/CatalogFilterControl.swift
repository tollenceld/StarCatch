import SwiftUI

/// 目录筛选是一枚改变天空阅读方式的“观察镜片”。
///
/// 这里刻意只有一层：展开后所有镜片都在同一张列表里，按“常用 / 任务 / 运营方 /
/// 轨道网络”分段排列。用户永远只需要一次点击就能换镜片，不必先回答“你想从哪一面
/// 阅读天空”这样的中间问题，也不会在返回箭头之间迷路。
struct CatalogFilterControl: View {
    /// 收起态是一枚方形端口而不是细长胶囊：它常驻在右下角的仪器轨末端，
    /// 必须有足够的落指面积，也要能在任何捕获状态下被一眼认出。
    static let collapsedSize: CGFloat = 60
    private static let cornerRadius: CGFloat = 21
    private static let panelWidth: CGFloat = 262
    private static let headerHeight: CGFloat = 52
    private static let rowHeight: CGFloat = 38
    private static let sectionLabelHeight: CGFloat = 26
    /// 列表高度上限。超出后在面板内滚动，面板本身不再改变尺寸——
    /// 尺寸恒定是这次重构最重要的一点：镜片面板不该在脚下伸缩。
    private static let listMaxHeight: CGFloat = 316

    private struct Section: Identifiable {
        let id: String
        let label: String
        let filters: [CatalogFilter]
    }

    /// 分段直接复用目录模型里的分组定义，避免两处各自维护一份清单。
    private static let sections: [Section] = [
        Section(
            id: "frequent",
            label: "常用",
            filters: CatalogFilter.frequentLenses
        ),
        Section(
            id: CatalogFilterGroup.mission.id,
            label: "任务类型",
            filters: CatalogFilterGroup.mission.filters.filter {
                !CatalogFilter.frequentLenses.contains($0)
            }
        ),
        Section(
            id: CatalogFilterGroup.authority.id,
            label: "运营方",
            filters: CatalogFilterGroup.authority.filters
        ),
        Section(
            id: CatalogFilterGroup.constellation.id,
            label: "轨道网络",
            filters: CatalogFilterGroup.constellation.filters
        ),
    ]

    let selection: CatalogFilter
    let expanded: Bool
    let onToggle: () -> Void
    let onSelect: (CatalogFilter) -> Void

    /// 观测层降权：捕获与锁定时镜片仍然在原位可用，只是让出第一视觉权重。
    var presence: Double = 1

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
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
        .opacity(expanded ? 1 : presence)
    }

    @available(iOS 26.0, *)
    private var liquidGlassControl: some View {
        GlassEffectContainer(spacing: 18) {
            controlSurface
                .glassEffect(
                    .regular.tint(Palette.voidBlack.opacity(0.32)).interactive(),
                    in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                )
                .glassEffectID("catalog-filter", in: glassNamespace)
        }
    }

    private var fallbackControl: some View {
        controlSurface
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            )
            .background(
                Palette.voidBlack.opacity(0.84),
                in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .stroke(Palette.inkFaint.opacity(0.34), lineWidth: 0.6)
            }
            .matchedGeometryEffect(id: "catalog-filter", in: glassNamespace)
    }

    @ViewBuilder
    private var controlSurface: some View {
        if expanded {
            expandedPanel
                .transition(.opacity.combined(with: .offset(x: 7)))
        } else {
            collapsedLens
                .frame(width: Self.collapsedSize, height: Self.collapsedSize)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
        }
    }

    /// 收起态：一枚 60pt 见方的镜片端口。图标承担识别，下方一行短标签回答
    /// “此刻装的是哪片镜片”。已筛选时描边点亮为镜片本身的身份色 —— 状态由
    /// 端口自己表达，不需要额外的提示行。
    private var collapsedLens: some View {
        let filtered = selection != .all
        let tint = filtered ? selection.tint : Palette.inkHigh
        return Button(action: onToggle) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(filtered ? 0.12 : 0.05))
                    Circle()
                        .stroke(tint.opacity(filtered ? 0.42 : 0.16), lineWidth: 0.7)
                    Image(systemName: filtered ? selection.symbolName : "camera.filters")
                        .font(.system(size: 14, weight: filtered ? .semibold : .regular))
                        .foregroundStyle(
                            (filtered ? selection.tint : Palette.inkMid)
                                .opacity(filtered ? 0.95 : 0.74)
                        )
                }
                .frame(width: 30, height: 30)

                Text(filtered ? selection.compactTitle : "镜片")
                    .font(.system(size: 8, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(
                        (filtered ? selection.tint : Palette.inkLow).opacity(filtered ? 0.8 : 0.62)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 5)
            }
            .frame(width: Self.collapsedSize, height: Self.collapsedSize)
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .stroke(
                        selection.tint.opacity(filtered ? 0.34 : 0),
                        lineWidth: 0.8
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(
            filtered ? "观察镜片，当前为\(selection.title)" : "观察镜片，当前为全部天空"
        )
        .accessibilityHint("展开后可以更换镜片或恢复全部天空")
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            panelHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.sections) { section in
                        sectionLabel(section.label)
                        ForEach(section.filters) { filter in
                            filterRow(filter)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: Self.listMaxHeight)
        }
        .frame(width: Self.panelWidth)
        .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private var panelHeader: some View {
        HStack(spacing: 9) {
            Text("观察镜片")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Palette.inkHigh.opacity(0.84))

            Spacer(minLength: 4)

            // 「全部天空」既是复位也是当前状态的答案，所以常驻在标题栏，
            // 不需要用户滚回列表顶部去找。
            if selection != .all {
                Button { onSelect(.all) } label: {
                    Text("全部天空")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.signal.opacity(0.86))
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(Palette.signal.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("恢复全部天空")
            }

            Button(action: onToggle) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.inkMid.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .background(Palette.inkHigh.opacity(0.035), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起观察镜片")
        }
        .padding(.horizontal, 11)
        .frame(width: Self.panelWidth, height: Self.headerHeight)
        .overlay(alignment: .bottom) { divider.padding(.horizontal, 12) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(Palette.inkLow.opacity(0.42))
            .frame(height: Self.sectionLabelHeight, alignment: .bottomLeading)
            .padding(.horizontal, 4)
    }

    /// 单行镜片。副标题只在选中时出现——收起的行保持安静，选中的行才解释自己在做什么。
    private func filterRow(_ filter: CatalogFilter) -> some View {
        let selected = filter == selection
        return Button {
            onSelect(filter)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(filter.tint.opacity(selected ? 0.94 : 0.6))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(filter.title)
                        .font(.system(size: 11, weight: selected ? .medium : .regular))
                        .foregroundStyle(
                            selected
                                ? Palette.inkHigh.opacity(0.95)
                                : Palette.inkMid.opacity(0.8)
                        )
                    if selected {
                        Text(filter.subtitle)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(Palette.inkLow.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 3)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(filter.tint.opacity(0.85))
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: Self.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? filter.tint.opacity(0.055) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title)，\(filter.subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.16))
            .frame(height: 0.5)
    }
}
