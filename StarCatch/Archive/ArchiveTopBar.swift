import SwiftUI

/// 全 App 边缘控件的共同几何与材质刻度。
/// 页面可以有不同内容宽度，但不再各自定义高度、圆角、间距和描边重量。
enum AppChromeMetrics {
    static let controlHeight: CGFloat = 44
    static let wingVisualHeight: CGFloat = 30
    /// 沉浸式页面返回翼只包裹图标与短标题，不继承状态翼的固定信息宽度。
    static let compactBackWingWidth: CGFloat = 72
    static let compactCornerRadius: CGFloat = 16
    static let wingCornerRadius: CGFloat = 14
    static let edgeInset: CGFloat = 16
    static let topEdgeInset: CGFloat = 20
    static let itemSpacing: CGFloat = 8
    static let mainActionWidth: CGFloat = 148
    static let strokeWidth: CGFloat = 0.55
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

/// 全 App 共用的返回入口。可见内容保持轻量，但触控区始终满足 44pt。
struct AppBackControl: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ContentTopBarMetrics.itemSpacing) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: ContentTopBarMetrics.iconWidth)
                Text(title)
                    .lineLimit(1)
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
        .accessibilityLabel("返回\(title)")
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
        ZStack {
            Text(title)
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.present))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: 128)

            HStack(spacing: 16) {
                AppBackControl(title: backTitle, action: onBack)

                Spacer(minLength: 12)

                trailingContent
            }
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
            .accessibilityLabel("更多观测记录操作")
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
                .frame(
                    width: ContentTopBarMetrics.controlHeight,
                    height: ContentTopBarMetrics.controlHeight
                )
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
