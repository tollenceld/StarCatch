import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 日常设置页。只保留会影响观测的偏好、观测进度与必要帮助。
/// 标准字号下一屏完成；极小设备或放大字体时才降级为滚动，保证可访问性。
struct InstrumentPanel: View {
    enum Destination {
        case settings
        case systemStatus
        case observations
    }

    private enum Page: Equatable {
        case settings
        case systemStatus
        case observations
        case observationDetail(String)
    }

    @Binding var presented: Bool
    /// 内容页只读取会话的目录与低频状态快照；不要观察整颗 SkySession。
    /// 否则主天空的高频 pointing 发布会让设置和长记录列表整页失效重算。
    let session: SkySession
    @ObservedObject private var observer: ObserverLocation
    @ObservedObject private var log: ObservationLog

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.openURL) private var openURL

    let onOpenManual: () -> Void
    let onOpenPrivacy: () -> Void
    let onOpenOverview: () -> Void

    @AppStorage("reducedMotion") private var reducedMotion = false
    @AppStorage("grainEnabled") private var grainEnabled = true
    @AppStorage("captureConfirmationEnabled") private var captureConfirmationEnabled = false

    @State private var revealed = false
    @State private var dismissRequested = false
    @State private var confirmClearLog = false
    @State private var page: Page = .settings
    @State private var historyScrollPosition: String?
    @State private var navigationForward = true

    private struct HistorySection: Identifiable {
        let day: Date
        let entries: [ObservationLog.Entry]
        var id: Date { day }
    }

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var navigationAnimation: Animation {
        suppressMotion ? .easeOut(duration: 0.16) : Motion.interfaceExpand
    }
    private var pageKey: String {
        switch page {
        case .settings: "settings"
        case .systemStatus: "status"
        case .observations: "observations"
        case .observationDetail(let objectId): "observation-\(objectId)"
        }
    }
    private var pageTransition: AnyTransition {
        let insertionEdge: Edge = navigationForward ? .trailing : .leading
        let removalEdge: Edge = navigationForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    init(
        presented: Binding<Bool>,
        session: SkySession,
        initialDestination: Destination = .settings,
        onOpenOverview: @escaping () -> Void = {},
        onOpenManual: @escaping () -> Void = {},
        onOpenPrivacy: @escaping () -> Void = {}
    ) {
        _presented = presented
        self.session = session
        _observer = ObservedObject(wrappedValue: session.observer)
        _log = ObservedObject(wrappedValue: session.log)
        let initialPage: Page = switch initialDestination {
        case .settings: .settings
        case .systemStatus: .systemStatus
        case .observations: .observations
        }
        _page = State(initialValue: initialPage)
        self.onOpenOverview = onOpenOverview
        self.onOpenManual = onOpenManual
        self.onOpenPrivacy = onOpenPrivacy
    }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()
            StaticDustBackdrop()
                .ignoresSafeArea()
                .opacity(0.28)
                // 颗粒即时预览只处理背景。对整个 ScrollView 做 Metal 离屏渲染
                // 会让部分系统版本漏绘 LazyVStack 的记录行。
                .colorEffect(
                    ShaderLibrary.grain(
                        .float(0),
                        .float(grainEnabled ? 0.024 : 0)
                    )
                )

            Group {
                switch page {
                case .settings:
                    ScrollView(showsIndicators: false) {
                        panelContent
                    }
                    .scrollBounceBehavior(.basedOnSize)

                case .systemStatus:
                    systemStatus

                case .observations:
                    observationHistory

                case .observationDetail(let objectId):
                    observationDetail(objectId: objectId)
                }
            }
            .id(pageKey)
            .transition(pageTransition)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topNavigationBar
        }
        .appEdgeBackGesture(action: navigateBack)
        .opacity(revealed ? 1 : 0)
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--openObservationDetail"), let first = log.entries.first {
                page = .observationDetail(first.objectId)
            } else if args.contains("--openStatus") {
                page = .systemStatus
            } else if args.contains("--openObservations") {
                page = .observations
            }
            #endif
            withAnimation(navigationAnimation) {
                revealed = true
            }
        }
        .confirmationDialog(
            "清除全部观测记录？",
            isPresented: $confirmClearLog,
            titleVisibility: .visible
        ) {
            Button("清除记录", role: .destructive) { log.clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("显示偏好与手册状态不会被清除。")
        }
    }

    // MARK: - 单屏信息架构

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("显示")
                .padding(.top, 18)
                .padding(.bottom, 6)
            displayControls
                .padding(.bottom, 24)

            sectionLabel("观测")
                .padding(.bottom, 6)
            observationSummary

            sectionLabel("帮助")
                .padding(.top, 24)
                .padding(.bottom, 6)
            actionRow(
                eyebrow: "STATUS & DATA",
                title: "仪器状态与轨道数据"
            ) {
                push(.systemStatus)
            }
            actionRow(
                eyebrow: "FIELD MANUAL",
                title: "重新查看观测手册",
                action: onOpenManual
            )
            actionRow(
                eyebrow: "PRIVACY",
                title: "隐私与设备内数据",
                action: onOpenPrivacy
            )
            if observer.isDeniedOrRestricted {
                openSettingsButton
            }

            Text("STARCATCH · \(versionText)")
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                .padding(.top, 22)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
    }

    private var displayControls: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: "介质颗粒",
                caption: "画面颗粒与扫描纹理。",
                isOn: $grainEnabled
            )
            hairline
            toggleRow(
                title: "抑制动效",
                caption: "冻结漂移与呼吸，缩短转场。",
                isOn: $reducedMotion
            )
            hairline
            toggleRow(
                title: "确认捕获",
                caption: "在主视野显示确认、切换与取消操作。",
                isOn: $captureConfirmationEnabled
            )
        }
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private var observationSummary: some View {
        Button {
            push(.observations)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("观测记录")
                        .font(Typography.guide)
                        .tracking(Typography.guideTracking)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                    Text("已识别 \(log.totalObjects) 个 · 共锁定 \(totalLockCount) 次")
                        .font(Typography.readingCompact)
                        .tracking(Typography.readingCompactTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                    Text("最近：\(log.entries.first?.objectName ?? "尚无记录")")
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.secondary))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                    .frame(width: 24, height: 34)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { hairline }
            .overlay(alignment: .bottom) { hairline }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "已识别 \(log.totalObjects) 个天体，最近观测 \(log.entries.first?.objectName ?? "尚无记录")"
        )
        .accessibilityHint("打开完整观测记录")
    }

    // MARK: - 仪器状态与数据

    private var systemStatus: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("设备")
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                statusField("观察者", observerDescription)
                statusField("定位权限", authorizationDescription)
                statusField("指向", pointingDescription)
                statusField("姿态服务", availabilityDescription)

                if observer.isDeniedOrRestricted {
                    openSettingsButton
                }

                sectionLabel("轨道目录")
                    .padding(.top, 26)
                    .padding(.bottom, 8)
                statusField("对象", "\(session.catalog.objects.count) OBJECTS")
                statusField("快照", snapshotDescription)
                statusField("龄期", catalogAgeDescription)
                statusField("运行", "OFFLINE · ON DEVICE")

                Text("目录来自 CelesTrak GP/OMM 快照；SatelliteKit 在设备上执行 SGP4 传播。轨道数据不会在运行时联网刷新。")
                    .font(Typography.archivePoetic)
                    .tracking(Typography.archivePoeticTracking)
                    .lineSpacing(Typography.archivePoeticLineSpacing)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                Text("仅供教育与观测，不用于导航、碰撞规避或安全决策。")
                    .font(Typography.statusTag)
                    .tracking(0.35)
                    .foregroundStyle(Palette.signal.opacity(Palette.Level.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                sectionLabel("支持与归属")
                    .padding(.top, 28)
                    .padding(.bottom, 6)
                externalActionRow(
                    eyebrow: "GITHUB ISSUES",
                    title: "反馈问题与获取支持",
                    url: AppLinks.support
                )
                externalActionRow(
                    eyebrow: "SOURCE & LICENSE",
                    title: "项目源码与开源许可",
                    url: AppLinks.project
                )

                Text("StarCatch 与 SatelliteKit 依据 MIT License 发布。轨道目录归属 CelesTrak；完整声明随项目公开发布。")
                    .font(Typography.statusTag)
                    .tracking(0.45)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }

    private var observerDescription: String {
        let coordinates = observer.coordinates
        if coordinates.assumed { return "BEIJING · ASSUMED" }
        let latitude = String(
            format: "%.2f°%@",
            abs(coordinates.latitude),
            coordinates.latitude >= 0 ? "N" : "S"
        )
        let longitude = String(
            format: "%.2f°%@",
            abs(coordinates.longitude),
            coordinates.longitude >= 0 ? "E" : "W"
        )
        return "\(latitude)  \(longitude)"
    }

    private var authorizationDescription: String {
        switch observer.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "ALLOWED"
        case .denied: "DENIED · USING ASSUMED"
        case .restricted: "RESTRICTED · USING ASSUMED"
        case .notDetermined: "NOT REQUESTED"
        @unknown default: "UNKNOWN"
        }
    }

    private var pointingDescription: String {
        switch session.confidence {
        case .trueNorth: "TRUE NORTH"
        case .uncalibrated: "UNCALIBRATED · 请缓慢转动设备"
        case .manual: "MANUAL · SIMULATION"
        }
    }

    private var availabilityDescription: String {
        switch session.pointingAvailability {
        case .idle: "IDLE"
        case .starting: "STARTING"
        case .tracking: "TRACKING"
        case .manual: "MANUAL"
        case .unavailable: "UNAVAILABLE"
        }
    }

    private var snapshotDescription: String {
        guard session.catalog.snapshotEpoch != .distantPast else { return "UNAVAILABLE" }
        return Self.snapshotDateFormatter.string(from: session.catalog.snapshotEpoch)
    }

    private var catalogAgeDescription: String {
        let age = session.tleAgeDays
        if age <= 14 { return "\(age)D · CURRENT" }
        return "\(age)D · UPDATE APP"
    }

    private static let snapshotDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func statusField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.secondary))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(Typography.archiveDataValue)
                .tracking(Typography.dataValueTracking)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
        .overlay(alignment: .bottom) { hairline }
    }

    private func externalActionRow(eyebrow: String, title: String, url: URL) -> some View {
        actionRow(eyebrow: eyebrow, title: title, icon: "arrow.up.right") {
            openURL(url)
        }
    }

    // MARK: - 观测记录二级页

    private var observationHistory: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                historyMetrics
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if log.entries.isEmpty {
                    emptyHistory
                        .padding(.top, 12)
                } else {
                    ForEach(Array(historySections.enumerated()), id: \.element.id) { index, section in
                        Section {
                            ForEach(section.entries) { entry in
                                ObservationSwipeRow(
                                    onDelete: { log.remove(objectId: entry.objectId) }
                                ) {
                                    historyRow(entry)
                                }
                                .id(entry.objectId)
                            }
                        } header: {
                            historySectionLabel(
                                for: section.day,
                                isFirst: index == 0
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 22)
        }
        .scrollPosition(id: $historyScrollPosition)
    }

    private var historySections: [HistorySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: log.entries) {
            calendar.startOfDay(for: $0.lastSeen)
        }
        return grouped.keys.sorted(by: >).map { day in
            HistorySection(
                day: day,
                entries: grouped[day, default: []].sorted { $0.lastSeen > $1.lastSeen }
            )
        }
    }

    private func historySectionLabel(for day: Date, isFirst: Bool) -> some View {
        let calendar = Calendar.current
        let label: String
        if calendar.isDateInToday(day) {
            label = "今天"
        } else if calendar.isDateInYesterday(day) {
            label = "昨天"
        } else {
            label = Self.historyDayFormatter.string(from: day)
        }
        return Text(label)
            .font(Typography.statusTag)
            .tracking(1.1)
            .foregroundStyle(Palette.inkMid.opacity(Palette.Level.secondary))
            .padding(.top, isFirst ? 16 : 14)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.voidBlack.opacity(0.985))
    }

    private var historyMetrics: some View {
        HStack(spacing: 28) {
            metric("已识别", "\(log.totalObjects) / \(session.catalog.objects.count)")
            metric("锁定次数", "\(totalLockCount)")
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
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

    private func historyRow(_ entry: ObservationLog.Entry) -> some View {
        Button {
            push(.observationDetail(entry.objectId))
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
            .frame(minHeight: 54)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { hairline }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(entry.objectName)，最近观测 \(Self.historyDateFormatter.string(from: entry.lastSeen))，共 \(entry.count) 次"
        )
        .accessibilityHint("查看该天体的观测详情")
    }

    private func historyCategory(for entry: ObservationLog.Entry) -> String? {
        (
            session.catalog.objectsByID[entry.objectId]?.category ?? entry.category
        )?.title
    }

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("尚无观测记录")
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
            Text("将准星对准人造天体可即时阅读档案；开启“确认捕获”并确认目标后，观测会保存在这台设备上。")
                .font(Typography.statusTag)
                .tracking(0.45)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
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

    private static let historyDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter
    }()

    // MARK: - 单条观测详情

    @ViewBuilder
    private func observationDetail(objectId: String) -> some View {
        if let entry = log.entries.first(where: { $0.objectId == objectId }),
           let object = session.catalog.objectsByID[objectId] ?? archivedObject(from: entry) {
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

                    Text(object.poetic)
                        .font(Typography.archivePoetic)
                        .tracking(Typography.archivePoeticTracking)
                        .lineSpacing(Typography.archivePoeticLineSpacing)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.bottom, 24)

                    sectionLabel("观测")
                        .padding(.bottom, 8)
                    detailField("最近锁定", Self.historyDateFormatter.string(from: entry.lastSeen))
                    detailField("首次锁定", Self.historyDateFormatter.string(from: entry.firstSeen))
                    detailField("累计次数", "\(entry.count)")
                    if let observedAt = entry.observedAt {
                        detailField("观测时刻", Self.historyDateFormatter.string(from: observedAt))
                    }

                    sectionLabel("当时的轨道读数")
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    orbitalSnapshot(entry: entry, object: object)

                    sectionLabel("任务")
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    detailField("类别", object.category.title)
                    detailField("轨道", object.orbitClass)
                    detailField("发射", object.launched)
                    detailField("状态", statusText(for: object.status))
                }
                .padding(.horizontal, 30)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        } else {
            observationHistory
        }
    }

    private func archivedObject(from entry: ObservationLog.Entry) -> CatalogObject? {
        guard let category = entry.category,
              let cosparId = entry.cosparId,
              let noradId = entry.noradId,
              let orbitClass = entry.orbitClass,
              let launched = entry.launched,
              let status = entry.status,
              let kind = entry.kind,
              let poetic = entry.poetic else { return nil }
        return CatalogObject(
            id: entry.objectId,
            name: entry.objectName,
            noradId: noradId,
            cosparId: cosparId,
            orbitClass: orbitClass,
            launched: launched,
            status: status,
            kind: kind,
            poetic: poetic,
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
            detailField("方位", String(format: "%.1f°", azimuth * 180 / .pi))
        }
        if let elevation {
            detailField("仰角", String(format: "%+.1f°", elevation * 180 / .pi))
        }
        if let altitude {
            detailField("高度", String(format: "%.0f KM", altitude))
        }
        if let range {
            detailField("距离", String(format: "%.0f KM", range))
        }
        if let velocity {
            detailField("速度", String(format: "%.2f KM/S", velocity))
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
        .overlay(alignment: .bottom) { hairline }
    }

    private func roleTitle(for object: CatalogObject) -> String {
        if let family = object.family {
            return "\(family.title) CONSTELLATION · 星座节点"
        }
        return switch object.kind {
        case "station": "ORBITAL HABITAT · 载人设施"
        case "telescope": "SPACE OBSERVATORY · 空间望远镜"
        case "weather": "WEATHER WATCH · 气象观测"
        case "nav": "NAVIGATION CLOCK · 导航授时"
        case "comms": "SIGNAL RELAY · 通信中继"
        case "science": "SCIENCE MISSION · 科学任务"
        case "debris": "ORBITAL DEBRIS · 在轨碎片"
        case "rocket_body": "SPENT STAGE · 火箭末级"
        default: "ORBITAL OBJECT · 在轨物体"
        }
    }

    private func statusText(for status: CatalogObject.Status) -> String {
        switch status {
        case .active: "ACTIVE"
        case .silent: "SILENT"
        case .derelict: "DERELICT"
        case .debris: "DEBRIS"
        }
    }

    // MARK: - 交互元件

    private func toggleRow(
        title: String,
        caption: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: suppressMotion ? 0.16 : 0.28)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typography.guide)
                        .tracking(Typography.guideTracking)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                    Text(caption)
                        .font(Typography.readingCompact)
                        .tracking(Typography.readingCompactTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.readableSecondary))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                switchIndicator(isOn: isOn.wrappedValue)
                    .padding(.top, 1)
                    .fixedSize()
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "开启" : "关闭")
        .accessibilityHint("轻触切换")
    }

    private func switchIndicator(isOn: Bool) -> some View {
        ZStack {
            Capsule()
                .stroke(Palette.inkFaint.opacity(0.76), lineWidth: 0.6)
                .frame(width: 30, height: 16)
            Circle()
                .fill(
                    (isOn ? Palette.signal : Palette.inkLow)
                        .opacity(isOn ? 0.88 : Palette.Level.faint)
                )
                .frame(width: 7, height: 7)
                .offset(x: isOn ? 7 : -7)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private func actionRow(
        eyebrow: String,
        title: String,
        icon: String = "chevron.right",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typography.guide)
                        .tracking(Typography.guideTracking)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                    Text(eyebrow)
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                }
                Spacer(minLength: 8)
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                    .frame(width: 34, height: 34)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { hairline }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var openSettingsButton: some View {
        #if canImport(UIKit) && !targetEnvironment(simulator)
        actionRow(
            eyebrow: "LOCATION",
            title: "恢复真实位置权限",
            icon: "arrow.up.right"
        ) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        #endif
    }

    private var hairline: some View {
        Rectangle()
            .fill(Palette.inkFaint.opacity(Palette.Level.functionalDivider))
            .frame(height: 0.5)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.fieldLabel)
            .tracking(Typography.fieldLabelTracking + 0.5)
            .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
    }

    // MARK: - 统一顶部导航

    @ViewBuilder
    private var topNavigationBar: some View {
        switch page {
        case .settings:
            ArchiveTopBar(
                backTitle: "天空",
                title: "设置",
                onBack: dismiss
            )
        case .systemStatus:
            ArchiveTopBar(
                backTitle: "设置",
                title: "仪器状态",
                onBack: returnToSettings
            )
        case .observations:
            if !log.entries.isEmpty {
                ArchiveTopBar(
                    backTitle: "设置",
                    title: "观测记录",
                    trailingTitle: "更多",
                    trailingIcon: "ellipsis",
                    onBack: returnToSettings,
                    destructiveMenuTitle: "清除全部",
                    onDestructiveMenuAction: { confirmClearLog = true }
                )
            } else {
                ArchiveTopBar(
                    backTitle: "设置",
                    title: "观测记录",
                    onBack: returnToSettings
                )
            }
        case .observationDetail(_):
            ArchiveTopBar(
                backTitle: "观测记录",
                title: "记录详情",
                onBack: returnToObservations
            )
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        return "V\(version)"
    }

    private func returnToSettings() {
        navigationForward = false
        withAnimation(suppressMotion ? .easeOut(duration: 0.16) : Motion.interfaceCollapse) {
            page = .settings
        }
    }

    private func returnToObservations() {
        navigationForward = false
        withAnimation(suppressMotion ? .easeOut(duration: 0.16) : Motion.interfaceCollapse) {
            page = .observations
        }
    }

    private func push(_ destination: Page) {
        navigationForward = true
        withAnimation(navigationAnimation) {
            page = destination
        }
    }

    private func navigateBack() {
        switch page {
        case .settings:
            dismiss()
        case .systemStatus, .observations:
            returnToSettings()
        case .observationDetail:
            returnToObservations()
        }
    }

    private func dismiss() {
        guard !dismissRequested else { return }
        dismissRequested = true
        let duration = suppressMotion ? 0.16 : Motion.interfaceCollapseDuration
        withAnimation(suppressMotion ? .easeIn(duration: duration) : Motion.interfaceCollapse) {
            revealed = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            presented = false
        }
    }
}

/// `List` 的系统 Section 会注入不可控的标题边距和组间距；记录页改用自定义行，
/// 同时保留明确、克制的单条左滑删除能力。
private struct ObservationSwipeRow<Content: View>: View {
    let onDelete: () -> Void
    let content: Content

    @State private var offset: CGFloat = 0
    @State private var settledOffset: CGFloat = 0

    init(
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: delete) {
                Text("删除")
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.present))
                    .frame(width: 66)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.red.opacity(0.22))

            content
                .background(Palette.voidBlack.opacity(0.985))
                .offset(x: offset)
        }
        .clipped()
        .simultaneousGesture(swipeGesture)
        .accessibilityAction(named: "删除") { delete() }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, max(-88, settledOffset + value.translation.width))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let projected = settledOffset + value.predictedEndTranslation.width
                if projected < -116 {
                    delete()
                    return
                }
                let target: CGFloat = offset < -34 ? -66 : 0
                settledOffset = target
                withAnimation(.easeOut(duration: 0.2)) {
                    offset = target
                }
            }
    }

    private func delete() {
        withAnimation(.easeOut(duration: 0.18)) {
            offset = -88
        }
        onDelete()
    }
}
