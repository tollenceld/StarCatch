import SwiftUI

/// 全 App 边缘控件的共同几何与材质刻度。
/// 页面可以有不同内容宽度，但不再各自定义高度、圆角、间距和描边重量。
enum AppChromeMetrics {
    static let controlHeight: CGFloat = 44
    static let wingVisualHeight: CGFloat = 32
    /// 沉浸式页面返回翼只包裹图标与短标题，不继承状态翼的固定信息宽度。
    static let compactBackWingWidth: CGFloat = 72
    static let compactCornerRadius: CGFloat = 16
    static let wingCornerRadius: CGFloat = 16
    static let edgeInset: CGFloat = 18
    static let topEdgeInset: CGFloat = 18
    static let itemSpacing: CGFloat = 10
    static let commandControlSize: CGFloat = 52
    static let commandRailHeight: CGFloat = 64
    static let commandRailCornerRadius: CGFloat = 24
    static let mainActionWidth: CGFloat = 168
    static let strokeWidth: CGFloat = 0.55
}

/// 控件材质选择的纯值结果，让系统透明度偏好、旧系统回退与 iOS 26 玻璃增强
/// 遵循同一优先级，也便于不启动 SwiftUI 视图就验证无障碍分支。
enum AppChromeSurfaceMode: Equatable {
    case liquidGlass
    case translucentMaterial
    case opaque

    nonisolated static func resolve(
        liquidGlassAvailable: Bool,
        reduceTransparency: Bool,
        forceLegacyMaterial: Bool
    ) -> AppChromeSurfaceMode {
        if reduceTransparency { return .opaque }
        if liquidGlassAvailable, !forceLegacyMaterial { return .liquidGlass }
        return .translucentMaterial
    }
}

/// 底部四个入口的根页面共享同一种收回语义。工具面板和全球轨道虽然使用
/// 不同表面，左侧入口都从同一位置向下返回天空；普通详情页才使用左箭头。
enum AppNavigationControlRole: Equatable {
    case back
    case dismissToSky

    var systemImage: String {
        switch self {
        case .back: "chevron.left"
        case .dismissToSky: "chevron.down"
        }
    }
}

/// 全 App 共用的返回 / 收回入口。图标语义由页面层级决定，文字、44pt 热区、
/// 字体、颜色和无障碍朗读保持一致。
struct AppNavigationControl: View {
    let title: String
    let role: AppNavigationControlRole
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ContentTopBarMetrics.itemSpacing) {
                    navigationIcon
                    Text(title)
                        .lineLimit(1)
                }
                navigationIcon
            }
            .font(Typography.guide)
            .tracking(Typography.guideTracking)
            .foregroundStyle(Palette.signal.opacity(Palette.Level.full))
            .frame(
                minWidth: ContentTopBarMetrics.controlHeight,
                minHeight: ContentTopBarMetrics.controlHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("navigation.back", title))
    }

    private var navigationIcon: some View {
        Image(systemName: role.systemImage)
            .font(.caption.weight(.semibold))
            .frame(width: ContentTopBarMetrics.iconWidth)
    }
}

/// 筛选、记录与设置面板共用的顶部导航。页面标题固定靠右，左侧始终是
/// 指向上一层的明确返回入口。
struct AppPageHeader: View {
    let backTitle: String
    let title: String
    let onBack: () -> Void
    var collapsesToSky = false

    var body: some View {
        HStack(spacing: 12) {
            AppNavigationControl(
                title: backTitle,
                role: collapsesToSky ? .dismissToSky : .back,
                action: onBack
            )
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 12)

            Text(title)
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, AppChromeMetrics.edgeInset)
        .frame(height: 56)
        .background(Palette.sheetBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(Palette.Level.functionalDivider))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        // A fixed 56pt navigation row cannot grow with accessibility body text;
        // keep it legible while the scrolling content retains the full type range.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// 面板内的内容外壳；外部容器负责几何。仅顶栏可下拉关闭，子页左缘返回上一层。
struct AppPageShell<Content: View>: View {
    let backTitle: String
    let title: String
    let onBack: () -> Void
    var isRoot = true
    @ViewBuilder let content: () -> Content
    @Environment(\.utilityPanelProgress) private var progress
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.chromePreviewReducedMotion) private var previewReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    private var suppressMotion: Bool { reducedMotion || systemReducedMotion || previewReducedMotion }

    var body: some View {
        if isRoot {
            page
        } else {
            page.appEdgeBackGesture(action: onBack)
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            AppPageHeader(
                backTitle: backTitle,
                title: title,
                onBack: onBack,
                collapsesToSky: isRoot
            )
            .opacity(DockMorphMetrics.headerReveal(progress))
            .offset(y: suppressMotion ? 0 : 12 * (1 - DockMorphMetrics.headerReveal(progress)))
            .appRootDismissGesture(enabled: isRoot, action: onBack)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(DockMorphMetrics.contentReveal(progress))
                .offset(y: suppressMotion ? 0 : 20 * (1 - DockMorphMetrics.contentReveal(progress)))
        }
        .background(Palette.sheetBackground.opacity(DockMorphMetrics.headerReveal(progress)))
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape, onBack)
    }
}

/// 内容页顶部导航的唯一几何规范。安全区由 `safeAreaInset` 统一提供，
/// 页面本身不再为不同机型或层级额外猜测顶部位置。
enum ContentTopBarMetrics {
    static let height: CGFloat = 56
    static let controlHeight = AppChromeMetrics.controlHeight
    static let horizontalMargin = AppChromeMetrics.topEdgeInset
    static let itemSpacing = AppChromeMetrics.itemSpacing
    static let iconWidth: CGFloat = 12
}

/// 内容页的功能性分隔线；统一对比度，避免每个页面各自定义最暗灰阶。
struct ContentHairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(Palette.Level.functionalDivider))
            .frame(height: 0.5)
    }
}

/// 普通详情页返回入口。根页面统一使用 `AppNavigationControl.dismissToSky`。
struct AppBackControl: View {
    let title: String
    let action: () -> Void

    var body: some View {
        AppNavigationControl(title: title, role: .back, action: action)
    }
}

/// 根页面顶部下拉的共同命中规则。只挂在标题栏上，避免争抢列表滚动、时间轴
/// 拖动和地球旋转；四个入口均把它解释为“收回到天空”。
struct AppRootDismissGestureModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 16).onEnded { value in
                    guard DockMorphMetrics.shouldDismiss(
                        translation: value.translation,
                        predicted: value.predictedEndTranslation
                    ) else { return }
                    action()
                }
            )
        } else {
            content
        }
    }
}

/// StarCatch 内容页的标准 iOS 返回手势。
///
/// 只在屏幕左缘的窄热区识别向右拖动，避免与正文滚动、手册翻页或地球旋转争抢。
/// 左上角按钮仍是主要且可发现的返回入口。
struct AppEdgeBackGestureModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    nonisolated static func shouldNavigateBack(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        let projectedX = max(translation.width, predictedEndTranslation.width)
        let horizontalMagnitude = max(
            abs(translation.width),
            abs(predictedEndTranslation.width)
        )
        let verticalMagnitude = max(
            abs(translation.height),
            abs(predictedEndTranslation.height)
        )
        return projectedX >= 64
            && horizontalMagnitude > verticalMagnitude * 1.2
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if enabled {
                    Color.clear
                        .frame(width: 28)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(
                                minimumDistance: 12,
                                coordinateSpace: .local
                            )
                            .onEnded { value in
                                guard Self.shouldNavigateBack(
                                    translation: value.translation,
                                    predictedEndTranslation: value.predictedEndTranslation
                                ) else { return }
                                action()
                            }
                        )
                        .ignoresSafeArea(edges: .vertical)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func appRootDismissGesture(
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        modifier(AppRootDismissGestureModifier(enabled: enabled, action: action))
    }

    func appEdgeBackGesture(
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            AppEdgeBackGestureModifier(
                enabled: enabled,
                action: action
            )
        )
    }
}

/// 设置、记录与阅读页共享的标准顶部导航：左侧永远返回，右侧只放当前页操作。
/// 视觉保持 StarCatch 的仪器语言，位置与 44pt 触控逻辑遵循常规 iOS 导航。
struct ArchiveTopBar: View {
    let backTitle: String
    let title: String
    var trailingTitle: String? = nil
    var trailingIcon: String? = nil
    let onBack: () -> Void
    var onTrailingAction: (() -> Void)? = nil
    var destructiveMenuTitle: String? = nil
    var onDestructiveMenuAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            AppBackControl(title: backTitle, action: onBack)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(title)
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.present))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            trailingContent
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, ContentTopBarMetrics.horizontalMargin)
        .frame(height: ContentTopBarMetrics.height)
        .frame(maxWidth: .infinity)
        .background(Palette.voidBlack.opacity(0.97))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(Palette.Level.functionalDivider))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let destructiveMenuTitle, let onDestructiveMenuAction {
            Menu {
                Button(
                    destructiveMenuTitle,
                    systemImage: "trash",
                    role: .destructive,
                    action: onDestructiveMenuAction
                )
            } label: {
                trailingLabel(color: Palette.inkLow.opacity(Palette.Level.secondary))
            }
            .accessibilityLabel(L10n.text("observations.more.accessibility"))
        } else if let onTrailingAction, let trailingTitle {
            Button(action: onTrailingAction) {
                trailingLabel(
                    title: trailingTitle,
                    color: Palette.inkMid.opacity(Palette.Level.present)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(trailingTitle)
        } else {
            Color.clear
                .frame(height: ContentTopBarMetrics.controlHeight)
                .accessibilityHidden(true)
        }
    }

    private func trailingLabel(title: String? = nil, color: Color) -> some View {
        HStack(spacing: ContentTopBarMetrics.itemSpacing) {
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.caption.weight(.medium))
            }
            if let title {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .font(Typography.statusTag)
        .tracking(Typography.statusTagTracking)
        .foregroundStyle(color)
        .frame(
            minWidth: ContentTopBarMetrics.controlHeight,
            minHeight: ContentTopBarMetrics.controlHeight,
            alignment: .trailing
        )
        .contentShape(Rectangle())
    }
}
