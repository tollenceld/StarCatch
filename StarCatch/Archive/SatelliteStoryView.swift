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

    }

    let object: CatalogObject
    let story: SatelliteStory
    let ephemeris: Ephemeris?
    let insight: SatelliteInsightSnapshot?
    let forecast: PassForecast?
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var revealed = false
    @State private var expandedChapterID: String?
    @State private var missionHistoryExpanded = false
    @State private var sourcesExpanded = false
    @State private var selectedSection: ArchiveSection = .observation
    @State private var selectedPassIndex: Int?
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
        HStack(spacing: 22) {
            ForEach(ArchiveSection.allCases) { section in
                Button {
                    withAnimation(suppressMotion ? .easeOut(duration: 0.1) : .easeInOut(duration: 0.22)) {
                        selectedSection = section
                    }
                } label: {
                    Text(copy(section.titleKey))
                        .lineLimit(1)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(
                        selectedSection == section
                            ? Palette.inkHigh.opacity(0.92)
                            : Palette.inkLow.opacity(0.68)
                    )
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .overlay(alignment: .bottom) {
                        if selectedSection == section {
                            Rectangle()
                                .fill(object.identityTint.opacity(0.82))
                                .frame(height: 1)
                                .matchedGeometryEffect(id: "archive-section", in: sectionSelection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.28))
                .frame(height: 0.5)
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
            forecastSectionHeader
            PassForecastLedgerView(
                forecast: forecast,
                fallbackPass: insight?.pass,
                selectedIndex: $selectedPassIndex,
                tint: object.identityTint
            )
            .padding(.top, 11)

            sectionLabel(copy("archive.section.observe_now"))
                .padding(.top, 24)
            if let ephemeris {
                observationSnapshot(ephemeris)
                    .padding(.top, 11)
            } else {
                Text(copy("archive.observation.unavailable"))
                    .font(Typography.readingCompact)
                    .foregroundStyle(Palette.inkMid.opacity(0.7))
                    .padding(.top, 13)
            }

        }
    }

    private var forecastSectionHeader: some View {
        HStack(spacing: 10) {
            Text(copy("archive.section.future_24h"))
                .font(Typography.fieldLabel)
                .tracking(Typography.fieldLabelTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                .lineLimit(1)
            Spacer(minLength: 10)
            HStack(spacing: 6) {
                Rectangle()
                    .fill(object.identityTint.opacity(0.65))
                    .frame(width: 14, height: 0.7)
                Text(copy("archive.forecast.above_horizon"))
                    .font(Typography.statusTag)
                    .tracking(language == .english ? 0.35 : 0.08)
                    .foregroundStyle(Palette.inkLow.opacity(0.64))
                    .lineLimit(1)
            }
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
            orbitParametersModule
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

    private var orbitParametersModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(copy("archive.section.orbit_parameters"))
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

/// A 24-hour ephemeris ledger. Geometry is derived from the forecast once;
/// the only live work is a one-second current-time marker and countdown.
private struct PassForecastLedgerView: View {
    let forecast: PassForecast?
    let fallbackPass: PassWindow?
    @Binding var selectedIndex: Int?
    let tint: Color

    @State private var forecastLoadedAt = Date()

    private var copyLanguage: SupportedLanguage { .current }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 13) {
                if let forecast {
                    let forecastNow = forecast.referenceDate.addingTimeInterval(
                        timeline.date.timeIntervalSince(forecastLoadedAt)
                    )
                    if forecast.isStationary {
                        stationaryState(forecast)
                    } else if forecast.windows.isEmpty {
                        forecastEmptyState
                    } else {
                        forecastTimeline(forecast, now: forecastNow)
                        if let window = selectedWindow(in: forecast, at: forecastNow) {
                            selectedPassPanel(window, now: forecastNow)
                        }
                    }
                } else if let fallbackPass {
                    if fallbackPass.phase == .stationary {
                        waitingState(key: "archive.forecast.stationary")
                    } else {
                        selectedPassPanel(fallbackPass, now: timeline.date)
                            .redacted(reason: .placeholder)
                            .accessibilityHidden(true)
                    }
                } else {
                    waitingState(key: "archive.forecast.loading")
                }
            }
        }
        .onChange(of: forecast) { _, value in
            forecastLoadedAt = Date()
            selectedIndex = value?.defaultWindowIndex(at: value?.referenceDate ?? Date())
        }
        .onAppear {
            if selectedIndex == nil {
                selectedIndex = forecast?.defaultWindowIndex(
                    at: forecast?.referenceDate ?? Date()
                )
            }
        }
    }

    private func text(_ key: String) -> String {
        L10n.text(key, table: "SatelliteText", language: copyLanguage)
    }

    private func forecastTimeline(_ forecast: PassForecast, now: Date) -> some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.inkFaint.opacity(0.16))
                        .frame(height: 2)

                    ForEach(Array(forecast.windows.enumerated()), id: \.offset) { index, window in
                        if let rise = window.rise, let set = window.set {
                            let x = timeX(rise, forecast: forecast, width: proxy.size.width)
                            let endX = timeX(set, forecast: forecast, width: proxy.size.width)
                            Button {
                                selectedIndex = index
                            } label: {
                                Capsule()
                                    .fill(
                                        tint.opacity(selectedIndex == index ? 0.86 : 0.38)
                                    )
                                    .frame(width: max(7, endX - x), height: selectedIndex == index ? 6 : 3)
                                    .contentShape(Rectangle().inset(by: -12))
                            }
                            .buttonStyle(.plain)
                            .offset(x: x)
                            .accessibilityLabel(passAccessibility(window))
                        }
                    }

                    if forecast.referenceDate ... forecast.endDate ~= now {
                        Rectangle()
                            .fill(Palette.inkHigh.opacity(0.76))
                            .frame(width: 0.6, height: 15)
                            .offset(x: timeX(now, forecast: forecast, width: proxy.size.width))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)

            HStack {
                Text("00H")
                Spacer()
                Text("06H")
                Spacer()
                Text("12H")
                Spacer()
                Text("18H")
                Spacer()
                Text("24H")
            }
            .font(Typography.statusTag)
            .tracking(0.45)
            .foregroundStyle(Palette.inkLow.opacity(0.66))
        }
    }

    private func selectedPassPanel(_ pass: PassWindow, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ledgerMetric(
                    text(pass.phase == .visible ? "archive.forecast.current_event" : "archive.forecast.next_event"),
                    eventValue(pass, now: now)
                )
                ledgerDivider
                ledgerMetric(
                    text("archive.forecast.maximum_elevation"),
                    pass.maximumElevationDegrees.map { String(format: "%.0f°", $0) } ?? "—"
                )
                ledgerDivider
                ledgerMetric(
                    text("archive.forecast.duration"),
                    pass.duration.map(durationText) ?? "—"
                )
            }

            Canvas { context, size in
                drawPass(pass, now: now, context: &context, size: size)
            }
            .frame(height: 62)
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                eventLabel(text("archive.forecast.rise"), date: pass.rise)
                Spacer()
                eventLabel(text("archive.forecast.peak"), date: pass.peak)
                Spacer()
                eventLabel(text("archive.forecast.set"), date: pass.set)
            }

            if let riseAzimuth = pass.riseAzimuthDegrees,
               let setAzimuth = pass.setAzimuthDegrees {
                Text(String(format: "AZ %03.0f°  →  %03.0f°", riseAzimuth, setAzimuth))
                    .font(Typography.statusTag)
                    .tracking(0.5)
                    .foregroundStyle(Palette.inkLow.opacity(0.7))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .background(
            tint.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.55)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(passAccessibility(pass))
    }

    private func stationaryState(_ forecast: PassForecast) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(tint.opacity(0.82))
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(tint.opacity(0.28), lineWidth: 0.6))
            VStack(alignment: .leading, spacing: 4) {
                Text(text("archive.forecast.stationary"))
                    .font(Typography.guide)
                    .foregroundStyle(Palette.inkHigh.opacity(0.9))
                if let elevation = forecast.stationaryElevationDegrees {
                    Text(String(format: "EL %+.1f°", elevation))
                        .font(Typography.statusTag)
                        .foregroundStyle(Palette.inkMid.opacity(0.72))
                }
            }
            Spacer()
        }
        .padding(13)
        .background(Palette.inkHigh.opacity(0.025), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.inkFaint.opacity(0.3), lineWidth: 0.5))
    }

    private var forecastEmptyState: some View {
        waitingState(key: "archive.forecast.no_pass")
    }

    private func waitingState(key: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: key == "archive.forecast.loading" ? "ellipsis" : "horizon")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(tint.opacity(0.7))
                .frame(width: 24)
            Text(text(key))
                .font(Typography.readingCompact)
                .foregroundStyle(Palette.inkMid.opacity(0.76))
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 52)
        .background(Palette.inkHigh.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func selectedWindow(in forecast: PassForecast, at date: Date) -> PassWindow? {
        let index = selectedIndex ?? forecast.defaultWindowIndex(at: date)
        guard let index, forecast.windows.indices.contains(index) else { return nil }
        return forecast.windows[index]
    }

    private func timeX(_ date: Date, forecast: PassForecast, width: CGFloat) -> CGFloat {
        let fraction = date.timeIntervalSince(forecast.referenceDate)
            / forecast.endDate.timeIntervalSince(forecast.referenceDate)
        return width * CGFloat(min(1, max(0, fraction)))
    }

    private func drawPass(
        _ pass: PassWindow,
        now: Date,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let baseline = size.height - 9
        let inset: CGFloat = 5
        let peakRatio = CGFloat(min(1, max(0.16, (pass.maximumElevationDegrees ?? 30) / 90)))
        let peakY = baseline - 18 - peakRatio * 29
        var path = Path()
        path.move(to: CGPoint(x: inset, y: baseline))
        path.addCurve(
            to: CGPoint(x: size.width - inset, y: baseline),
            control1: CGPoint(x: size.width * 0.31, y: peakY),
            control2: CGPoint(x: size.width * 0.69, y: peakY)
        )
        context.stroke(path, with: .color(tint.opacity(0.56)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))

        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: baseline))
        horizon.addLine(to: CGPoint(x: size.width, y: baseline))
        context.stroke(horizon, with: .color(Palette.inkFaint.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))

        guard let progress = pass.progress(at: now),
              let point = path.trimmedPath(from: 0, to: max(0.002, progress)).currentPoint
        else { return }
        context.fill(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(tint.opacity(0.92)))
    }

    private func ledgerMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.statusTag)
                .foregroundStyle(Palette.inkLow.opacity(0.68))
                .lineLimit(1)
            Text(value)
                .font(Typography.archiveDataValue)
                .foregroundStyle(Palette.inkHigh.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ledgerDivider: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(0.25))
            .frame(width: 0.5, height: 30)
            .padding(.horizontal, 7)
    }

    private func eventLabel(_ label: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
            Text(date.map(timeText) ?? "—")
                .foregroundStyle(Palette.inkMid.opacity(0.82))
        }
        .font(Typography.statusTag)
        .foregroundStyle(Palette.inkLow.opacity(0.65))
    }

    private func eventValue(_ pass: PassWindow, now: Date) -> String {
        if pass.phase == .visible, let set = pass.set {
            return countdown(to: set, from: now)
        }
        return pass.rise.map(timeText) ?? "—"
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        return L10n.format("archive.forecast.minutes", table: "SatelliteText", language: copyLanguage, minutes)
    }

    private func countdown(to date: Date, from now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func passAccessibility(_ pass: PassWindow) -> String {
        L10n.format(
            "accessibility.pass_window",
            table: "SatelliteText",
            language: copyLanguage,
            pass.rise.map(timeText) ?? "—",
            pass.maximumElevationDegrees ?? 0,
            pass.set.map(timeText) ?? "—"
        )
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
