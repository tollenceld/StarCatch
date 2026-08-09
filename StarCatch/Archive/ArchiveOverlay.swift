import SwiftUI

/// 目标进入感应范围后出现的最小识别标签。
///
/// 它只回答“这是什么”，不提前承担档案阅读；短引线由调用方把它放在目标附近。
struct TargetMicroLabel: View {
    let object: CatalogObject
    let ephemeris: Ephemeris?

    private var label: String {
        let range = ephemeris.map { String(format: "%.0f KM", $0.rangeKm) } ?? "— KM"
        return "\(object.cosparId)  ·  \(range)  ·  \(object.orbitClass)"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .tracking(0.45)
            .foregroundStyle(Palette.inkHigh.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(
            .ultraThinMaterial,
            in: Capsule()
        )
        .background(
            Palette.voidBlack.opacity(0.48),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(object.identityTint.opacity(0.26), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(object.name)，距离 \(ephemeris.map { String(format: "%.0f 公里", $0.rangeKm) } ?? "未知")，\(object.orbitClass) 轨道"
        )
    }

}

/// 稳定锁定后的底部摘要。
///
/// 主视野只保留身份、任务意义与三项关键遥测；完整轨道参数和故事进入深入档案。
struct ArchiveOverlay: View {
    let object: CatalogObject
    let ephemeris: Ephemeris?
    let revealed: Bool
    var captured: Bool = true
    var retainedByInteraction: Bool = false
    var releaseProgress: Double = 0
    var onOpenArchive: () -> Void = {}
    var onInteraction: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onRelease: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var presentationVisible = false
    @GestureState private var dismissTranslation: CGFloat = 0

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var clampedReleaseProgress: Double { min(1, max(0, releaseProgress)) }

    private var statusText: String {
        switch object.status {
        case .active: "ACTIVE"
        case .silent: "SILENT"
        case .derelict: "DERELICT"
        case .debris: "DEBRIS"
        }
    }

    private var statusColor: Color {
        object.status.isActive ? Palette.activeTint : Palette.derelictTint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityHeader

            Text(object.name)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.inkHigh.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.top, 9)

            Text(object.archiveNarrative)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Palette.inkMid.opacity(0.9))
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            telemetry
                .padding(.top, 13)

            archiveAction
                .padding(.top, 12)
        }
        .padding(.horizontal, 17)
        .padding(.top, 15)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassSurface)
        .opacity(presentationVisible ? 1 - 0.38 * clampedReleaseProgress : 0)
        .offset(
            y: max(0, dismissTranslation)
                + (suppressMotion ? 0 : (presentationVisible ? 0 : 12) + 5 * clampedReleaseProgress)
        )
        .simultaneousGesture(dismissGesture)
        .onTapGesture(perform: onInteraction)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "保持目标详情", onInteraction)
        .accessibilityAction(named: "收起目标详情", onDismiss)
        .task(id: object.id) {
            presentationVisible = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(
                suppressMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.38, dampingFraction: 0.88)
            ) {
                presentationVisible = revealed
            }
        }
        .onChange(of: revealed) { _, visible in
            withAnimation(.easeOut(duration: suppressMotion ? 0.1 : 0.2)) {
                presentationVisible = visible
            }
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor.opacity(0.9))
                .frame(width: 4, height: 4)

            Text(statusText)
                .foregroundStyle(statusColor.opacity(0.9))

            Rectangle()
                .fill(Palette.inkFaint.opacity(0.34))
                .frame(width: 0.5, height: 9)

            Text(object.category.title)
                .foregroundStyle(Palette.inkMid.opacity(0.83))

            Rectangle()
                .fill(Palette.inkFaint.opacity(0.34))
                .frame(width: 0.5, height: 9)

            Text(object.orbitClass)
                .foregroundStyle(Palette.inkLow.opacity(0.78))

            Spacer(minLength: 8)

            if retainedByInteraction {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(object.identityTint.opacity(0.76))
                    .accessibilityLabel("详情已保持")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.inkMid.opacity(0.78))
                    .frame(
                        width: ContentTopBarMetrics.controlHeight,
                        height: ContentTopBarMetrics.controlHeight
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起目标详情")
        }
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        .tracking(0.7)
    }

    private var telemetry: some View {
        HStack(spacing: 0) {
            telemetryCell(
                title: "距离",
                value: ephemeris.map { String(format: "%.0f KM", $0.rangeKm) } ?? "—"
            )
            telemetryDivider
            telemetryCell(
                title: "高度",
                value: ephemeris.map { String(format: "%.0f KM", $0.altitudeKm) } ?? "—"
            )
            telemetryDivider
            telemetryCell(
                title: "速度",
                value: ephemeris.map { String(format: "%.2f KM/S", $0.velocityKmS) } ?? "—"
            )
        }
        .padding(.vertical, 10)
        .background(
            Palette.voidBlack.opacity(0.22),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Palette.inkFaint.opacity(0.2), lineWidth: 0.5)
        }
    }

    private func telemetryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(Palette.inkMid.opacity(0.76))
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.inkHigh.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var telemetryDivider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.22))
            .frame(width: 0.5, height: 28)
    }

    private var archiveAction: some View {
        HStack(spacing: 10) {
            Button(action: onOpenArchive) {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 11, weight: .medium))
                    Text("查看档案")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Palette.inkHigh.opacity(0.88))
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开目标的完整任务与轨道资料")

            if captured {
                Rectangle()
                    .fill(Palette.inkFaint.opacity(0.24))
                    .frame(width: 0.5, height: 16)

                Button(action: onRelease) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.slash")
                            .font(.system(size: 10, weight: .medium))
                        Text("解除锁定")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(Palette.inkMid.opacity(0.76))
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("解除当前目标锁定")
            }

            if let reference = object.officialReference {
                Rectangle()
                    .fill(Palette.inkFaint.opacity(0.24))
                    .frame(width: 0.5, height: 16)

                Link(destination: reference.url) {
                    HStack(spacing: 5) {
                        Image(systemName: "network")
                            .font(.system(size: 9.5, weight: .medium))
                        Text("官网")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(object.identityTint.opacity(0.86))
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开\(reference.title)官方页面")
                .accessibilityHint("将在浏览器中打开外部网站")
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.22))
                .frame(height: 0.5)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dismissTranslation) { value, state, _ in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                state = value.translation.height
            }
            .onEnded { value in
                let vertical = max(
                    value.translation.height,
                    value.predictedEndTranslation.height * 0.72
                )
                guard vertical > 58,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                onDismiss()
            }
    }

    @ViewBuilder
    private var glassSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(
                    .regular
                        .tint(Palette.voidBlack.opacity(0.2))
                        .interactive(),
                    in: shape
                )
                .overlay {
                    shape.stroke(Palette.inkFaint.opacity(0.3), lineWidth: 0.6)
                }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(object.identityTint.opacity(0.68))
                        .frame(width: 2, height: 32)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 16)
                }
        } else {
            shape
                .fill(.ultraThinMaterial)
                .background(Palette.voidBlack.opacity(0.62), in: shape)
                .overlay {
                    shape.stroke(Palette.inkFaint.opacity(0.34), lineWidth: 0.6)
                }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(object.identityTint.opacity(0.68))
                        .frame(width: 2, height: 32)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 16)
                }
        }
    }
}
