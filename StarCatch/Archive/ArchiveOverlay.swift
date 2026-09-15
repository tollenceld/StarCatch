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
            .background(.ultraThinMaterial, in: Capsule())
            .background(Palette.voidBlack.opacity(0.48), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(object.identityTint.opacity(0.26), lineWidth: 0.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                L10n.format(
                    "accessibility.micro_label",
                    table: "SatelliteText",
                    object.name,
                    ephemeris.map { String(format: "%.0f KM", $0.rangeKm) }
                        ?? L10n.text("value.unknown", table: "SatelliteText"),
                    object.orbitClass
                )
            )
    }
}

/// 自动锁定后的持久目标摘要。移动准星不会改变或关闭它；右上角叉号是唯一可见退出入口。
struct ArchiveOverlay: View {
    let object: CatalogObject
    let ephemeris: Ephemeris?
    var dismissalProgress: Double = 0
    var onOpenArchive: () -> Void = {}
    var onDismiss: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.chromePreviewReducedTransparency) private var previewReduceTransparency
    @Environment(\.forceLegacyMaterial) private var forceLegacyMaterial
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var presentationVisible = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var reduceTransparency: Bool {
        systemReduceTransparency || previewReduceTransparency
    }
    private var clampedDismissalProgress: Double {
        min(1, max(0, dismissalProgress))
    }
    private var language: SupportedLanguage { .current }

    private func copy(_ key: String) -> String {
        L10n.text(key, table: "SatelliteText", language: language)
    }

    private var statusText: String {
        switch object.status {
        case .active: copy("status.active")
        case .silent: copy("status.silent")
        case .derelict: copy("status.derelict")
        case .debris: copy("status.debris")
        }
    }

    private var statusColor: Color {
        object.status.isActive ? Palette.activeTint : Palette.derelictTint
    }

    private var missionRoleKey: String? {
        switch object.kind {
        case "telescope": "telescope"
        case "station": "station"
        case "nav": "navigation"
        case "comms": "communications"
        case "weather": "weather"
        case "science": "science"
        case "debris", "rocket_body": "orbital_remnant"
        default: nil
        }
    }

    private var missionRoleTitle: String {
        missionRoleKey.map { copy("archive.role.\($0).title") }
            ?? object.category.title(language: language)
    }

    private var missionRoleSummary: String {
        missionRoleKey.map { copy("target.role.\($0).summary") }
            ?? object.category.subtitle(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(object.name)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.inkHigh.opacity(0.97))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.trailing, 48)

            identityHeader
                .padding(.top, 8)

            Text(missionRoleSummary)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Palette.inkMid.opacity(0.9))
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            telemetry
                .padding(.top, 10)

            archiveAction
                .padding(.top, 10)
        }
        .padding(.horizontal, 15)
        .padding(.top, 15)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassSurface)
        .overlay(alignment: .topTrailing) {
            closeControl
                .padding(.top, 2)
                .padding(.trailing, 2)
        }
        .opacity(presentationVisible ? 1 - clampedDismissalProgress : 0)
        .offset(
            y: suppressMotion
                ? 0
                : (presentationVisible ? 0 : 12) + 8 * clampedDismissalProgress
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { onDismiss() }
        .task(id: object.id) {
            presentationVisible = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(
                suppressMotion
                    ? .easeOut(duration: 0.12)
                    : Motion.interfaceExpand
            ) {
                presentationVisible = true
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

            metadataDivider

            Text(missionRoleTitle)
                .foregroundStyle(Palette.inkMid.opacity(0.83))

            metadataDivider

            Text(object.orbitClass)
                .foregroundStyle(Palette.inkLow.opacity(0.78))

            Spacer(minLength: 8)
        }
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        .tracking(0.7)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.34))
            .frame(width: 0.5, height: 9)
    }

    private var closeControl: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkMid.opacity(0.84))
                .frame(width: 34, height: 34)
                .background(
                    Palette.voidBlack.opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.inkFaint.opacity(0.26), lineWidth: 0.5)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copy("accessibility.close_detail"))
        .accessibilityHint(copy("accessibility.close_detail.hint"))
    }

    private var telemetry: some View {
        HStack(spacing: 0) {
            telemetryCell(
                title: copy("archive.field.range"),
                value: ephemeris.map { String(format: "%.0f KM", $0.rangeKm) } ?? "—"
            )
            telemetryDivider
            telemetryCell(
                title: copy("archive.field.altitude"),
                value: ephemeris.map { String(format: "%.0f KM", $0.altitudeKm) } ?? "—"
            )
            telemetryDivider
            telemetryCell(
                title: copy("archive.field.speed"),
                value: ephemeris.map { String(format: "%.2f KM/S", $0.velocityKmS) } ?? "—"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            Palette.voidBlack.opacity(0.18),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.inkFaint.opacity(0.22), lineWidth: 0.5)
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
        Button(action: onOpenArchive) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(object.identityTint.opacity(0.09))
                        .frame(width: 26, height: 26)
                    Image(systemName: "book.closed")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(object.identityTint.opacity(0.9))
                }
                Text(copy("action.view_archive"))
                    .font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 8)
                Text(copy("action.view_archive.subtitle"))
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Palette.inkMid.opacity(0.72))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(object.identityTint.opacity(0.72))
            }
            .foregroundStyle(Palette.inkHigh.opacity(0.88))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                Palette.inkHigh.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(object.identityTint.opacity(0.24), lineWidth: 0.55)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(copy("action.view_archive.hint"))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.22))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var glassSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if reduceTransparency {
            shape
                .fill(Palette.sheetBackground)
                .overlay {
                    shape.stroke(Palette.inkFaint.opacity(0.5), lineWidth: 0.6)
                }
        } else if #available(iOS 26.0, *), !forceLegacyMaterial {
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
        } else {
            shape
                .fill(.ultraThinMaterial)
                .background(Palette.voidBlack.opacity(0.62), in: shape)
                .overlay {
                    shape.stroke(Palette.inkFaint.opacity(0.34), lineWidth: 0.6)
                }
        }
    }
}
