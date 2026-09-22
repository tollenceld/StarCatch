import SwiftUI

/// 最广局部视场之后出现的显式模式入口。它是一次导航确认，不参与缩放手势。
struct GlobalEntryControl: View {
    let enabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.forceLegacyMaterial) private var forceLegacyMaterial

    var body: some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency, !forceLegacyMaterial {
                button
                    .glassEffect(
                        .regular.tint(Palette.signal.opacity(0.12)).interactive(),
                        in: Capsule()
                    )
            } else {
                button
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Palette.voidBlack.opacity(0.84), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Palette.signal.opacity(0.54), lineWidth: 0.7)
                    }
            }
        }
        .accessibilityLabel(L10n.text("overview.entry.title"))
        .accessibilityHint(L10n.text("overview.entry.hint"))
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.signal.opacity(0.94))

                Text(L10n.text("overview.entry.title"))
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(Palette.inkHigh.opacity(0.96))
            }
            .frame(width: 194, height: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(SkyCapsulePressStyle())
        .disabled(!enabled)
    }
}

/// 离开 LIVE 后浮在时间轴上方的主动作。胶囊承担清晰的按压、扩散和触觉反馈，
/// 时间坐标仪本身只保留读数与拖动职责。
struct ReturnToLiveControl: View {
    let returning: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.forceLegacyMaterial) private var forceLegacyMaterial
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var feedbackPulse = false

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }

    var body: some View {
        Group {
            if #available(iOS 26.0, *), !reduceTransparency, !forceLegacyMaterial {
                actionButton
                    .glassEffect(
                        .regular
                            .tint(Palette.signal.opacity(returning ? 0.2 : 0.12))
                            .interactive(),
                        in: Capsule()
                    )
            } else {
                actionButton
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Palette.voidBlack.opacity(0.8), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Palette.inkFaint.opacity(0.52), lineWidth: 0.65)
                    }
            }
        }
        .accessibilityLabel(L10n.text(returning ? "time.returning.accessibility" : "time.return_now"))
        .accessibilityHint(L10n.text("time.return_now.hint"))
    }

    private var actionButton: some View {
        Button(action: trigger) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Palette.signal.opacity(0.36), lineWidth: 0.65)
                        .frame(width: 17, height: 17)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Palette.signal.opacity(0.92))
                        .rotationEffect(.degrees(returning ? -34 : 0))
                }

                Text(L10n.text(returning ? "time.returning" : "time.return_now"))
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .tracking(1.4)
                    .foregroundStyle(Palette.inkHigh.opacity(0.94))

                Rectangle()
                    .fill(Palette.signal.opacity(returning ? 0.72 : 0.42))
                    .frame(width: returning ? 22 : 14, height: 0.65)
            }
            .frame(
                width: AppChromeMetrics.mainActionWidth,
                height: AppChromeMetrics.controlHeight
            )
            .contentShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Palette.signal.opacity(0.6), lineWidth: 0.7)
                    .scaleEffect(feedbackPulse ? 1.14 : 1)
                    .opacity(feedbackPulse ? 0 : 0.48)
                    .animation(
                        suppressMotion
                            ? .easeOut(duration: 0.14)
                            : .easeOut(duration: 0.68),
                        value: feedbackPulse
                    )
            }
            .animation(.easeOut(duration: 0.3), value: returning)
        }
        .buttonStyle(SkyCapsulePressStyle())
        .disabled(returning)
    }

    private func trigger() {
        feedbackPulse = false
        DispatchQueue.main.async { feedbackPulse = true }
        action()
    }
}

struct SkyCapsulePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.065 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 主天空按需出现的紧凑复位入口。32pt 视觉表面仍保留 44pt 热区。
struct FieldOfViewResetControl: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.chromePreviewReducedTransparency) private var previewReduceTransparency
    @Environment(\.forceLegacyMaterial) private var forceLegacyMaterial

    private var reduceTransparency: Bool { systemReduceTransparency || previewReduceTransparency }

    var body: some View {
        Button(action: action) {
            surface
                .padding(.vertical, 6)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(L10n.text("view.reset"))
        .accessibilityHint(L10n.text("view.reset.hint"))
    }

    @ViewBuilder private var surface: some View {
        if #available(iOS 26.0, *), !reduceTransparency, !forceLegacyMaterial {
            label
                .glassEffect(
                    .regular.tint(Palette.inkLow.opacity(0.1)).interactive(),
                    in: Capsule()
                )
        } else {
            label
                .background(Palette.voidBlack.opacity(reduceTransparency ? 1 : 0.8), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Palette.inkFaint.opacity(0.46), lineWidth: 0.6)
                }
        }
    }

    private var label: some View {
        HStack(spacing: 9) {
            Image(systemName: "viewfinder")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.signal.opacity(0.78))
            Text(L10n.text("view.reset"))
                .font(.system(size: 11, weight: .medium, design: .default))
                .tracking(1.1)
                .foregroundStyle(Palette.inkHigh.opacity(0.88))
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }
}
