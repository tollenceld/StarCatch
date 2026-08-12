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
                .opacity(0.20)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    PrivacySummary()

                    PrivacySection(
                        title: "位置与姿态",
                        text: "定位默认请求完整精度，只用于在设备上计算观察者坐标与真北方向；低轨目标会因近似位置产生明显视差。陀螺仪只用于确定设备指向，位置和姿态不会上传或持久化。你仍可在系统中选择近似位置；精度不足时应用会明确提示。拒绝定位后，应用使用北京作为明确标注的假定坐标。"
                    )
                    PrivacySection(
                        title: "本地记录",
                        text: "观测记录、手册阅读状态和显示偏好仅保存在本机，用于恢复你的仪器状态。你可以在设置中清除观测记录。"
                    )
                    PrivacySection(
                        title: "网络与第三方",
                        text: "当前版本不创建账户，不包含广告、分析或跟踪代码，也不会向开发者或第三方传输个人数据。SatelliteKit 仅在本机执行轨道计算。"
                    )
                    PrivacySection(
                        title: "你的选择",
                        text: "你可以在系统设置中撤销定位权限，也可以随时删除应用以移除全部本地数据。"
                    )

                    VStack(spacing: 0) {
                        DocumentLinkRow(
                            title: "查看公开隐私政策",
                            label: "PUBLIC POLICY",
                            action: { openURL(AppLinks.privacyPolicy) }
                        )
                        DocumentLinkRow(
                            title: "反馈隐私或支持问题",
                            label: "SUPPORT",
                            action: { openURL(AppLinks.support) }
                        )
                    }
                    .overlay(alignment: .top) { ContentHairline() }

                    Text("PRIVACY · ON DEVICE · 2026-08-01")
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                }
                .padding(.horizontal, 30)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ArchiveTopBar(
                backTitle: "设置",
                title: "隐私",
                onBack: onFinished
            )
        }
        .appEdgeBackGesture(action: onFinished)
    }
}

private struct PrivacySummary: View {
    private let conclusions = [
        "不创建账户",
        "不上传位置",
        "不进行追踪",
        "所有计算均在设备上完成",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(conclusions, id: \.self) { conclusion in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Palette.signal.opacity(0.62))
                        .frame(width: 3.5, height: 3.5)
                    Text(conclusion)
                        .font(Typography.readingCompact)
                        .tracking(Typography.readingCompactTracking)
                        .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.present))
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { ContentHairline() }
        .overlay(alignment: .bottom) { ContentHairline() }
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacySection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(Typography.guide.weight(.medium))
                .tracking(0.35)
                .foregroundStyle(Palette.signal.opacity(Palette.Level.present))
            Text(text)
                .font(Typography.readingBody)
                .tracking(Typography.readingBodyTracking)
                .lineSpacing(Typography.readingBodyLineSpacing)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DocumentLinkRow: View {
    let title: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typography.guide)
                        .tracking(Typography.guideTracking)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                    Text(label)
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.secondary))
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                    .frame(width: 34, height: 44)
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { ContentHairline() }
        }
        .buttonStyle(.plain)
        .accessibilityHint("在浏览器中打开")
    }
}

#Preview {
    PrivacyStatementView(onFinished: {})
}
