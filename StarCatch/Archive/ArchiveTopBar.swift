import SwiftUI

/// 设置、记录与隐私页共享的标准顶部导航：左侧永远返回，右侧只放状态或当前页操作。
/// 视觉保持 StarCatch 的仪器语言，位置与 44pt 触控逻辑遵循常规 iOS 导航。
struct ArchiveTopBar: View {
    let backTitle: String
    let trailingTitle: String
    var trailingIcon: String? = nil
    let onBack: () -> Void
    var onTrailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                    Text(backTitle)
                }
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.signal.opacity(Palette.Level.full))
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            if let onTrailingAction {
                Button(action: onTrailingAction) {
                    HStack(spacing: 7) {
                        if let trailingIcon {
                            Image(systemName: trailingIcon)
                                .font(.caption.weight(.medium))
                        }
                        Text(trailingTitle)
                    }
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                    .frame(minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(trailingTitle)
            } else {
                Text(trailingTitle)
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 34)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(Palette.voidBlack.opacity(0.97))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.34))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}
