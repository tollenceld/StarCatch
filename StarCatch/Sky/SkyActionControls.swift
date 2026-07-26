import SwiftUI

/// 在设置中开启“确认捕获”后的主动作。它只负责建立或切换捕获；取消捕获由独立控件承担，
/// 避免同一个按钮在“切换”和“结束”之间产生含混。
enum FocusActionMode: Equatable {
    case seeking
    case confirm(progress: Double)
    case replace(progress: Double)
    case captured
    case releasing

    var title: String {
        switch self {
        case .seeking: "将准星移向卫星"
        case .confirm: "捕获卫星"
        case .replace: "切换捕获"
        case .captured: "捕获保持中"
        case .releasing: "正在取消"
        }
    }

    var symbol: String {
        switch self {
        case .seeking, .confirm: "scope"
        case .replace: "arrow.triangle.2.circlepath"
        case .captured: "dot.radiowaves.left.and.right"
        case .releasing: "xmark"
        }
    }

    var readiness: Double {
        switch self {
        case .seeking:
            0
        case .confirm(let progress), .replace(let progress):
            min(1, max(0, progress))
        case .captured, .releasing:
            1
        }
    }

    var isReleasing: Bool { self == .releasing }

    var isInteractive: Bool {
        switch self {
        case .seeking, .captured, .releasing: false
        default: true
        }
    }

    var width: CGFloat { self == .seeking ? 194 : 154 }
}

struct FocusActionControl: View {
    let mode: FocusActionMode
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
                            .tint(Palette.signal.opacity(mode == .seeking ? 0.05 : mode.isReleasing ? 0.18 : 0.10))
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
        .accessibilityLabel(mode.title)
        .accessibilityHint(accessibilityHint)
    }

    private var actionButton: some View {
        Button(action: trigger) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Palette.signal.opacity(0.38), lineWidth: 0.65)
                        .frame(width: 17, height: 17)
                    Circle()
                        .trim(from: 0, to: mode.readiness)
                        .stroke(
                            Palette.signal.opacity(0.86),
                            style: StrokeStyle(lineWidth: 1.05, lineCap: .round)
                        )
                        .frame(width: 17, height: 17)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: mode.symbol)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Palette.signal.opacity(mode == .seeking ? 0.5 : 0.92))
                        .rotationEffect(.degrees(mode.isReleasing ? 24 : 0))
                }

                Text(mode.title)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .tracking(1.4)
                    .foregroundStyle(Palette.inkHigh.opacity(mode == .seeking ? 0.52 : 0.94))

                Rectangle()
                    .fill(Palette.signal.opacity(mode.isReleasing ? 0.68 : 0.4 + 0.26 * mode.readiness))
                    .frame(width: 14 + 8 * CGFloat(mode.readiness), height: 0.65)
            }
            .frame(width: mode.width, height: 42)
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
            .animation(.easeOut(duration: 0.26), value: mode)
        }
        .buttonStyle(SkyCapsulePressStyle())
        .disabled(!mode.isInteractive)
    }

    private var accessibilityHint: String {
        switch mode {
        case .seeking:
            "移动设备，让卫星进入准星的捕获范围"
        case .confirm:
            "确认准星当前感应到的卫星"
        case .replace:
            "结束当前目标并锁定准星感应到的新卫星"
        case .captured:
            "当前目标保持捕获；可对准另一目标切换，或使用旁边按钮取消"
        case .releasing:
            "正在关闭当前卫星档案"
        }
    }

    private func trigger() {
        feedbackPulse = false
        DispatchQueue.main.async { feedbackPulse = true }
        action()
    }
}

enum CaptureSecondaryMode: Equatable {
    case cancelCapture
    case cancelling

    var title: String {
        switch self {
        case .cancelCapture: "取消捕获"
        case .cancelling: "取消中"
        }
    }

    var symbol: String {
        switch self {
        case .cancelCapture, .cancelling: "xmark"
        }
    }
}

struct CaptureSecondaryControl: View {
    let mode: CaptureSecondaryMode
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                button
                    .glassEffect(
                        .regular.tint(Palette.inkLow.opacity(0.08)).interactive(),
                        in: Capsule()
                    )
            } else {
                button
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Palette.voidBlack.opacity(0.82), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Palette.inkFaint.opacity(0.46), lineWidth: 0.65)
                    }
            }
        }
        .accessibilityLabel(mode.title)
        .accessibilityHint("结束当前持续捕获，不影响设置中的确认捕获开关")
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(mode.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.9)
            }
            .foregroundStyle(Palette.inkMid.opacity(mode == .cancelling ? 0.48 : 0.82))
            .frame(width: 102, height: 38)
            .contentShape(Capsule())
        }
        .buttonStyle(SkyCapsulePressStyle())
        .disabled(mode == .cancelling)
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

struct SkyCapsulePressStyle: ButtonStyle {
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
