import SwiftUI

/// 顶部状态指示器。
///
/// 旧设计把 AZ/EL 原始读数常驻顶部，用户需要自己翻译这串数字意味着什么。
/// 这里改为先回答"仪器现在处于什么状态"，坐标退居为同一枚指示器右侧的次级读数：
/// 一眼可读状态，需要精度时再看数字。
struct SkyStatusIndicator: View {

    /// 仪器状态。顺序即优先级：降级状态永远盖过常规观测状态。
    enum Mode: Equatable {
        /// 正常实时观测。
        case observing
        /// 准星正在感应某个目标。
        case acquiring
        /// 已建立持续捕获。
        case locked(name: String)
        /// 全局星图（可能位于非 LIVE 时刻）。
        case field(timeLabel: String)
        /// 姿态或位置降级，点位方向不可信。
        case degraded(reason: String)

        var label: String {
            switch self {
            case .observing: "正在观测"
            case .acquiring: "正在感应"
            case .locked(let name): name
            case .field(let timeLabel): timeLabel
            case .degraded(let reason): reason
            }
        }

        /// 指示灯颜色。只用 signal 与灰阶两种语义，不引入第三种颜色通道。
        var indicatorTint: Color {
            switch self {
            case .observing, .field: Palette.inkMid
            case .acquiring, .locked: Palette.signal
            case .degraded: Palette.legacyTint
            }
        }

        /// 呼吸只给"正在进行中"的状态；稳定状态保持恒定，避免持续闪动。
        var breathes: Bool {
            switch self {
            case .acquiring: true
            case .observing, .locked, .field, .degraded: false
            }
        }
    }

    let mode: Mode
    /// 次级坐标读数，nil 时只显示状态。
    let coordinates: String?
    /// 整体存在感，由捕获状态驱动后退。
    let presence: Double

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 6.0, paused: !mode.breathes || suppressMotion)) { timeline in
            let breath = mode.breathes && !suppressMotion
                ? Motion.breath(at: timeline.date.timeIntervalSinceReferenceDate)
                : 1

            HStack(spacing: 8) {
                indicator(breath: breath)

                Text(mode.label)
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.present))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let coordinates {
                    Rectangle()
                        .fill(Palette.inkFaint.opacity(0.34))
                        .frame(width: 0.5, height: 11)

                    Text(coordinates)
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                // 深色天空上需要一层极弱的介质才能保证读数可读；不使用亮色卡片。
                Capsule()
                    .fill(Palette.voidBlack.opacity(0.72))
                    .overlay {
                        Capsule()
                            .stroke(Palette.inkFaint.opacity(0.30), lineWidth: 0.5)
                    }
            }
        }
        .opacity(presence)
        .animation(
            suppressMotion ? .easeOut(duration: 0.14) : Motion.interfaceExpand,
            value: mode
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 指示灯：一枚实心点加一圈同色细环。环只在进行中的状态出现。
    private func indicator(breath: Double) -> some View {
        ZStack {
            if mode.breathes {
                Circle()
                    .stroke(mode.indicatorTint.opacity(0.34 * breath), lineWidth: 0.5)
                    .frame(width: 9, height: 9)
            }
            Circle()
                .fill(mode.indicatorTint.opacity(Palette.Level.present * breath))
                .frame(width: 3.5, height: 3.5)
        }
        .frame(width: 9, height: 9)
    }

    private var accessibilityLabel: String {
        if let coordinates {
            return "\(mode.label)，\(coordinates)"
        }
        return mode.label
    }
}
