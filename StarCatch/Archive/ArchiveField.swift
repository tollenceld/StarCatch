import SwiftUI

/// 档案单行：标签 + 值。等宽、克制。
struct ArchiveField: View {
    let label: String
    let value: String
    var valueColor: Color = Palette.inkMid

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(Typography.archiveFieldLabel)
                .tracking(1.0)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(Typography.archiveDataValue)
                .tracking(Typography.dataValueTracking)
                .foregroundStyle(valueColor.opacity(Palette.Level.full))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .layoutPriority(1)
        }
    }
}

/// 逐行浮现容器：fade + 2pt 上浮，行间 stagger。
struct ArchiveLineReveal: ViewModifier {
    let index: Int
    let revealed: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: suppressMotion || revealed ? 0 : Motion.archiveRise)
            .animation(suppressMotion ? .easeOut(duration: 0.16) : animation, value: revealed)
    }

    private var animation: Animation {
        if revealed {
            return Motion.archiveRevealLine.delay(Double(index) * Motion.archiveRevealStagger)
        } else {
            let reverseIndex = max(0, Motion.archiveLineCount - 1 - index)
            return Motion.archiveDismissLine.delay(Double(reverseIndex) * Motion.archiveDismissStagger)
        }
    }
}

extension View {
    func archiveReveal(index: Int, revealed: Bool) -> some View {
        modifier(ArchiveLineReveal(index: index, revealed: revealed))
    }
}
