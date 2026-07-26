import SwiftUI

/// 应用内隐私说明。公开网页版本应与本页保持一致。
struct PrivacyStatementView: View {
    let onFinished: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()
            StaticDustBackdrop()
                .ignoresSafeArea()
                .opacity(0.24)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 34) {
                    header

                    statement(
                        "位置与姿态",
                        "定位只用于在设备上计算观察者坐标与真北方向；陀螺仪只用于确定设备指向。位置和姿态不会离开设备。拒绝定位后，应用使用北京作为明确标注的假定坐标。"
                    )
                    statement(
                        "本地记录",
                        "观测记录、手册阅读状态和显示偏好仅保存在本机，用于恢复你的仪器状态。你可以在仪器面板中清除观测记录。"
                    )
                    statement(
                        "网络与第三方",
                        "当前版本不创建账户，不包含广告、分析或跟踪代码，也不会向开发者或第三方传输个人数据。SatelliteKit 仅在本机执行轨道计算。"
                    )
                    statement(
                        "你的选择",
                        "你可以在系统设置中撤销定位权限，也可以随时删除应用以移除全部本地数据。"
                    )

                    VStack(spacing: 0) {
                        externalLink(
                            title: "查看公开隐私政策",
                            eyebrow: "PUBLIC POLICY",
                            url: AppLinks.privacyPolicy
                        )
                        externalLink(
                            title: "反馈隐私或支持问题",
                            eyebrow: "SUPPORT",
                            url: AppLinks.support
                        )
                    }
                    .overlay(alignment: .top) { hairline }
                }
                .padding(.horizontal, 36)
                .padding(.top, 28)
                .padding(.bottom, 36)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ArchiveTopBar(
                backTitle: "仪器",
                trailingTitle: "PRIVACY · ON DEVICE",
                onBack: onFinished
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIVACY")
                .font(Typography.objectName)
                .tracking(Typography.objectNameTracking + 1)
                .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
            Text("隐私说明 · 2026-07-17")
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
            Rectangle()
                .fill(Palette.signal.opacity(0.62))
                .frame(width: 64, height: 0.75)
                .padding(.top, 10)
        }
    }

    private func statement(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Typography.fieldLabel)
                .tracking(Typography.fieldLabelTracking)
                .foregroundStyle(Palette.signal.opacity(Palette.Level.present))
            Text(body)
                .font(Typography.poetic)
                .tracking(Typography.poeticTracking)
                .lineSpacing(Typography.poeticLineSpacing)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
        }
    }

    private func externalLink(title: String, eyebrow: String, url: URL) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typography.guide)
                        .tracking(Typography.guideTracking)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                    Text(eyebrow)
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                    .frame(width: 34, height: 34)
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { hairline }
        }
        .buttonStyle(.plain)
        .accessibilityHint("在浏览器中打开")
    }

    private var hairline: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.34))
            .frame(height: 0.5)
    }
}

#Preview {
    PrivacyStatementView(onFinished: {})
}
