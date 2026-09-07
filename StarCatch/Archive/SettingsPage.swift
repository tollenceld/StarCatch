import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 全屏设置页。只观察低频设备状态和本地显示偏好，不观察整颗 `SkySession`，
/// 避免姿态发布让设置内容反复重算。
struct SettingsPage: View {
    let session: SkySession
    let onBack: () -> Void
    let onOpenManual: () -> Void
    let onOpenPrivacy: () -> Void

    @ObservedObject private var observer: ObserverLocation
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.openURL) private var openURL

    @AppStorage("reducedMotion") private var reducedMotion = false
    @AppStorage("grainEnabled") private var grainEnabled = true
    @AppStorage("captureConfirmationEnabled") private var captureConfirmationEnabled = false
    @State private var path: [SettingsRoute]

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var language: SupportedLanguage { .current }
    private func copy(_ key: String) -> String { L10n.text(key, language: language) }

    init(
        session: SkySession,
        initialRoute: SettingsRoute? = nil,
        onBack: @escaping () -> Void = {},
        onOpenManual: @escaping () -> Void = {},
        onOpenPrivacy: @escaping () -> Void = {}
    ) {
        self.session = session
        self.onBack = onBack
        self.onOpenManual = onOpenManual
        self.onOpenPrivacy = onOpenPrivacy
        _observer = ObservedObject(wrappedValue: session.observer)
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            AppPageShell(
                backTitle: copy("navigation.sky"),
                title: copy("navigation.settings"),
                onBack: onBack
            ) {
                pageContent {
                    ScrollView(showsIndicators: false) {
                        panelContent
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .accessibilityHidden(!path.isEmpty)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .systemStatus:
                    AppPageShell(
                        backTitle: copy("navigation.settings"),
                        title: copy("navigation.instrument_status"),
                        onBack: popRoute
                    ) {
                        pageContent { systemStatus }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func pageContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            StaticDustBackdrop()
                .ignoresSafeArea()
                .opacity(0.14)
                .colorEffect(
                    ShaderLibrary.grain(
                        .float(0),
                        .float(grainEnabled ? 0.024 : 0)
                    )
                )
                .allowsHitTesting(false)

            content()
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(copy("settings.section.display"))
                .padding(.top, 18)
                .padding(.bottom, 6)
            displayControls
                .padding(.bottom, 26)

            sectionLabel(copy("settings.section.help"))
                .padding(.bottom, 6)
            actionRow(
                eyebrow: copy("settings.status.eyebrow"),
                title: copy("settings.status.title")
            ) {
                path.append(.systemStatus)
            }
            actionRow(
                eyebrow: copy("settings.manual.eyebrow"),
                title: copy("settings.manual.title"),
                action: onOpenManual
            )
            actionRow(
                eyebrow: copy("settings.privacy.eyebrow"),
                title: copy("settings.privacy.title"),
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
        .padding(.bottom, 30)
    }

    private var displayControls: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: copy("settings.grain.title"),
                caption: copy("settings.grain.caption"),
                isOn: $grainEnabled
            )
            hairline
            toggleRow(
                title: copy("settings.motion.title"),
                caption: copy("settings.motion.caption"),
                isOn: $reducedMotion
            )
            hairline
            toggleRow(
                title: copy("settings.capture.title"),
                caption: copy("settings.capture.caption"),
                isOn: $captureConfirmationEnabled
            )
        }
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private var systemStatus: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel(copy("status.section.device"))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                statusField(copy("status.field.observer"), observerDescription)
                statusField(copy("status.field.location_permission"), authorizationDescription)
                statusField(copy("status.field.pointing"), pointingDescription)
                statusField(copy("status.field.motion_service"), availabilityDescription)

                if observer.isDeniedOrRestricted {
                    openSettingsButton
                }

                sectionLabel(copy("status.section.catalog"))
                    .padding(.top, 26)
                    .padding(.bottom, 8)
                statusField(
                    copy("status.field.objects"),
                    L10n.format(
                        "status.objects",
                        language: language,
                        session.catalog.objects.count
                    )
                )
                statusField(copy("status.field.snapshot"), snapshotDescription)
                statusField(copy("status.field.age"), catalogAgeDescription)
                statusField(copy("status.field.runtime"), copy("status.runtime.offline"))

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

                sectionLabel(copy("status.section.support"))
                    .padding(.top, 28)
                    .padding(.bottom, 6)
                externalActionRow(
                    eyebrow: copy("status.support.eyebrow"),
                    title: copy("status.support.title"),
                    url: AppLinks.support
                )
                externalActionRow(
                    eyebrow: copy("status.source.eyebrow"),
                    title: copy("status.source.title"),
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
        if coordinates.assumed { return copy("status.observer.assumed") }
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
        case .authorizedAlways, .authorizedWhenInUse: copy("status.permission.allowed")
        case .denied: copy("status.permission.denied")
        case .restricted: copy("status.permission.restricted")
        case .notDetermined: copy("status.permission.not_requested")
        @unknown default: copy("status.value.unknown")
        }
    }

    private var pointingDescription: String {
        switch session.confidence {
        case .trueNorth: copy("status.pointing.true_north")
        case .uncalibrated: copy("status.pointing.uncalibrated")
        case .manual: copy("status.pointing.manual")
        }
    }

    private var availabilityDescription: String {
        switch session.pointingAvailability {
        case .idle: copy("status.service.idle")
        case .starting: copy("status.service.starting")
        case .tracking: copy("status.service.tracking")
        case .manual: copy("status.service.manual")
        case .unavailable: copy("status.service.unavailable")
        }
    }

    private var snapshotDescription: String {
        guard session.catalog.snapshotEpoch != .distantPast else {
            return copy("status.service.unavailable")
        }
        return Self.snapshotDateFormatter.string(from: session.catalog.snapshotEpoch)
    }

    private var catalogAgeDescription: String {
        let age = session.tleAgeDays
        return L10n.format(
            age <= 14 ? "status.catalog.current" : "status.catalog.update",
            language: language,
            age
        )
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
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(copy(isOn.wrappedValue ? "accessibility.on" : "accessibility.off"))
        .accessibilityHint(copy("accessibility.toggle"))
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
            eyebrow: copy("settings.location.eyebrow"),
            title: copy("settings.location.title"),
            icon: "arrow.up.right"
        ) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        #endif
    }

    private var hairline: some View {
        ContentHairline()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.fieldLabel)
            .tracking(Typography.fieldLabelTracking + 0.5)
            .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        return "V\(version)"
    }

    private func popRoute() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}
