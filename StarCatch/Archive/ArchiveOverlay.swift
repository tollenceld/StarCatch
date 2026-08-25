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

/// 稳定锁定后的底部摘要。
///
/// 主视野只保留身份、任务意义与三项关键遥测；完整轨道参数和故事进入深入档案。
struct ArchiveOverlay: View {
    let object: CatalogObject
    let ephemeris: Ephemeris?
    let insight: SatelliteInsightSnapshot?
    let revealed: Bool
    var retainedByInteraction: Bool = false
    var releaseProgress: Double = 0
    var onOpenArchive: () -> Void = {}
    var onInteraction: () -> Void = {}
    var onToggleRetention: () -> Void = {}
    var onDismiss: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var presentationVisible = false
    @GestureState private var dismissTranslation: CGFloat = 0

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var clampedReleaseProgress: Double { min(1, max(0, releaseProgress)) }
    private var language: SupportedLanguage { .current }

    private func copy(_ key: String) -> String {
        L10n.text(key, table: "SatelliteText", language: language)
    }

    private var statusText: String {
        switch object.status {
        case .active: copy("status.cataloged")
        case .silent: copy("status.silent")
        case .derelict: copy("status.derelict")
        case .debris: copy("status.debris")
        }
    }

    private var statusColor: Color {
        object.status.isActive ? Palette.activeTint : Palette.derelictTint
    }

    private var fallbackInsight: String {
        let fingerprint = object.orbitFingerprint
        if fingerprint.eccentricity >= 0.08 {
            return L10n.format(
                "insight.orbit.elliptical",
                table: "SatelliteText",
                language: language,
                fingerprint.apogeeKm - fingerprint.perigeeKm
            )
        }
        return L10n.format(
            "insight.orbit.summary",
            table: "SatelliteText",
            language: language,
            fingerprint.periodMinutes,
            fingerprint.inclinationDegrees
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                identityHeader

                Text(object.name)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.inkHigh.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 7)

                Text(
                    insight?.headline(
                        relativeTo: insight?.observationTime ?? Date(),
                        language: language
                    )
                        ?? fallbackInsight
                )
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Palette.inkMid.opacity(0.92))
                    .lineSpacing(1.5)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                insightGraphic
                    .padding(.top, 8)

                telemetry
                    .padding(.top, 8)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onInteraction)

            archiveAction
                .padding(.top, 9)
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassSurface)
        .overlay(alignment: .topTrailing) {
            headerControls
                .padding(.top, 2)
                .padding(.trailing, 2)
        }
        .opacity(presentationVisible ? 1 - 0.38 * clampedReleaseProgress : 0)
        .offset(
            y: max(0, dismissTranslation)
                + (suppressMotion ? 0 : (presentationVisible ? 0 : 12) + 5 * clampedReleaseProgress)
        )
        .simultaneousGesture(dismissGesture)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(copy("accessibility.retain_detail")), onInteraction)
        .accessibilityAction(named: Text(copy("accessibility.collapse_detail")), onDismiss)
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

    @ViewBuilder
    private var insightGraphic: some View {
        if let insight,
           let pass = insight.pass,
           pass.phase != .stationary {
            SatelliteInsightGraphic(
                insight: insight,
                tint: object.identityTint,
                compact: true
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Palette.voidBlack.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Palette.inkFaint.opacity(0.2), lineWidth: 0.5)
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

            Text(object.category.title(language: language))
                .foregroundStyle(Palette.inkMid.opacity(0.83))

            Rectangle()
                .fill(Palette.inkFaint.opacity(0.34))
                .frame(width: 0.5, height: 9)

            Text(object.orbitClass)
                .foregroundStyle(Palette.inkLow.opacity(0.78))

            Spacer(minLength: 8)

        }
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        .tracking(0.7)
        .padding(.trailing, 104)
    }

    private var headerControls: some View {
        HStack(spacing: 2) {
            Button(action: onToggleRetention) {
                Image(systemName: retainedByInteraction ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        retainedByInteraction
                            ? object.identityTint.opacity(0.96)
                            : Palette.inkMid.opacity(0.8)
                    )
                    .frame(width: 34, height: 34)
                    .background(
                        retainedByInteraction
                            ? object.identityTint.opacity(0.11)
                            : Palette.voidBlack.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                retainedByInteraction
                                    ? object.identityTint.opacity(0.48)
                                    : Palette.inkFaint.opacity(0.26),
                                lineWidth: retainedByInteraction ? 0.7 : 0.5
                            )
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                copy(retainedByInteraction ? "accessibility.unpin_detail" : "accessibility.pin_detail")
            )
            .accessibilityHint(
                retainedByInteraction
                    ? copy("accessibility.unpin_detail.hint")
                    : copy("accessibility.pin_detail.hint")
            )

            collapseControl
        }
    }

    /// 收起只隐藏资料卡，不解除卫星锁定。图标和文字组合提高可发现性，
    /// 同时保留 44pt 热区和向下滑动这一直接操控。
    private var collapseControl: some View {
        Button(action: onDismiss) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                Text(copy("action.collapse"))
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(Palette.inkHigh.opacity(0.88))
            .frame(width: 58, height: 34)
            .background(
                Palette.inkHigh.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.inkFaint.opacity(0.34), lineWidth: 0.55)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copy("accessibility.collapse_detail"))
        .accessibilityHint(copy("accessibility.collapse_detail.hint"))
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
