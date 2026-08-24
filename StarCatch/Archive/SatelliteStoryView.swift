import SwiftUI

/// 单体卫星或大型星座的离线深度档案。策展事实与当前节点的实时轨道读数
/// 明确分区，避免把故事和瞬时位置混成同一种“参数表”。
struct SatelliteStoryView: View {
    private enum ArchiveSection: String, CaseIterable, Identifiable {
        case observation
        case mission
        case data

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .observation: "archive.tab.observation"
            case .mission: "archive.tab.mission"
            case .data: "archive.tab.data"
            }
        }

        var symbolName: String {
            switch self {
            case .observation: "scope"
            case .mission: "sparkles"
            case .data: "waveform.path.ecg"
            }
        }
    }

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
    @State private var selectedSection: ArchiveSection = .observation
    @Namespace private var sectionSelection

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
                    identityHero
                        .padding(.bottom, 22)

                    archiveSectionPicker
                        .padding(.bottom, 22)

                    selectedSectionContent
                        .id(selectedSection)
                        .transition(
                            suppressMotion
                                ? .opacity
                                : .opacity.combined(with: .offset(y: 5))
                        )
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

    private var identityHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: missionRoleSymbol)
                    .font(.system(size: 10, weight: .medium))
                Text(missionRoleTitle)
                Spacer(minLength: 8)
                Text(object.orbitClass)
            }
            .font(Typography.statusTag)
            .tracking(language == .english ? 0.85 : 0.18)
            .foregroundStyle(object.identityTint.opacity(0.88))
            .padding(.bottom, 10)

            Text(object.deepArchiveTitle)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(missionRoleSummary)
                .font(.system(.headline, design: .default, weight: .medium))
                .foregroundStyle(Palette.inkHigh.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)

            HStack(spacing: 7) {
                archiveBadge(story.eyebrow)
                archiveBadge("NORAD \(object.noradId)")
                if object.family != nil {
                    archiveBadge(copy("archive.badge.series"))
                }
            }
            .padding(.top, 14)
        }
    }

    private func archiveBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .tracking(language == .english ? 0.45 : 0.08)
            .foregroundStyle(Palette.inkMid.opacity(0.74))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Palette.inkHigh.opacity(0.035), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Palette.inkFaint.opacity(0.34), lineWidth: 0.5)
            }
    }

    private var archiveSectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(ArchiveSection.allCases) { section in
                Button {
                    withAnimation(suppressMotion ? .easeOut(duration: 0.1) : .easeInOut(duration: 0.22)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.symbolName)
                            .font(.system(size: 9.5, weight: .medium))
                        Text(copy(section.titleKey))
                            .lineLimit(1)
                    }
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(
                        selectedSection == section
                            ? Palette.inkHigh.opacity(0.92)
                            : Palette.inkLow.opacity(0.68)
                    )
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(object.identityTint.opacity(0.09))
                                .matchedGeometryEffect(id: "archive-section", in: sectionSelection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.inkHigh.opacity(0.025), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Palette.inkFaint.opacity(0.34), lineWidth: 0.55)
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .observation:
            observationSection
        case .mission:
            missionSection
        case .data:
            dataSection
        }
    }

    private var observationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(copy("archive.section.observe_now"))
            if let ephemeris {
                observationSnapshot(ephemeris)
                    .padding(.top, 11)
            } else {
                Text(copy("archive.observation.unavailable"))
                    .font(Typography.readingCompact)
                    .foregroundStyle(Palette.inkMid.opacity(0.7))
                    .padding(.top, 13)
            }

            sectionLabel(copy("archive.section.orbit_at_glance"))
                .padding(.top, 24)
            OrbitFingerprintView(
                fingerprint: object.orbitFingerprint,
                tint: object.identityTint,
                motion: insight?.motion
            )
            .padding(.top, 8)
            HStack(spacing: 0) {
                compactMetric(
                    copy("archive.field.period"),
                    String(format: "%.1f MIN", object.orbitFingerprint.periodMinutes)
                )
                observationDivider
                compactMetric(
                    copy("archive.field.inclination"),
                    String(format: "%.2f°", object.orbitFingerprint.inclinationDegrees)
                )
                observationDivider
                compactMetric(
                    copy("archive.field.apsides_compact"),
                    String(
                        format: "%.0f / %.0f KM",
                        object.orbitFingerprint.perigeeKm,
                        object.orbitFingerprint.apogeeKm
                    )
                )
            }
            .padding(.top, 2)
        }
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(copy(story.scope == .family ? "archive.section.family" : "archive.section.mission_brief"))
            Text(story.lead)
                .font(Typography.readingBody)
                .tracking(Typography.readingBodyTracking)
                .lineSpacing(Typography.readingBodyLineSpacing)
                .foregroundStyle(Palette.inkMid.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.bottom, story.officialReference == nil ? 22 : 14)

            if let reference = story.officialReference {
                officialReferenceLink(reference)
                    .padding(.bottom, 22)
            }

            if !preferredFacts.isEmpty {
                sectionLabel(copy("archive.section.facts"))
                VStack(spacing: 0) {
                    ForEach(preferredFacts) { fact in
                        storyField(fact.label, fact.value)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

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
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            orbitFingerprintModule
                .padding(.bottom, 24)
            currentTargetModule
                .padding(.bottom, 20)
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
                    Text(copy("archive.official_reference"))
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

    private var missionFilter: CatalogFilter? {
        switch object.family {
        case .starlink: return .starlink
        case .oneweb: return .oneweb
        case .qianfan, .hulianwang: return .chinaConstellations
        case .kuiper: return .kuiper
        case .iridium, .globalstar, .orbcomm: return .mobileConstellations
        case nil: break
        }
        if object.kind == "nav" { return .navigation }
        if object.kind == "comms" { return .communications }
        if object.isRecognizedHumanScienceMission { return .humanScience }
        if object.isRecognizedEarthMission { return .earthObservation }
        if object.category == .legacy || object.status != .active { return .orbitalHeritage }
        return nil
    }

    private var missionRoleTitle: String {
        explicitMissionRole?.title
            ?? missionFilter?.title
            ?? object.category.title(language: language)
    }

    private var missionRoleSummary: String {
        explicitMissionRole?.summary
            ?? missionFilter?.subtitle
            ?? object.category.subtitle(language: language)
    }

    private var missionRoleSymbol: String {
        explicitMissionRole?.symbol
            ?? missionFilter?.symbolName
            ?? object.category.symbolName
    }

    private var explicitMissionRole: (title: String, summary: String, symbol: String)? {
        let key: String
        let symbol: String
        switch object.kind {
        case "telescope":
            key = "telescope"
            symbol = "telescope"
        case "station":
            key = "station"
            symbol = "person.2"
        case "nav":
            key = "navigation"
            symbol = "location.north.line"
        case "comms":
            key = "communications"
            symbol = "antenna.radiowaves.left.and.right"
        case "weather":
            key = "weather"
            symbol = "cloud.sun"
        case "science":
            key = "science"
            symbol = "sparkles"
        case "debris", "rocket_body":
            key = "orbital_remnant"
            symbol = "circle.dashed"
        default:
            return nil
        }
        return (
            copy("archive.role.\(key).title"),
            copy("archive.role.\(key).summary"),
            symbol
        )
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
                    label: "EL",
                    value: String(format: "%+.1f°", ephemeris.elevation * 180 / .pi)
                )
                observationDivider
                observationCell(
                    label: copy("archive.field.range"),
                    value: String(format: "%.0f KM", ephemeris.rangeKm)
                )
                observationDivider
                observationCell(
                    label: copy("archive.field.speed"),
                    value: String(format: "%.2f KM/S", ephemeris.velocityKmS)
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(observationSentence(ephemeris))
                    .font(Typography.archiveNarrative)
                    .tracking(0.15)
                    .foregroundStyle(Palette.inkMid.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(String(format: "AZ %03.0f°", normalizedDegrees(ephemeris.azimuth)))
                    .font(Typography.statusTag)
                    .tracking(0.45)
                    .foregroundStyle(Palette.inkLow.opacity(0.64))
                    .lineLimit(1)
            }

            if let movement = insight?.movementLabel(language: language) {
                Label(movement, systemImage: "arrow.up.right")
                    .font(Typography.statusTag)
                    .tracking(language == .english ? 0.45 : 0.12)
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

    private func compactMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.statusTag)
                .tracking(language == .english ? 0.65 : 0.12)
                .foregroundStyle(Palette.inkLow.opacity(0.66))
                .lineLimit(1)
            Text(value)
                .font(Typography.archiveDataValue)
                .foregroundStyle(Palette.inkMid.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
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
