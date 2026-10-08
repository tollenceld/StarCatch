import SwiftUI

enum SatelliteArchiveSection: String, CaseIterable, Identifiable {
    case observation, mission, data
    var id: String { rawValue }
    var title: String { L10n.text("archive.tab." + rawValue, table: "SatelliteText") }
    var symbol: String {
        switch self {
        case .observation: "binoculars"
        case .mission: "text.book.closed"
        case .data: "chart.bar.xaxis"
        }
    }
    var firstNumber: String { self == .observation ? "01" : self == .mission ? "02" : "05" }
    func moved(by delta: Int) -> Self {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return Self.allCases[min(Self.allCases.count - 1, max(0, index + delta))]
    }
}

/// 单体卫星或大型星座的离线深度档案。策展事实与当前节点的实时轨道读数
/// 明确分区，避免把故事和瞬时位置混成同一种“参数表”。
struct SatelliteStoryView: View {
    let object: CatalogObject
    let story: SatelliteStory
    let ephemeris: Ephemeris?
    let insight: SatelliteInsightSnapshot?
    let forecast: PassForecast?
    var trace: SatelliteTrackSnapshot? = nil
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.chromePreviewReducedMotion) private var previewReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var revealed = false
    @State private var section: SatelliteArchiveSection = .observation
    @State private var sectionDirection: CGFloat = 1
    @Namespace private var sectionHighlight

    private var suppressMotion: Bool { systemReducedMotion || previewReducedMotion || reducedMotion }
    private var language: SupportedLanguage { .current }

    private func copy(_ key: String) -> String {
        L10n.text(key, table: "SatelliteText", language: language)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.voidBlack.ignoresSafeArea()
                ScrollViewReader { reader in
                    VStack(spacing: 0) {
                        if dynamicTypeSize.isAccessibilitySize {
                            // At accessibility sizes the hero joins the single scroll flow,
                            // preserving space for full names and reading content.
                            ScrollView {
                                VStack(spacing: 0) {
                                    archiveHero(height: 150)
                                    ZStack(alignment: .topLeading) {
                                        readingContents.id(section).transition(sectionTransition)
                                    }
                                }
                            }
                        } else {
                            archiveHero(height: min(260, max(210, geometry.size.height * 0.29)))
                            ZStack(alignment: .topLeading) {
                                ScrollView(showsIndicators: false) { readingContents }
                                    .id(section)
                                    .transition(sectionTransition)
                            }
                            .clipped()
                        }
                    }
                    #if DEBUG
                    .task(id: trace?.referenceDate) {
                        let args = ProcessInfo.processInfo.arguments
                        if let index = args.firstIndex(of: "--archiveTab"), index + 1 < args.count,
                           let value = SatelliteArchiveSection(rawValue: args[index + 1]) {
                            section = value
                        }
                        if let index = args.firstIndex(of: "--archiveSection"), index + 1 < args.count {
                            let number = args[index + 1]
                            section = ["02", "03"].contains(number) ? .mission
                                : ["05", "06"].contains(number) ? .data : .observation
                            try? await Task.sleep(for: .milliseconds(150))
                            guard !Task.isCancelled else { return }
                            reader.scrollTo(number, anchor: .top)
                        }
                        if args.contains("--previewArchiveTabs") {
                            // Finite replay uses the same selection path as the floating buttons.
                            for item in [SatelliteArchiveSection.mission, .data, .observation] {
                                try? await Task.sleep(for: .seconds(2))
                                guard !Task.isCancelled else { return }
                                select(item)
                            }
                        }
                    }
                    #endif
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            archiveHeader
        }
        .overlay(alignment: .bottom) {
            sectionControl
                .padding(.horizontal, AppChromeMetrics.edgeInset)
                .padding(.bottom, 12)
        }
        .appEdgeBackGesture(action: onDismiss)
        .opacity(revealed ? 1 : 0)
        .offset(y: suppressMotion ? 0 : revealed ? 0 : 8)
        .onAppear {
            withAnimation(suppressMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.28)) { revealed = true }
        }
        .accessibilityElement(children: .contain)
    }

    private func archiveHero(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(missionRoleTitle)
                .font(Typography.statusTag)
                .foregroundStyle(object.identityTint)
            Text(object.deepArchiveTitle)
                .instrumentFont(24, relativeTo: .title, weight: .semibold)
                .foregroundStyle(Palette.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(metadataLine)
                .font(Typography.statusTag)
                .foregroundStyle(Palette.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            SatelliteWireframeView(drawingHeight: dynamicTypeSize.isAccessibilitySize ? 150 : max(90, height - 62))
                .id(object.id)
        }
        .padding(.horizontal, AppChromeMetrics.readingInset)
        .padding(.top, 12)
    }

    /// Leaving the archive and switching its peer sections occupy separate edges.
    private var archiveHeader: some View {
        HStack(spacing: 16) {
            Button(action: onDismiss) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text(copy("navigation.return_sky"))
                }
                .font(Typography.guide)
                .foregroundStyle(Palette.signal)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copy("navigation.return_sky"))
            Spacer(minLength: 0)
            Text(copy("navigation.object_archive"))
                .font(Typography.guide)
                .foregroundStyle(Palette.Text.secondary)
        }
        .padding(.horizontal, AppChromeMetrics.edgeInset)
        .frame(minHeight: ContentTopBarMetrics.height)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Palette.voidBlack.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { ContentHairline() }
    }

    private var sectionControl: some View {
        HStack(spacing: 2) {
            ForEach(SatelliteArchiveSection.allCases) { item in
                Button { select(item) } label: {
                    let layout = dynamicTypeSize >= .xxLarge
                        ? AnyLayout(VStackLayout(spacing: 3))
                        : AnyLayout(HStackLayout(spacing: 5))
                    layout {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 19, height: 19)
                        Text(item.title)
                            .instrumentFont(12, relativeTo: .caption, weight: section == item ? .semibold : .medium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(section == item ? Palette.signal : Palette.Text.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if section == item {
                            selectionHighlight
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(maxWidth: dynamicTypeSize >= .xxLarge ? 280 : 264)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .modifier(SkyGlassSurface(shape: Capsule(), interactive: true))
        .modifier(ChromeGlassContainer())
        .shadow(color: .black.opacity(0.20), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            guard abs(value.translation.width) > 40,
                  abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            select(section.moved(by: value.translation.width < 0 ? 1 : -1))
        })
    }

    @ViewBuilder private var selectionHighlight: some View {
        let highlight = Capsule()
            .fill(Palette.Text.primary.opacity(0.10))
            .overlay { Capsule().strokeBorder(Palette.Text.primary.opacity(0.16), lineWidth: 0.5) }
        if suppressMotion {
            highlight.transition(.opacity)
        } else {
            highlight.matchedGeometryEffect(id: "archive-selection", in: sectionHighlight)
        }
    }

    private func select(_ value: SatelliteArchiveSection) {
        guard value != section else { return }
        sectionDirection = (SatelliteArchiveSection.allCases.firstIndex(of: value) ?? 0)
            > (SatelliteArchiveSection.allCases.firstIndex(of: section) ?? 0) ? 1 : -1
        withAnimation(.easeInOut(duration: suppressMotion ? 0.14 : 0.24)) { section = value }
    }

    private var sectionTransition: AnyTransition {
        guard !suppressMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: sectionDirection * 24)),
            removal: .opacity.combined(with: .offset(x: -sectionDirection * 24))
        )
    }

    private var readingContents: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch section {
            case .observation:
                readingSection(number: "01", title: copy("archive.reading.motion")) { currentMotion }
                readingSection(number: "04", title: copy("archive.reading.passes")) { observationSection }
            case .mission:
                readingSection(number: "02", title: copy("archive.reading.mission")) { missionSection }
                readingSection(number: "03", title: copy("archive.history.title")) { milestoneRail }
            case .data:
                readingSection(number: "05", title: copy("archive.reading.identity")) { dataSection }
                readingSection(number: "06", title: copy("archive.sources.title")) { sourceNote }
            }
        }
        .padding(.horizontal, AppChromeMetrics.readingInset)
        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 104 : 88)
    }

    private var metadataLine: String {
        var fields = [story.eyebrow, "NORAD \(object.noradId)", object.orbitClass]
        if object.family != nil { fields.append(copy("archive.badge.series")) }
        return fields.joined(separator: "  ·  ")
    }

    private func readingSection<Content: View>(
        number: String, title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(number)
                    .font(Typography.statusTag)
                    .foregroundStyle(object.identityTint)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.Text.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, number == section.firstNumber ? 12 : 20)
        .overlay(alignment: .top) { if number != section.firstNumber { ContentHairline() } }
        .padding(.top, number == section.firstNumber ? 0 : 24)
        .id(number)
    }

    private var currentMotion: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let trace {
                SatelliteMotionTraceView(trace: trace, tint: object.identityTint)
            } else {
                Text(copy("archive.reading.motion_loading"))
                    .font(Typography.readingCompact)
                    .foregroundStyle(Palette.Text.tertiary)
            }
            if let ephemeris {
                observationSnapshot(ephemeris)
            }
        }
    }

    private var observationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            forecastSectionHeader
            PassForecastLedgerView(
                forecast: forecast,
                fallbackPass: insight?.pass,
                tint: object.identityTint
            )
        }
    }

    private var forecastSectionHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(copy("archive.section.future_24h"))
                .font(Typography.fieldLabel)
                .tracking(Typography.fieldLabelTracking)
                .foregroundStyle(Palette.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
            HStack(spacing: 6) {
                Rectangle()
                    .fill(object.identityTint.opacity(0.65))
                    .frame(width: 14, height: 0.7)
                Text(copy("archive.forecast.above_horizon"))
                    .font(Typography.statusTag)
                    .tracking(language == .english ? 0.35 : 0.08)
                    .foregroundStyle(Palette.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(story.lead)
                .font(Typography.readingBody)
                .foregroundStyle(Palette.Text.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(copy(story.scope == .family ? "archive.reading.family_scope" : "archive.reading.object_scope"))
                .font(Typography.statusTag)
                .foregroundStyle(object.identityTint)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                storyField(copy("archive.reading.organization"), story.organization, narrative: true)
                storyField(copy("archive.reading.program"), story.program, narrative: true)
            }
            if !story.facts.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading),
                                         count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                          alignment: .leading, spacing: 16) {
                    ForEach(story.facts) { fact in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(fact.label)
                                .font(Typography.readingCompact)
                                .foregroundStyle(object.identityTint)
                            Text(fact.value)
                                .font(Typography.readingBody)
                                .foregroundStyle(Palette.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 4)
            }
            ForEach(story.chapters) { chapter in
                VStack(alignment: .leading, spacing: 8) {
                    Text(chapter.title)
                        .font(.headline)
                        .foregroundStyle(Palette.Text.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(chapter.body)
                        .font(Typography.readingBody)
                        .lineSpacing(4)
                        .foregroundStyle(Palette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) { ContentHairline() }
            }
            if let reference = story.officialReference { officialReferenceLink(reference) }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            orbitParametersModule
            currentTargetModule
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
                        .foregroundStyle(Palette.Text.primary)
                    Text(reference.title)
                        .font(Typography.statusTag)
                        .tracking(0.45)
                        .foregroundStyle(Palette.Text.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(object.identityTint.opacity(0.82))
            }
            .padding(.horizontal, 16)
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
        .buttonStyle(SkyCapsulePressStyle())
        .accessibilityLabel(
            L10n.format("accessibility.open_official", table: "SatelliteText", language: language, reference.title)
        )
        .accessibilityHint(copy("accessibility.external_browser"))
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 0))
        return VStack(alignment: .leading, spacing: 11) {
            layout {
                observationCell(
                    label: "EL",
                    value: String(format: "%+.1f", ephemeris.elevation * 180 / .pi), unit: "°"
                )
                if !dynamicTypeSize.isAccessibilitySize { observationDivider }
                observationCell(
                    label: copy("archive.field.range"),
                    value: String(format: "%.0f", ephemeris.rangeKm), unit: "KM"
                )
                if !dynamicTypeSize.isAccessibilitySize { observationDivider }
                observationCell(
                    label: copy("archive.field.speed"),
                    value: String(format: "%.2f", ephemeris.velocityKmS), unit: "KM/S"
                )
            }

            layout {
                Text(observationSentence(ephemeris))
                    .font(Typography.archiveNarrative)
                    .tracking(0.15)
                    .foregroundStyle(Palette.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(String(format: "AZ %03.0f°", normalizedDegrees(ephemeris.azimuth)))
                    .font(Typography.statusTag)
                    .tracking(0.45)
                    .foregroundStyle(Palette.Text.tertiary)
                    .lineLimit(1)
            }

            if let movement = insight?.movementLabel(language: language) {
                Label(movement, systemImage: "arrow.up.right")
                    .font(Typography.statusTag)
                    .tracking(language == .english ? 0.45 : 0.12)
                    .foregroundStyle(object.identityTint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Palette.sheetBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
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

    private func observationCell(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.statusTag)
                .tracking(0.85)
                .foregroundStyle(Palette.Text.tertiary)
            SatelliteReadout(value: value, unit: unit)
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
                            .foregroundStyle(Palette.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, index < story.milestones.count - 1 ? 12 : 0)
                }
            }
        }
    }

    private func storyField(_ label: String, _ value: String, narrative: Bool = false) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
        return layout {
            Text(label)
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.Text.tertiary)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 88, alignment: .leading)
            Text(value)
                .font(narrative ? Typography.readingBody : Typography.archiveDataValue)
                .tracking(narrative ? 0.1 : Typography.dataValueTracking)
                .foregroundStyle(Palette.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 8)
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
                .foregroundStyle(Palette.Text.tertiary)
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
                .foregroundStyle(Palette.Text.tertiary)
            ForEach(story.sources) { source in
                sourceRow(source)
            }
            if story.sources.contains(where: { $0.verifiedAt == nil && $0.provenance != .catalog }) {
                Text(copy("archive.reading.undated"))
                    .font(Typography.readingCompact)
                    .foregroundStyle(Palette.Text.tertiary)
            }
            Text(copy("archive.sources.calculation_note"))
                .font(Typography.archiveNarrative)
                .tracking(0.45)
                .foregroundStyle(Palette.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: StorySource) -> some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            Text(source.provenance.title + " · " + source.scope.title)
                .font(Typography.statusTag)
                .foregroundStyle(object.identityTint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(source.title)
                    .font(Typography.readingBody)
                    .foregroundStyle(Palette.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if source.url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.Text.tertiary)
                }
            }
            if let date = source.verifiedAt ?? source.retrievedAt {
                Text("\(copy(source.verifiedAt == nil ? "archive.reading.retrieved" : "archive.reading.verified")) · \(date)")
                    .font(Typography.statusTag)
                    .foregroundStyle(Palette.Text.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { ContentHairline() }
        .contentShape(Rectangle())

        if let url = source.url {
            Link(destination: url) { content }
                .buttonStyle(SkyCapsulePressStyle())
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
    let tint: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var forecastLoadedAt = Date()
    @State private var selectedDate: Date?
    @State private var zoom = 1.0
    @State private var viewCenter: Double?

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
                        if let index = selectedIndex(in: forecast, now: forecastNow) {
                            let window = forecast.windows[index]
                            selectedPassPanel(window, now: forecastNow)
                        }
                        upcomingPasses(forecast, now: forecastNow)
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
            selectedDate = nil
            zoom = 1
            viewCenter = nil
        }
    }

    private func text(_ key: String) -> String {
        L10n.text(key, table: "SatelliteText", language: copyLanguage)
    }

    private func selectedIndex(in forecast: PassForecast, now: Date) -> Int? {
        selectedDate.flatMap { ArchiveChartSelection.nearestPass(in: forecast, at: $0) }
            ?? forecast.defaultWindowIndex(at: now)
    }

    private func viewport(for forecast: PassForecast) -> ArchiveChartViewport {
        ArchiveChartViewport(extent: 0...max(1, forecast.endDate.timeIntervalSince(forecast.referenceDate)),
                             minimumSpan: 3 * 3600, zoom: zoom, center: viewCenter)
    }

    private func forecastTimeline(_ forecast: PassForecast, now: Date) -> some View {
        let viewport = viewport(for: forecast)
        let range = viewport.visibleRange
        return VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                let baseline = size.height / 2
                func x(_ offset: Double) -> CGFloat {
                    size.width * (offset - range.lowerBound) / (range.upperBound - range.lowerBound)
                }
                var line = Path()
                line.move(to: CGPoint(x: 0, y: baseline))
                line.addLine(to: CGPoint(x: size.width, y: baseline))
                context.stroke(line, with: .color(Palette.Text.tertiary.opacity(0.3)), lineWidth: 0.7)
                for index in 0...24 {
                    let offset = range.lowerBound + (range.upperBound-range.lowerBound) * Double(index) / 24
                    let h: CGFloat = index.isMultiple(of: 6) ? 18 : 7
                    var tick = Path()
                    tick.move(to: CGPoint(x: x(offset), y: baseline - h / 2))
                    tick.addLine(to: CGPoint(x: x(offset), y: baseline + h / 2))
                    context.stroke(tick, with: .color(Palette.Text.tertiary.opacity(0.4)), lineWidth: 0.7)
                }
                for (index, pass) in forecast.windows.enumerated() {
                    guard let rise = pass.rise, let set = pass.set else { continue }
                    let start = max(range.lowerBound, rise.timeIntervalSince(forecast.referenceDate))
                    let end = min(range.upperBound, set.timeIntervalSince(forecast.referenceDate))
                    guard end >= start else { continue }
                    let selected = index == selectedIndex(in: forecast, now: now)
                    let mark = CGRect(x: x(start), y: baseline - 4, width: max(1, x(end)-x(start)), height: 8)
                    context.fill(Path(roundedRect: mark, cornerRadius: 2),
                                 with: .color(selected ? Palette.signal : tint.opacity(0.65)))
                }
                for (date, color) in [(now, Palette.Text.primary), (selectedDate, Palette.signal)] {
                    guard let date else { continue }
                    let offset = date.timeIntervalSince(forecast.referenceDate)
                    guard range.contains(offset) else { continue }
                    var cursor = Path()
                    cursor.move(to: CGPoint(x: x(offset), y: 0))
                    cursor.addLine(to: CGPoint(x: x(offset), y: size.height))
                    context.stroke(cursor, with: .color(color), lineWidth: 1)
                }
            }
            .frame(height: 54)
            .overlay {
                ArchiveChartScrubber(zoom: zoom, onScrub: { fraction in
                    selectedDate = forecast.referenceDate.addingTimeInterval(viewport.value(at: fraction))
                }, onZoom: { value in
                    if zoom == 1 { viewCenter = selectedDate?.timeIntervalSince(forecast.referenceDate) }
                    zoom = value
                }).accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text("archive.chart.pass_hint"))
            .accessibilityValue(selectedDate.map(passDateText) ?? text("archive.section.future_24h"))
            .accessibilityAdjustableAction { direction in
                let current = selectedIndex(in: forecast, now: now) ?? 0
                let next = min(forecast.windows.count - 1, max(0, current + (direction == .increment ? 1 : -1)))
                selectedDate = forecast.windows[next].rise ?? forecast.windows[next].peak
                if zoom > 1 { viewCenter = selectedDate?.timeIntervalSince(forecast.referenceDate) }
            }
            .accessibilityAction(named: Text(text("archive.chart.zoom_in"))) { zoom = min(8, zoom * 2) }
            .accessibilityAction(named: Text(text("archive.chart.zoom_out"))) { zoom = max(1, zoom / 2) }
            HStack {
                ForEach(0..<5) { index in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(forecast.referenceDate.addingTimeInterval(viewport.value(at: Double(index) / 4)),
                         format: .dateTime.hour().minute())
                }
            }
            .font(Typography.statusTag)
            .foregroundStyle(Palette.Text.tertiary)
            if let selectedDate {
                Text(text("archive.chart.inspect_time") + " · " + passDateText(selectedDate))
                    .font(Typography.statusTag)
                    .foregroundStyle(Palette.signal)
            }
            ArchiveChartTools(zoom: zoom, hasSelection: selectedDate != nil) {
                selectedDate = nil; zoom = 1; viewCenter = nil
            }
        }
    }

    private func upcomingPasses(_ forecast: PassForecast, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(forecast.windows.enumerated()), id: \.offset) { index, window in
                Button {
                    selectedDate = window.peak ?? window.rise
                    if zoom > 1 { viewCenter = selectedDate?.timeIntervalSince(forecast.referenceDate) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(window.rise.map(passDateText) ?? "—")  →  \(window.set.map(passDateText) ?? "—")")
                                .font(Typography.readingBody.monospacedDigit())
                                .foregroundStyle(Palette.Text.primary)
                            Text(passAccessibility(window))
                                .font(Typography.readingCompact)
                                .foregroundStyle(Palette.Text.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: index == selectedIndex(in: forecast, now: now) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index == selectedIndex(in: forecast, now: now) ? tint : Palette.Text.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) { ContentHairline() }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selectedIndex(in: forecast, now: now) ? .isSelected : [])
            }
        }
    }

    private func selectedPassPanel(_ pass: PassWindow, now: Date) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 0))
        return VStack(alignment: .leading, spacing: 12) {
            layout {
                ledgerMetric(
                    text(selectedDate != nil ? "archive.forecast.rise"
                         : pass.phase == .visible ? "archive.forecast.current_event" : "archive.forecast.next_event"),
                    selectedDate != nil ? (pass.rise.map(timeText) ?? "—") : eventValue(pass, now: now),
                    prominent: true
                )
                if !dynamicTypeSize.isAccessibilitySize { ledgerDivider }
                ledgerMetric(
                    text("archive.forecast.maximum_elevation"),
                    pass.maximumElevationDegrees.map { String(format: "%.0f°", $0) } ?? "—"
                )
                if !dynamicTypeSize.isAccessibilitySize { ledgerDivider }
                ledgerMetric(
                    text("archive.forecast.duration"),
                    pass.duration.map(durationText) ?? "—"
                )
            }

            Text(text("archive.forecast.key_events"))
                .font(Typography.statusTag)
                .foregroundStyle(Palette.Text.tertiary)
            SatellitePassEventStrip(pass: pass, now: now, tint: tint)
                .id(pass.rise)

            layout {
                eventLabel(text("archive.forecast.rise"), date: pass.rise)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                eventLabel(text("archive.forecast.peak"), date: pass.peak)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                eventLabel(text("archive.forecast.set"), date: pass.set)
            }

            if let riseAzimuth = pass.riseAzimuthDegrees,
               let setAzimuth = pass.setAzimuthDegrees {
                Text(String(format: "AZ %03.0f°  →  %03.0f°", riseAzimuth, setAzimuth))
                    .font(Typography.statusTag)
                    .tracking(0.5)
                    .foregroundStyle(Palette.Text.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            Palette.sheetBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .contain)
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
                    .foregroundStyle(Palette.Text.primary)
                if let elevation = forecast.stationaryElevationDegrees {
                    Text(String(format: "EL %+.1f°", elevation))
                        .font(Typography.statusTag)
                        .foregroundStyle(Palette.Text.secondary)
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
                .foregroundStyle(Palette.Text.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Palette.inkHigh.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func ledgerMetric(_ label: String, _ value: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Typography.fieldLabel)
                .foregroundStyle(Palette.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .instrumentFont(prominent ? 24 : 16, relativeTo: .callout, weight: prominent ? .medium : .regular, design: .monospaced)
                .foregroundStyle(prominent ? Palette.Text.primary : Palette.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .foregroundStyle(Palette.Text.secondary)
        }
        .font(Typography.statusTag)
        .foregroundStyle(Palette.Text.tertiary)
    }

    private func eventValue(_ pass: PassWindow, now: Date) -> String {
        if pass.phase == .visible, let set = pass.set {
            return countdown(to: set, from: now)
        }
        return pass.rise.map(timeText) ?? "—"
    }

    private func passDateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day()
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
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
            .foregroundStyle(Palette.Text.primary)
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
