import SwiftUI

/// 深空档案信息层。锁定态浮现，释放态整体消隐。
///
/// 不是百科卡片 —— 是一份来自深空仪器的任务档案：
/// 独特故事与任务身份优先，少量遥测只负责建立尺度感。
struct ArchiveOverlay: View {
    let object: CatalogObject
    let ephemeris: Ephemeris?
    let revealed: Bool
    /// 锁定确认 0...1；用于先建立档案边界，再交给逐行正文。
    var lockProgress: Double = 1
    /// 主动归还 0...1；档案、联系线与锁定标记共享同一进度源。
    var releaseProgress: Double = 0
    /// 过境预报（LIVE 下有意义）。
    var nextPass: PassPredictor.Prediction = .none
    /// 非 LIVE 时的观测时刻标注（如 "T+02:14:36"）；nil = LIVE。
    var observationTimeLabel: String? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    /// 视图插入时 `revealed` 已经为 true；用本地状态制造真实的隐藏 → 显示跃迁。
    @State private var presentationVisible = false

    private var contentVisible: Bool { revealed && presentationVisible }
    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var clampedLockProgress: Double { min(1, max(0, lockProgress)) }
    private var clampedReleaseProgress: Double { min(1, max(0, releaseProgress)) }
    private var isReleasing: Bool { !revealed || clampedReleaseProgress > 0.001 }

    private var statusText: String {
        switch object.status {
        case .active: "ACTIVE"
        case .silent: "SILENT"
        case .derelict: "DERELICT"
        case .debris: "DEBRIS"
        }
    }

    private var statusColor: Color {
        object.status.isActive ? Palette.activeTint : Palette.derelictTint
    }

    private var roleTitle: String {
        if object.isStarlink { return "STARLINK CONSTELLATION · 星座节点" }
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

    private var orbitNarrative: String {
        switch object.orbitClass {
        case "LEO": "近地轨道 · 快速越过天空"
        case "MEO": "中地轨道 · 长周期导航带"
        case "GEO": "地球同步轨道 · 近似固定方位"
        case "HEO": "高椭圆轨道 · 远地点缓慢停留"
        default: "\(object.orbitClass) 轨道"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            readingVeil

            VStack(alignment: .leading, spacing: 6) {
                lockHeader

                // 名称
                Text(object.name)
                    .font(Typography.archiveObjectName)
                    .tracking(Typography.objectNameTracking)
                    .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .archiveReveal(index: 0, revealed: contentVisible)

                // 编号行
                Text("\(object.cosparId)  ·  N\(String(object.noradId))")
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.bottom, 4)
                    .archiveReveal(index: 1, revealed: contentVisible)

                Text(roleTitle)
                    .font(Typography.statusTag)
                    .tracking(0.7)
                    .foregroundStyle(object.identityTint.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .archiveReveal(index: 2, revealed: contentVisible)

                // 每个对象独有的历史句，成为档案的视觉主体。
                Text(object.poetic)
                    .font(Typography.archivePoetic)
                    .tracking(Typography.archivePoeticTracking)
                    .lineSpacing(Typography.archivePoeticLineSpacing)
                    .foregroundStyle(Palette.inkLow.opacity(0.72))
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .archiveReveal(index: 3, revealed: contentVisible)

                Text(orbitNarrative)
                    .font(Typography.statusTag)
                    .tracking(0.55)
                    .foregroundStyle(Palette.inkLow.opacity(0.72))
                    .padding(.top, 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .archiveReveal(index: 4, revealed: contentVisible)

                readoutDivider
                    .archiveReveal(index: 5, revealed: contentVisible)

                // 少量关键遥测建立尺度感，其余参数退出主档案。
                Group {
                    if let label = observationTimeLabel {
                        ArchiveField(label: "TIME", value: label, valueColor: Palette.signal)
                            .archiveReveal(index: 6, revealed: contentVisible)
                    }
                    if let eph = ephemeris {
                        ArchiveField(label: "ALT", value: String(format: "%.0f KM", eph.altitudeKm))
                            .archiveReveal(index: 7, revealed: contentVisible)
                    }
                    ArchiveField(label: "LAUNCH", value: object.launched)
                        .archiveReveal(index: 8, revealed: contentVisible)
                    ArchiveField(label: "STATUS", value: statusText, valueColor: statusColor)
                        .archiveReveal(index: 9, revealed: contentVisible)
                    if observationTimeLabel == nil,
                       let pass = PassPredictor.label(for: nextPass) {
                        ArchiveField(label: pass.label, value: pass.value, valueColor: Palette.signal)
                            .archiveReveal(index: 10, revealed: contentVisible)
                    }
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .padding(.vertical, 7)
        }
        .opacity(
            (0.28 + 0.72 * clampedLockProgress)
                * (1 - 0.18 * clampedReleaseProgress)
        )
        .offset(
            x: suppressMotion
                ? 0
                : -8 * (1 - clampedLockProgress) - 3 * clampedReleaseProgress
        )
        .scaleEffect(
            x: suppressMotion ? 1 : 1 - 0.012 * clampedReleaseProgress,
            y: 1,
            anchor: .leading
        )
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .task(id: object.id) {
            // 先建立联系线和档案边界，正文随后出现，避免所有元素同帧弹出。
            presentationVisible = false
            await Task.yield()
            if !suppressMotion {
                try? await Task.sleep(for: .seconds(Motion.archiveContentDelay))
            }
            guard !Task.isCancelled else { return }
            presentationVisible = revealed
        }
        .onChange(of: revealed) { _, newValue in
            // releasing 时反向消隐；中途重新锁定则从当前透明度自然反向。
            presentationVisible = newValue
        }
    }

    private var readingVeil: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                stops: [
                    .init(color: Palette.voidBlack.opacity(0.92), location: 0),
                    .init(color: Palette.voidBlack.opacity(0.68), location: 0.68),
                    .init(color: Palette.voidBlack.opacity(0.08), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            Rectangle()
                .fill(object.identityTint.opacity(0.34))
                .frame(width: 0.5)
                .padding(.vertical, 4)
        }
        .opacity(clampedLockProgress * (1 - clampedReleaseProgress))
        .mask(alignment: .leading) {
            Rectangle()
                .scaleEffect(x: max(0.001, clampedLockProgress), anchor: .leading)
        }
        .allowsHitTesting(false)
    }

    private var lockHeader: some View {
        HStack(spacing: 6) {
            ArchiveLockGlyph(
                tint: object.identityTint,
                progress: clampedLockProgress,
                releasing: clampedReleaseProgress
            )

            ZStack(alignment: .leading) {
                Text("LOCKED")
                    .opacity(isReleasing ? 0 : 1)
                Text("RETURN")
                    .opacity(isReleasing ? 1 : 0)
            }
            .font(Typography.statusTag)
            .tracking(1.15)
            .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .layoutPriority(1)

            Spacer(minLength: 4)

            Text(isReleasing ? "CLOSING" : "LINK")
                .font(Typography.statusTag)
                .tracking(0.9)
                .foregroundStyle(object.identityTint.opacity(isReleasing ? 0.36 : 0.66))
                .lineLimit(1)
        }
        .frame(height: 30)
        .opacity(0.22 + 0.78 * clampedLockProgress)
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(object.identityTint.opacity(0.30))
                .frame(height: 0.5)
                .scaleEffect(
                    x: max(0.001, clampedLockProgress * (1 - clampedReleaseProgress)),
                    anchor: .leading
                )
        }
    }

    private var readoutDivider: some View {
        HStack(spacing: 7) {
            Text("READOUT")
                .font(Typography.statusTag)
                .tracking(1.15)
                .foregroundStyle(Palette.inkLow.opacity(0.58))
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.34))
                .frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }
}

private struct ArchiveLockGlyph: View {
    let tint: Color
    let progress: Double
    let releasing: Double

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.06, to: 0.23)
                .stroke(tint.opacity(0.72), style: StrokeStyle(lineWidth: 0.65, lineCap: .butt))
                .rotationEffect(.degrees(-45))
            Circle()
                .trim(from: 0.56, to: 0.73)
                .stroke(tint.opacity(0.72), style: StrokeStyle(lineWidth: 0.65, lineCap: .butt))
                .rotationEffect(.degrees(-45))
            Circle()
                .fill(Palette.inkHigh.opacity(0.84))
                .frame(width: 2.5, height: 2.5)
        }
        .frame(width: 15, height: 15)
        .rotationEffect(.degrees(10 * releasing))
        .scaleEffect(0.82 + 0.18 * progress + 0.16 * releasing)
        .opacity(progress * (1 - 0.62 * releasing))
        .accessibilityHidden(true)
    }
}
