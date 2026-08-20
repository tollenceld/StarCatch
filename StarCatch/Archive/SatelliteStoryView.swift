import SwiftUI

/// 单体卫星或大型星座的离线深度档案。策展事实与当前节点的实时轨道读数
/// 明确分区，避免把故事和瞬时位置混成同一种“参数表”。
struct SatelliteStoryView: View {
    let object: CatalogObject
    let story: SatelliteStory
    let ephemeris: Ephemeris?
    let insight: SatelliteInsightSnapshot?
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var revealed = false
    @State private var expandedChapterID: String?
    @State private var missionHistoryExpanded = false
    @State private var sourcesExpanded = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var language: SupportedLanguage { .current }

    private func copy(_ key: String) -> String {
        L10n.text(key, table: "SatelliteText", language: language)
    }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()
            StaticDustBackdrop()
                .ignoresSafeArea()
                .opacity(0.22)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    identityHeader
                        .padding(.bottom, ephemeris == nil ? 20 : 14)

                    if let ephemeris {
                        observationSnapshot(ephemeris)
                            .padding(.bottom, 20)
                    }

                    orbitFingerprintModule
                        .padding(.bottom, 22)

                    currentTargetModule
                        .padding(.bottom, 22)

                    sectionLabel(copy(story.scope == .family ? "archive.section.family" : "archive.section.mission"))
                    Text(story.lead)
                        .font(Typography.readingBody)
                        .tracking(Typography.readingBodyTracking)
                        .lineSpacing(4)
                        .foregroundStyle(Palette.inkMid.opacity(0.88))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.bottom, story.officialReference == nil ? 20 : 12)

                    if let reference = story.officialReference {
                        officialReferenceLink(reference)
                            .padding(.bottom, 20)
                    }

                    sectionLabel(copy("archive.section.facts"))
                    VStack(spacing: 0) {
                        ForEach(preferredFacts) { fact in
                            storyField(fact.label, fact.value)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    if !story.chapters.isEmpty {
                        sectionLabel(copy("archive.section.notes"))
                        VStack(spacing: 0) {
                            ForEach(story.chapters) { chapter in
                                chapterDisclosure(chapter)
                            }
                        }
                        .padding(.top, 7)
                        .padding(.bottom, 20)
                    }

                    if !story.milestones.isEmpty {
                        compactDisclosure(
                            title: copy("archive.history.title"),
                            detail: L10n.format("archive.history.count", table: "SatelliteText", language: language, story.milestones.count),
                            isExpanded: $missionHistoryExpanded
                        ) {
                            milestoneRail
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        }
                    }

                    compactDisclosure(
                        title: copy("archive.sources.title"),
                        detail: L10n.format("archive.sources.count", table: "SatelliteText", language: language, story.sources.count),
                        isExpanded: $sourcesExpanded
                    ) {
                        sourceNote
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 14)
                .padding(.bottom, 42)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ArchiveTopBar(
                backTitle: copy("navigation.sky"),
                title: copy("navigation.object_archive"),
                onBack: onDismiss
            )
        }
        .appEdgeBackGesture(action: onDismiss)
        .opacity(revealed ? 1 : 0)
        .offset(y: suppressMotion ? 0 : revealed ? 0 : 8)
        .onAppear {
            withAnimation(suppressMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.28)) {
                revealed = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(story.eyebrow)
                .font(Typography.statusTag)
                .tracking(1.35)
                .foregroundStyle(object.identityTint.opacity(0.82))

            Text(object.deepArchiveTitle)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(story.program)
                .font(Typography.guide)
                .tracking(1.0)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))

            HStack(spacing: 9) {
                Rectangle()
                    .fill(object.identityTint.opacity(0.62))
                    .frame(width: 22, height: 0.7)
                Text(story.organization)
                    .font(Typography.statusTag)
                    .tracking(0.75)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                    .lineLimit(2)
            }
            .padding(.top, 3)
        }
    }

    private func officialReferenceLink(
        _ reference: SatelliteStory.OfficialReference
    ) -> some View {
        Link(destination: reference.url) {
            HStack(spacing: 11) {
                Image(systemName: "network")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("官方任务页面")
                        .font(Typography.guide)
                        .foregroundStyle(Palette.inkHigh.opacity(0.9))
                    Text(reference.title)
                        .font(Typography.statusTag)
                        .tracking(0.45)
                        .foregroundStyle(Palette.inkMid.opacity(0.74))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(object.identityTint.opacity(0.82))
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .background(
                object.identityTint.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(object.identityTint.opacity(0.3), lineWidth: 0.55)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            L10n.format("accessibility.open_official", table: "SatelliteText", language: language, reference.title)
        )
        .accessibilityHint(copy("accessibility.external_browser"))
    }

    private var preferredFacts: [SatelliteStory.Fact] {
        let priority = language == .english
            ? ["Mission", "Type", "Period", "Inclination", "Perigee / apogee", "Orbit"]
            : ["任务", "类型", "周期", "倾角", "估算近 / 远地点", "形态", "主镜", "观测", "档案范围"]
        let indexed = Dictionary(uniqueKeysWithValues: priority.enumerated().map {
            ($0.element, $0.offset)
        })
        return story.facts
            .filter { indexed[$0.label] != nil }
            .sorted {
                (indexed[$0.label] ?? .max) < (indexed[$1.label] ?? .max)
            }
            .prefix(5)
            .map { $0 }
    }

    private func observationSnapshot(_ ephemeris: Ephemeris) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            if let insight {
                SatelliteInsightGraphic(
                    insight: insight,
                    tint: object.identityTint
                )
            }

            HStack(spacing: 0) {
                observationCell(
                    label: "AZ",
                    value: String(format: "%03.0f°", normalizedDegrees(ephemeris.azimuth))
                )
                observationDivider
                observationCell(
                    label: "EL",
                    value: String(format: "%+.1f°", ephemeris.elevation * 180 / .pi)
                )
                observationDivider
                observationCell(
                    label: copy("archive.field.range"),
                    value: String(format: "%.0f KM", ephemeris.rangeKm)
                )
            }

            HStack(spacing: 0) {
                observationCell(
                    label: copy("archive.field.altitude"),
                    value: String(format: "%.0f KM", ephemeris.altitudeKm)
                )
                observationDivider
                observationCell(
                    label: copy("archive.field.speed"),
                    value: String(format: "%.2f KM/S", ephemeris.velocityKmS)
                )
                observationDivider
                observationCell(label: copy("archive.field.orbit"), value: object.orbitClass)
            }

            Text(observationSentence(ephemeris))
                .font(Typography.archiveNarrative)
                .tracking(0.25)
                .foregroundStyle(Palette.inkMid.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            if let movement = insight?.movementLabel(language: language) {
                Text(movement)
                    .font(Typography.statusTag)
                    .tracking(0.55)
                    .foregroundStyle(object.identityTint.opacity(0.78))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            object.identityTint.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(object.identityTint.opacity(0.25), lineWidth: 0.55)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(observationSentence(ephemeris))
    }

    private var orbitFingerprintModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(copy("archive.section.orbit_fingerprint"))
            OrbitFingerprintView(
                fingerprint: object.orbitFingerprint,
                tint: object.identityTint
            )
            VStack(spacing: 0) {
                storyField(
                    copy("archive.field.period"),
                    String(format: "%.1f MIN", object.orbitFingerprint.periodMinutes)
                )
                storyField(
                    copy("archive.field.inclination"),
                    String(format: "%.2f°", object.orbitFingerprint.inclinationDegrees)
                )
                storyField(
                    copy("archive.field.eccentricity"),
                    String(format: "%.6f", object.orbitFingerprint.eccentricity)
                )
                storyField(
                    copy("archive.field.apsides"),
                    String(
                        format: "%.0f / %.0f KM",
                        object.orbitFingerprint.perigeeKm,
                        object.orbitFingerprint.apogeeKm
                    )
                )
            }
        }
    }

    private var currentTargetModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(copy("archive.section.current_object"))
            VStack(spacing: 0) {
                storyField("NORAD", "N\(object.noradId)")
                storyField("COSPAR", object.cosparId)
                storyField(copy("archive.field.launch"), object.launched)
                storyField(copy("archive.field.orbit"), object.orbitClass)
                if let cohort = insight?.launchCohort {
                    storyField(
                        copy("archive.field.launch_cohort"),
                        "\(cohort.ordinal) / \(cohort.memberCount) · \(cohort.launchKey)"
                    )
                }
                if let comparison = insight?.familyComparison {
                    storyField(
                        copy("archive.field.family_position"),
                        L10n.format(
                            "archive.value.family_position",
                            table: "SatelliteText",
                            language: language,
                            comparison.family.title,
                            comparison.altitudeDeltaKm
                        )
                    )
                }
                if let point = insight?.subpoint {
                    storyField(
                        copy("archive.field.subpoint"),
                        String(
                            format: "%.1f°%@  %.1f°%@",
                            abs(point.latitude), point.latitude >= 0 ? "N" : "S",
                            abs(point.longitude), point.longitude >= 0 ? "E" : "W"
                        )
                    )
                }
            }
        }
    }

    private func observationCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.statusTag)
                .tracking(0.85)
                .foregroundStyle(Palette.inkLow.opacity(0.7))
            Text(value)
                .font(Typography.archiveDataValue)
                .tracking(0.25)
                .foregroundStyle(Palette.inkHigh.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var observationDivider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.25))
            .frame(width: 0.5, height: 28)
            .padding(.horizontal, 8)
    }

    private func normalizedDegrees(_ radians: Double) -> Double {
        let degrees = (radians * 180 / .pi).truncatingRemainder(dividingBy: 360)
        return degrees >= 0 ? degrees : degrees + 360
    }

    private func observationSentence(_ ephemeris: Ephemeris) -> String {
        let azimuth = normalizedDegrees(ephemeris.azimuth)
        let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let index = Int((azimuth + 22.5) / 45).quotientAndRemainder(dividingBy: 8).remainder
        let direction = copy("direction.\(directions[index])")
        let visibility = copy(
            ephemeris.elevation > 0 ? "visibility.above_horizon" : "visibility.below_horizon"
        )
        return L10n.format(
            "archive.observation.sentence",
            table: "SatelliteText",
            language: language,
            direction,
            visibility
        )
    }

    private func chapterDisclosure(_ chapter: SatelliteStory.Chapter) -> some View {
        let expanded = expandedChapterID == chapter.id
        return DisclosureGroup(
            isExpanded: Binding(
                get: { expandedChapterID == chapter.id },
                set: { expandedChapterID = $0 ? chapter.id : nil }
            )
        ) {
            Text(chapter.body)
                .font(Typography.readingCompact)
                .tracking(Typography.readingCompactTracking)
                .lineSpacing(4)
                .foregroundStyle(Palette.inkMid.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 12)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(expanded ? object.identityTint : Palette.inkFaint)
                    .frame(width: 4, height: 4)
                Text(chapter.title)
                    .font(Typography.guide)
                    .tracking(0.55)
                    .foregroundStyle(Palette.inkHigh.opacity(expanded ? 0.9 : 0.78))
            }
            .frame(minHeight: 38)
        }
        .tint(object.identityTint.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.24))
                .frame(height: 0.5)
        }
    }

    private func compactDisclosure<Content: View>(
        title: String,
        detail: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(Typography.guide)
                    .tracking(0.55)
                    .foregroundStyle(Palette.inkHigh.opacity(0.8))
                Spacer(minLength: 8)
                Text(detail)
                    .font(Typography.statusTag)
                    .tracking(0.4)
                    .foregroundStyle(Palette.inkLow.opacity(0.58))
            }
            .frame(minHeight: 42)
        }
        .tint(object.identityTint.opacity(0.7))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.25))
                .frame(height: 0.5)
        }
    }

    private var milestoneRail: some View {
        VStack(spacing: 0) {
            ForEach(Array(story.milestones.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == 0 ? object.identityTint : Palette.inkFaint)
                            .frame(width: 5, height: 5)
                        if index < story.milestones.count - 1 {
                            Rectangle()
                                .fill(Palette.inkFaint.opacity(0.38))
                                .frame(width: 0.5, height: 38)
                        }
                    }
                    .frame(width: 8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.time)
                            .font(Typography.statusTag)
                            .tracking(Typography.statusTagTracking)
                            .foregroundStyle(object.identityTint.opacity(0.72))
                        Text(item.event)
                            .font(Typography.archiveNarrative)
                            .tracking(0.55)
                            .foregroundStyle(Palette.inkMid.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, index < story.milestones.count - 1 ? 12 : 0)
                }
            }
        }
    }

    private func storyField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(Typography.archiveDataValue)
                .tracking(Typography.dataValueTracking)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.26))
                .frame(height: 0.5)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(Typography.fieldLabel)
                .tracking(Typography.fieldLabelTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.38))
                .frame(height: 0.5)
        }
    }

    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(copy("archive.sources.offline_edition"))
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.inkLow.opacity(0.52))
            ForEach(story.sources) { source in
                sourceRow(source)
            }
            Text(copy("archive.sources.calculation_note"))
                .font(Typography.archiveNarrative)
                .tracking(0.45)
                .foregroundStyle(Palette.inkLow.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: StorySource) -> some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(source.provenance.title)
                .font(Typography.statusTag)
                .tracking(0.45)
                .foregroundStyle(object.identityTint.opacity(0.76))
                .padding(.horizontal, 7)
                .frame(minHeight: 22)
                .background(
                    object.identityTint.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(Typography.archiveNarrative)
                    .foregroundStyle(Palette.inkMid.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Text(source.scope.title)
                    .font(Typography.statusTag)
                    .tracking(0.35)
                    .foregroundStyle(Palette.inkLow.opacity(0.58))
            }
            Spacer(minLength: 4)
            if source.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Palette.inkLow.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .contentShape(Rectangle())

        if let url = source.url {
            Link(destination: url) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// 主天空底部的独立二级入口。它不再跟随空间信息面板移动，始终位于拇指可达区。
struct SatelliteStoryEntryControl: View {
    let tint: Color
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                button
                    .glassEffect(
                        .regular.tint(tint.opacity(0.08)).interactive(),
                        in: Capsule()
                    )
            } else {
                button
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Palette.voidBlack.opacity(0.82), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(tint.opacity(0.44), lineWidth: 0.65)
                    }
            }
        }
        .accessibilityLabel(L10n.text("archive.open", table: "SatelliteText"))
        .accessibilityHint(L10n.text("archive.open.hint", table: "SatelliteText"))
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tint.opacity(0.88))
                Text(L10n.text("archive.open", table: "SatelliteText"))
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(1.1)
                Rectangle()
                    .fill(tint.opacity(0.56))
                    .frame(width: 16, height: 0.65)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8.5, weight: .semibold))
            }
            .foregroundStyle(Palette.inkHigh.opacity(0.9))
            .frame(width: 154, height: 42)
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.44), lineWidth: 0.65)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SkyCapsulePressStyle())
    }
}
