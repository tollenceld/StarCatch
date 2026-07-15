import SwiftUI

/// 锁定态唯一的显式退出动作。位置、体量与“返回此刻”一致，但语义是结束当前观测。
struct ArchiveDismissControl: View {
    let releasing: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var feedbackPulse = false

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                actionButton
                    .glassEffect(
                        .regular
                            .tint(Palette.signal.opacity(releasing ? 0.18 : 0.10))
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
        .accessibilityLabel(releasing ? "正在结束观测" : "结束观测")
        .accessibilityHint("关闭当前卫星档案并返回天空探索")
    }

    private var actionButton: some View {
        Button(action: trigger) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Palette.signal.opacity(0.38), lineWidth: 0.65)
                        .frame(width: 17, height: 17)
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Palette.signal.opacity(0.92))
                        .rotationEffect(.degrees(releasing ? 24 : 0))
                }

                Text(releasing ? "正在结束" : "结束观测")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .tracking(1.4)
                    .foregroundStyle(Palette.inkHigh.opacity(0.94))

                Rectangle()
                    .fill(Palette.signal.opacity(releasing ? 0.68 : 0.4))
                    .frame(width: releasing ? 20 : 14, height: 0.65)
            }
            .frame(width: 154, height: 42)
            .contentShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Palette.signal.opacity(0.56), lineWidth: 0.7)
                    .scaleEffect(feedbackPulse ? 1.12 : 1)
                    .opacity(feedbackPulse ? 0 : 0.46)
                    .animation(
                        suppressMotion
                            ? .easeOut(duration: 0.14)
                            : .easeOut(duration: 0.62),
                        value: feedbackPulse
                    )
            }
            .animation(.easeOut(duration: 0.26), value: releasing)
        }
        .buttonStyle(SkyCapsulePressStyle())
        .disabled(releasing)
    }

    private func trigger() {
        feedbackPulse = false
        DispatchQueue.main.async { feedbackPulse = true }
        action()
    }
}

/// 离开 LIVE 后浮在时间轴上方的主动作。胶囊承担清晰的按压、扩散和触觉反馈，
/// 时间坐标仪本身只保留读数与拖动职责。
struct ReturnToLiveControl: View {
    let returning: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var feedbackPulse = false

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
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
        .accessibilityLabel(returning ? "正在返回实时天空" : "返回此刻")
        .accessibilityHint("让卫星沿时间轨迹回到当前状态")
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

                Text(returning ? "正在返回" : "返回此刻")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .tracking(1.4)
                    .foregroundStyle(Palette.inkHigh.opacity(0.94))

                Rectangle()
                    .fill(Palette.signal.opacity(returning ? 0.72 : 0.42))
                    .frame(width: returning ? 22 : 14, height: 0.65)
            }
            .frame(width: 154, height: 42)
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

private struct SkyCapsulePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 主天空与三维星图共用的镜头归位动作。仅在视场偏离默认比例时出现。
struct FieldOfViewResetControl: View {
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                actionButton
                    .glassEffect(
                        .regular
                            .tint(Palette.inkLow.opacity(0.1))
                            .interactive(),
                        in: Capsule()
                    )
            } else {
                actionButton
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Palette.voidBlack.opacity(0.8), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Palette.inkFaint.opacity(0.46), lineWidth: 0.6)
                    }
            }
        }
        .accessibilityLabel("复位视场")
        .accessibilityHint("恢复当前视图的默认观察比例")
    }

    private var actionButton: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.signal.opacity(0.78))
                Text("复位视场")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .tracking(1.1)
                    .foregroundStyle(Palette.inkHigh.opacity(0.88))
            }
            .frame(width: 124, height: 38)
            .contentShape(Capsule())
        }
        .buttonStyle(SkyCapsulePressStyle())
    }
}
