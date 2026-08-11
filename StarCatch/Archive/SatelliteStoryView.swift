import SwiftUI

/// 单体卫星或大型星座的离线深度档案。策展事实与当前节点的实时轨道读数
/// 明确分区，避免把故事和瞬时位置混成同一种“参数表”。
struct SatelliteStoryView: View {
    let object: CatalogObject
    let story: SatelliteStory
    let ephemeris: Ephemeris?
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false
    @State private var revealed = false
    @State private var expandedChapterID: String?
    @State private var missionHistoryExpanded = false
    @State private var sourcesExpanded = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }

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

                    if let reference = story.officialReference {
                        officialReferenceLink(reference)
                            .padding(.bottom, 22)
                    }

                    sectionLabel("MISSION IN VIEW")
                    Text(story.lead)
                        .font(Typography.readingBody)
                        .tracking(Typography.readingBodyTracking)
                        .lineSpacing(4)
                        .foregroundStyle(Palette.inkMid.opacity(0.88))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.bottom, 24)

                    sectionLabel("ORBIT & IDENTITY")
                    VStack(spacing: 0) {
                        ForEach(preferredFacts) { fact in
                            storyField(fact.label, fact.value)
                        }
                        storyField("NORAD", "N\(object.noradId)")
                        storyField("COSPAR", object.cosparId)
                        storyField("发射", object.launched)
                        storyField("轨道", object.orbitClass)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                    if !story.chapters.isEmpty {
                        sectionLabel("MISSION NOTES")
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
                            title: "任务历程",
                            detail: "\(story.milestones.count) 个关键节点",
                            isExpanded: $missionHistoryExpanded
                        ) {
                            milestoneRail
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        }
                    }

                    compactDisclosure(
                        title: "资料与计算说明",
                        detail: "\(story.sources.count) 个离线来源",
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
                backTitle: "天空",
                title: "目标档案",
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
        .accessibilityLabel("打开\(reference.title)官方任务页面")
        .accessibilityHint("将在浏览器中打开外部网站")
    }

    private var preferredFacts: [SatelliteStory.Fact] {
        let priority = [
            "任务", "类型", "周期", "倾角", "估算近 / 远地点",
            "形态", "主镜", "观测", "档案范围",
        ]
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
                    label: "RANGE",
                    value: String(format: "%.0f KM", ephemeris.rangeKm)
                )
            }

            HStack(spacing: 0) {
                observationCell(
                    label: "ALT",
                    value: String(format: "%.0f KM", ephemeris.altitudeKm)
                )
                observationDivider
                observationCell(
                    label: "SPEED",
                    value: String(format: "%.2f KM/S", ephemeris.velocityKmS)
                )
                observationDivider
                observationCell(label: "ORBIT", value: object.orbitClass)
            }

            Text(observationSentence(ephemeris))
                .font(Typography.archiveNarrative)
                .tracking(0.25)
                .foregroundStyle(Palette.inkMid.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
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
        let directions = ["正北", "东北", "正东", "东南", "正南", "西南", "正西", "西北"]
        let index = Int((azimuth + 22.5) / 45).quotientAndRemainder(dividingBy: 8).remainder
        let visibility = ephemeris.elevation > 0
            ? "位于地平线上方"
            : "当前处于几何地平线下"
        return "此刻目标在\(directions[index])方向，\(visibility)。肉眼可见性还取决于日照、相位、天气与目标姿态。"
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
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCES · OFFLINE EDITION")
                .font(Typography.statusTag)
                .tracking(Typography.statusTagTracking)
                .foregroundStyle(Palette.inkLow.opacity(0.52))
            Text(story.sources.joined(separator: "  ·  "))
                .font(Typography.statusTag)
                .tracking(0.45)
                .foregroundStyle(Palette.inkLow.opacity(0.44))
                .fixedSize(horizontal: false, vertical: true)
            Text("历史叙述随版本校订；位置与速度由 App 内置 CelesTrak GP/OMM 元素在设备上推算。")
                .font(Typography.archiveNarrative)
                .tracking(0.45)
                .foregroundStyle(Palette.inkLow.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel("深入档案")
        .accessibilityHint("打开当前卫星或所属星座的离线任务档案")
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tint.opacity(0.88))
                Text("深入档案")
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
