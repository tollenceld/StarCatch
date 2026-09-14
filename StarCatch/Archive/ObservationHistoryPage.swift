import SwiftUI

/// 记录页按本地自然日生成的稳定分组。分组与排序不依赖 SwiftUI `body` 的索引，
/// 因此删除和重新排序时仍能保持可靠身份。
struct ObservationHistorySection: Identifiable {
    let day: Date
    let entries: [ObservationLog.Entry]

    var id: Date { day }

    static func resolve(
        entries: [ObservationLog.Entry],
        calendar: Calendar = .current
    ) -> [ObservationHistorySection] {
        let grouped = Dictionary(grouping: entries) {
            calendar.startOfDay(for: $0.lastSeen)
        }
        return grouped.keys.sorted(by: >).map { day in
            ObservationHistorySection(
                day: day,
                entries: grouped[day, default: []].sorted { $0.lastSeen > $1.lastSeen }
            )
        }
    }
}

/// 面板内的观测记录。使用系统 List 协调纵向滚动与左滑删除，避免自定义 DragGesture
/// 抢占滚动手势。
struct ObservationHistoryPage: View {
    let session: SkySession
    let onBack: () -> Void

    @ObservedObject private var log: ObservationLog
    @State private var path: [ObservationRoute] = []
    @State private var confirmClearLog = false

    private var language: SupportedLanguage { .current }
    private func copy(_ key: String) -> String { L10n.text(key, language: language) }

    init(session: SkySession, onBack: @escaping () -> Void = {}) {
        self.session = session
        self.onBack = onBack
        _log = ObservedObject(wrappedValue: session.log)
    }

    var body: some View {
        NavigationStack(path: $path) {
            AppPageShell(
                backTitle: copy("navigation.sky"),
                title: copy("navigation.observations"),
                onBack: onBack
            ) {
                historyList
            }
            .accessibilityHidden(!path.isEmpty)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ObservationRoute.self) { route in
                switch route {
                case .detail(let objectID):
                    detailPage(objectID: objectID)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            copy("observations.clear.confirmation"),
            isPresented: $confirmClearLog,
            titleVisibility: .visible
        ) {
            Button(copy("observations.clear"), role: .destructive) { log.clear() }
            Button(copy("action.cancel"), role: .cancel) {}
        } message: {
            Text(copy("observations.clear.note"))
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--openObservationDetail"),
               let first = log.entries.first {
                path = [.detail(first.objectId)]
            }
            #endif
        }
    }

    private var historyList: some View {
        List {
            historyMetrics
                .listRowInsets(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if log.entries.isEmpty {
                emptyHistory
                    .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(historySections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            historyRow(entry)
                                .listRowInsets(
                                    EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            log.remove(objectId: entry.objectId)
                                        }
                                    } label: {
                                        Label(copy("action.delete"), systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        historySectionLabel(for: section.day)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var historySections: [ObservationHistorySection] {
        ObservationHistorySection.resolve(entries: log.entries)
    }

    private var historyMetrics: some View {
        HStack(alignment: .center, spacing: 22) {
            metric(
                copy("observations.metric.identified"),
                "\(log.totalObjects) / \(session.catalog.objects.count)"
            )
            metric(copy("observations.metric.locks"), "\(totalLockCount)")

            Spacer(minLength: 4)

            if !log.entries.isEmpty {
                Button {
                    confirmClearLog = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.legacyTint.opacity(Palette.Level.present))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copy("observations.clear_all"))
            }
        }
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) { ContentHairline() }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.secondary))
            Text(value)
                .font(Typography.dataValue)
                .tracking(Typography.dataValueTracking)
                .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
        }
    }

    private var totalLockCount: Int {
        log.entries.reduce(0) { $0 + $1.count }
    }

    private func historySectionLabel(for day: Date) -> some View {
        let calendar = Calendar.current
        let label: String
        if calendar.isDateInToday(day) {
            label = copy("date.today")
        } else if calendar.isDateInYesterday(day) {
            label = copy("date.yesterday")
        } else {
            label = historyDayFormatter.string(from: day)
        }
        return Text(label)
            .font(Typography.statusTag)
            .tracking(1.1)
            .foregroundStyle(Palette.inkMid.opacity(Palette.Level.secondary))
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 18)
            .background(Palette.sheetBackground)
    }

    private func historyRow(_ entry: ObservationLog.Entry) -> some View {
        Button {
            path.append(.detail(entry.objectId))
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.objectName)
                            .font(Typography.guide)
                            .tracking(Typography.guideTracking)
                            .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        if entry.count > 1 {
                            Text("×\(entry.count)")
                                .font(Typography.statusTag)
                                .tracking(Typography.statusTagTracking)
                                .foregroundStyle(Palette.signal.opacity(Palette.Level.secondary))
                                .fixedSize()
                        }
                    }
                    if let category = historyCategory(for: entry) {
                        Text(category)
                            .font(Typography.statusTag)
                            .tracking(Typography.statusTagTracking)
                            .foregroundStyle(Palette.inkLow.opacity(Palette.Level.secondary))
                    }
                }
                Spacer(minLength: 8)
                Text(Self.historyTimeFormatter.string(from: entry.lastSeen))
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkMid.opacity(Palette.Level.secondary))
                    .frame(width: 48, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                    .frame(width: 20, height: 34)
            }
            .frame(minHeight: 62)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { ContentHairline() }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            L10n.format(
                "observations.row.accessibility",
                language: language,
                entry.objectName,
                Self.historyDateFormatter.string(from: entry.lastSeen),
                entry.count
            )
        )
        .accessibilityHint(copy("observations.detail.hint"))
    }

    private func historyCategory(for entry: ObservationLog.Entry) -> String? {
        (session.catalog.objectsByID[entry.objectId]?.category ?? entry.category)?
            .title(language: language)
    }

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy("observations.empty.title"))
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
            Text(copy("observations.empty.body"))
                .font(Typography.statusTag)
                .tracking(0.45)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { ContentHairline() }
        .overlay(alignment: .bottom) { ContentHairline() }
    }

    private func detailPage(objectID: String) -> some View {
        AppPageShell(
            backTitle: copy("navigation.observations"),
            title: copy("navigation.observation_detail"),
            onBack: popDetail,
            isRoot: false
        ) {
            observationDetail(objectID: objectID)
        }
    }

    @ViewBuilder
    private func observationDetail(objectID: String) -> some View {
        if let entry = log.entries.first(where: { $0.objectId == objectID }),
           let object = session.catalog.objectsByID[objectID] ?? archivedObject(from: entry) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(object.name)
                        .font(Typography.archiveObjectName)
                        .tracking(Typography.objectNameTracking)
                        .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                        .lineLimit(2)

                    Text("\(object.cosparId)  ·  N\(object.noradId)")
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                        .padding(.top, 6)

                    Text(roleTitle(for: object))
                        .font(Typography.statusTag)
                        .tracking(0.7)
                        .foregroundStyle(Palette.signal.opacity(0.72))
                        .padding(.top, 16)

                    Text(
                        object.deepArchivePresentation(language: language)?.story.lead
                            ?? L10n.format(
                                "observations.object.fallback",
                                language: language,
                                object.cosparId,
                                object.orbitClass
                            )
                    )
                    .font(Typography.archivePoetic)
                    .tracking(Typography.archivePoeticTracking)
                    .lineSpacing(Typography.archivePoeticLineSpacing)
                    .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.bottom, 24)

                    sectionLabel(copy("settings.section.observation"))
                        .padding(.bottom, 8)
                    detailField(
                        copy("observations.field.latest_lock"),
                        Self.historyDateFormatter.string(from: entry.lastSeen)
                    )
                    detailField(
                        copy("observations.field.first_lock"),
                        Self.historyDateFormatter.string(from: entry.firstSeen)
                    )
                    detailField(copy("observations.field.total"), "\(entry.count)")
                    if let observedAt = entry.observedAt {
                        detailField(
                            copy("observations.field.time"),
                            Self.historyDateFormatter.string(from: observedAt)
                        )
                    }

                    sectionLabel(copy("observations.section.orbit_snapshot"))
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    orbitalSnapshot(entry: entry, object: object)

                    sectionLabel(copy("observations.section.mission"))
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    detailField(
                        copy("observations.field.category"),
                        object.category.title(language: language)
                    )
                    detailField(copy("observations.field.orbit"), object.orbitClass)
                    detailField(copy("observations.field.launch"), object.launched)
                    detailField(copy("observations.field.status"), statusText(for: object.status))
                }
                .padding(.horizontal, 30)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        } else {
            emptyHistory
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func archivedObject(from entry: ObservationLog.Entry) -> CatalogObject? {
        guard let category = entry.category,
              let cosparId = entry.cosparId,
              let noradId = entry.noradId,
              let orbitClass = entry.orbitClass,
              let launched = entry.launched,
              let status = entry.status,
              let kind = entry.kind else { return nil }
        return CatalogObject(
            id: entry.objectId,
            name: entry.objectName,
            noradId: noradId,
            cosparId: cosparId,
            orbitClass: orbitClass,
            launched: launched,
            status: status,
            kind: kind,
            category: category,
            family: entry.family,
            elementEpoch: entry.observedAt ?? entry.lastSeen,
            isCurated: false,
            orbitFingerprint: OrbitFingerprint(
                periodMinutes: 0,
                inclinationDegrees: 0,
                eccentricity: 0,
                perigeeKm: 0,
                apogeeKm: 0
            )
        )
    }

    @ViewBuilder
    private func orbitalSnapshot(
        entry: ObservationLog.Entry,
        object: CatalogObject
    ) -> some View {
        let fallback = session.ephemeris.ephemeris(
            object.id,
            at: entry.observedAt ?? entry.lastSeen,
            live: false
        )
        let azimuth = entry.azimuth ?? fallback?.azimuth
        let elevation = entry.elevation ?? fallback?.elevation
        let altitude = entry.altitudeKm ?? fallback?.altitudeKm
        let range = entry.rangeKm ?? fallback?.rangeKm
        let velocity = entry.velocityKmS ?? fallback?.velocityKmS

        if let azimuth {
            detailField(
                copy("observations.field.azimuth"),
                String(format: "%.1f°", azimuth * 180 / .pi)
            )
        }
        if let elevation {
            detailField(
                copy("observations.field.elevation"),
                String(format: "%+.1f°", elevation * 180 / .pi)
            )
        }
        if let altitude {
            detailField(copy("observations.field.altitude"), String(format: "%.0f KM", altitude))
        }
        if let range {
            detailField(copy("observations.field.range"), String(format: "%.0f KM", range))
        }
        if let velocity {
            detailField(copy("observations.field.speed"), String(format: "%.2f KM/S", velocity))
        }
    }

    private func detailField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.secondary))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(Typography.archiveDataValue)
                .tracking(Typography.dataValueTracking)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
        .overlay(alignment: .bottom) { ContentHairline() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.fieldLabel)
            .tracking(Typography.fieldLabelTracking + 0.5)
            .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
    }

    private func roleTitle(for object: CatalogObject) -> String {
        if let family = object.family {
            return L10n.format("role.constellation", language: language, family.title)
        }
        return switch object.kind {
        case "station": copy("role.station")
        case "telescope": copy("role.telescope")
        case "weather": copy("role.weather")
        case "nav": copy("role.navigation")
        case "comms": copy("role.communications")
        case "science": copy("role.science")
        case "debris": copy("role.debris")
        case "rocket_body": copy("role.rocket_body")
        default: copy("role.object")
        }
    }

    private func statusText(for status: CatalogObject.Status) -> String {
        switch status {
        case .active: copy("object.status.cataloged")
        case .silent: copy("object.status.silent")
        case .derelict: copy("object.status.derelict")
        case .debris: copy("object.status.debris")
        }
    }

    private func popDetail() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd  HH:mm"
        return formatter
    }()

    private static let historyTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var historyDayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }
}
