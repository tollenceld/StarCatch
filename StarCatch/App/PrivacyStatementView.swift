import SwiftUI

/// 应用内隐私说明。公开网页版本应与本页保持一致。
struct PrivacyStatementView: View {
    let onFinished: () -> Void

    @Environment(\.openURL) private var openURL

    private func copy(_ key: String) -> String { L10n.text(key) }

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
                        title: copy("privacy.location.title"),
                        text: copy("privacy.location.body")
                    )
                    PrivacySection(
                        title: copy("privacy.records.title"),
                        text: copy("privacy.records.body")
                    )
                    PrivacySection(
                        title: copy("privacy.network.title"),
                        text: copy("privacy.network.body")
                    )
                    PrivacySection(
                        title: copy("privacy.choice.title"),
                        text: copy("privacy.choice.body")
                    )

                    VStack(spacing: 0) {
                        DocumentLinkRow(
                            title: copy("privacy.public.title"),
                            label: copy("privacy.public.label"),
                            action: { openURL(AppLinks.privacyPolicy(for: .current)) }
                        )
                        DocumentLinkRow(
                            title: copy("privacy.support.title"),
                            label: copy("privacy.support.label"),
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
                backTitle: copy("navigation.settings"),
                title: copy("navigation.privacy"),
                onBack: onFinished
            )
        }
        .appEdgeBackGesture(action: onFinished)
    }
}

private struct PrivacySummary: View {
    private let conclusionKeys = [
        "privacy.summary.no_account",
        "privacy.summary.no_location_upload",
        "privacy.summary.no_tracking",
        "privacy.summary.on_device",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(conclusionKeys, id: \.self) { key in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Palette.signal.opacity(0.62))
                        .frame(width: 3.5, height: 3.5)
                    Text(L10n.text(key))
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
        .accessibilityHint(L10n.text("accessibility.open_browser"))
    }
}

#Preview {
    PrivacyStatementView(onFinished: {})
}
