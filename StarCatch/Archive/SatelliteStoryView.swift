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
                        .padding(.bottom, 28)

                    Text(story.lead)
                        .font(Typography.readingBody)
                        .tracking(Typography.readingBodyTracking)
                        .lineSpacing(Typography.readingBodyLineSpacing)
                        .foregroundStyle(Palette.inkMid.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 30)

                    ForEach(story.chapters) { chapter in
                        storyChapter(chapter)
                            .padding(.bottom, 26)
                    }

                    sectionLabel("MISSION ARC")
                    milestoneRail
                        .padding(.top, 12)
                        .padding(.bottom, 30)

                    sectionLabel("ARCHIVE FACTS")
                    VStack(spacing: 0) {
                        ForEach(story.facts) { fact in
                            storyField(fact.label, fact.value)
                        }
                        if object.family == nil {
                            storyField("NORAD", "N\(object.noradId)")
                            storyField("COSPAR", object.cosparId)
                            storyField("发射", object.launched)
                            storyField("轨道", object.orbitClass)
                        } else {
                            storyField("当前节点", object.name)
                            storyField("节点 NORAD", "N\(object.noradId)")
                            storyField("节点轨道", object.orbitClass)
                        }
                        if let ephemeris {
                            storyField("此刻高度", String(format: "%.0f KM", ephemeris.altitudeKm))
                            storyField("此刻距离", String(format: "%.0f KM", ephemeris.rangeKm))
                            storyField("此刻速度", String(format: "%.2f KM/S", ephemeris.velocityKmS))
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 30)

                    sourceNote
                }
                .padding(.horizontal, 30)
                .padding(.top, 18)
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

    private func storyChapter(_ chapter: SatelliteStory.Chapter) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(chapter.title)
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.inkHigh.opacity(0.86))
            Text(chapter.body)
                .font(Typography.readingBody)
                .tracking(Typography.readingBodyTracking)
                .lineSpacing(Typography.readingBodyLineSpacing)
                .foregroundStyle(Palette.inkMid.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
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
