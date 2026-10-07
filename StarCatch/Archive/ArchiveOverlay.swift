import SwiftUI

/// Identity is available on the first acquisition sample; it never waits for
/// the background story, precise ephemeris, or track preparation.
struct TargetMicroLabel: View {
    let object: CatalogObject
    let progress: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.chromePreviewReducedTransparency) private var previewReduceTransparency

    private var identity: String {
        let role = targetRoleKey(object.kind).map {
            L10n.text("archive.role.\($0).title", table: "SatelliteText")
        } ?? object.category.title
        return "\(role) · \(object.orbitClass) · N\(object.noradId)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(object.name)
                .instrumentFont(16, relativeTo: .headline, weight: .semibold)
                .foregroundStyle(Palette.Text.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(identity)
                .font(Typography.statusTag)
                .foregroundStyle(Palette.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text(L10n.text("capture.identity.hold", table: "SatelliteText"))
                    .font(Typography.statusTag)
                    .foregroundStyle(Palette.signal)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    ForEach(0 ..< 12, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Double(index) < progress * 12 ? Palette.signal : Palette.Text.tertiary.opacity(0.22))
                            .frame(width: 3, height: 8)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            if reduceTransparency || previewReduceTransparency {
                shape.fill(Palette.sheetBackground)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(Palette.voidBlack.opacity(0.5)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.signal.opacity(0.3), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 自动锁定后的持久目标摘要。移动准星不会改变或关闭它；右上角叉号是唯一可见退出入口。
struct ArchiveOverlay: View {
    let object: CatalogObject
    let ephemeris: Ephemeris?
    var story: SatelliteStory? = nil
    var insight: SatelliteInsightSnapshot? = nil
    var trace: SatelliteTrackSnapshot? = nil
    var dismissalProgress: Double = 0
    var onOpenArchive: () -> Void = {}
    var onDismiss: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.chromePreviewReducedTransparency) private var previewReduceTransparency
    @Environment(\.forceLegacyMaterial) private var forceLegacyMaterial
    @AppStorage("reducedMotion") private var reducedMotion = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    private var missionRoleKey: String? { targetRoleKey(object.kind) }

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
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    summaryContent
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: 380)
            } else {
                summaryContent
            }

            archiveAction
                .padding(.top, 16)
        }
        .padding(.horizontal, AppChromeMetrics.edgeInset)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SkyGlassSurface(
            shape: RoundedRectangle(cornerRadius: AppChromeMetrics.commandRailCornerRadius, style: .continuous),
            darkening: 0.15,
            interactive: false
        ))
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

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(object.name)
                .font(Typography.objectName)
                .foregroundStyle(Palette.Text.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 44)

            identityHeader
                .padding(.top, 8)
            if let story, story.scope == .family {
                Text(copy("archive.reading.family_scope"))
                    .font(Typography.fieldLabel)
                    .foregroundStyle(object.identityTint)
                    .padding(.top, 8)
            }

            Text(story?.lead ?? missionRoleSummary)
                .font(Typography.readingCompact)
                .foregroundStyle(Palette.Text.secondary)
                .lineSpacing(2)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if let trace {
                SatelliteMotionTraceView(trace: trace, tint: object.identityTint, compact: true)
                    .padding(.top, 16)
            }
            if let movement = insight?.movementLabel(language: language) {
                Text(movement)
                    .font(Typography.readingCompact)
                    .foregroundStyle(object.identityTint)
                    .padding(.top, 8)
            }

            telemetry
                .padding(.top, 16)
        }
    }

    private var identityHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                identityStatus
                metadataDivider
                Text(missionRoleTitle)
                metadataDivider
                Text(object.orbitClass)
            }
            VStack(alignment: .leading, spacing: 4) {
                identityStatus
                Text("\(missionRoleTitle) · \(object.orbitClass)")
            }
        }
        .font(Typography.fieldLabel)
        .foregroundStyle(Palette.Text.secondary)
    }

    private var identityStatus: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor.opacity(0.9))
                .frame(width: 4, height: 4)

            Text(statusText)
                .foregroundStyle(statusColor.opacity(0.9))

        }
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.34))
            .frame(width: 0.5, height: 9)
    }

    private var closeControl: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.Text.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(copy("accessibility.close_detail"))
        .accessibilityHint(copy("accessibility.close_detail.hint"))
    }

    private var telemetry: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            telemetryCell(
                title: copy("archive.field.range"),
                value: ephemeris.map { String(format: "%.0f", $0.rangeKm) } ?? "—",
                unit: "KM"
            )
            if !dynamicTypeSize.isAccessibilitySize { telemetryDivider }
            telemetryCell(
                title: copy("archive.field.altitude"),
                value: ephemeris.map { String(format: "%.0f", $0.altitudeKm) } ?? "—",
                unit: "KM"
            )
            if !dynamicTypeSize.isAccessibilitySize { telemetryDivider }
            telemetryCell(
                title: copy("archive.field.speed"),
                value: ephemeris.map { String(format: "%.2f", $0.velocityKmS) } ?? "—",
                unit: "KM/S"
            )
        }
        .padding(.vertical, 4)
    }

    private func telemetryCell(title: String, value: String, unit: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return layout {
            Text(title)
                .font(Typography.fieldLabel)
                .foregroundStyle(Palette.Text.tertiary)
            if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            SatelliteReadout(value: value, unit: unit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var telemetryDivider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.32))
            .frame(width: 0.5, height: 44)
    }

    private var archiveAction: some View {
        Button(action: onOpenArchive) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.footnote.weight(.medium))
                Text(copy("action.view_archive"))
                    .font(Typography.guide.weight(.medium))
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(Palette.signal)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.top, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityHint(copy("action.view_archive.hint"))
        .overlay(alignment: .top) { ContentHairline() }
    }

    @ViewBuilder
    private var glassSurface: some View {
        let shape = RoundedRectangle(cornerRadius: AppChromeMetrics.commandRailCornerRadius, style: .continuous)
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


private func targetRoleKey(_ kind: String) -> String? {
    switch kind {
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
