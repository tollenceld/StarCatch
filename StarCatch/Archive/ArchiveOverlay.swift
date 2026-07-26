import SwiftUI

/// 深空档案信息层。锁定态浮现，释放态整体消隐。
///
/// 不是百科卡片 —— 是一份来自深空仪器的任务档案：
/// 独特故事与任务身份优先，少量遥测只负责建立尺度感。
struct ArchiveOverlay: View {
    let object: CatalogObject
    let ephemeris: Ephemeris?
    let revealed: Bool
    /// false 表示准星感应到的即时预览；true 才表示用户主动建立的持续捕获。
    var captured: Bool = true
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
    /// 铭牌定宽。由遥测栅格两列中文标签的可读下限决定，调用方据此在屏内定位。
    static let plateWidth: CGFloat = 252

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

    private var rangeText: String {
        guard let ephemeris else { return "RANGE —" }
        return String(format: "RANGE %.0f KM", ephemeris.rangeKm)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            readingVeil

            VStack(alignment: .leading, spacing: 0) {
                lockHeader
                    .padding(.bottom, 10)

                // 第一眼：它是谁。名称不再压缩到 0.82 倍 —— 允许折行，
                // 因为"读得清"比"占一行"重要。
                Text(object.name)
                    .font(Typography.archiveObjectName)
                    .tracking(Typography.objectNameTracking)
                    .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .archiveReveal(index: 0, revealed: contentVisible)

                // 身份行：状态灯 + 类别 + 编号。编号回到主面板，
                // 它是这颗目标唯一的、可被核对的身份。
                identityRow
                    .padding(.top, 7)
                    .archiveReveal(index: 1, revealed: contentVisible)

                // 一句任务叙述负责回答"它正在做什么"。
                Text(object.archiveNarrative)
                    .font(Typography.archivePoetic)
                    .tracking(Typography.archivePoeticTracking)
                    .lineSpacing(Typography.archivePoeticLineSpacing)
                    .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .archiveReveal(index: 2, revealed: contentVisible)

                readoutDivider
                    .padding(.top, 14)
                    .archiveReveal(index: 3, revealed: contentVisible)

                // 遥测改为两列定宽栅格：读数在固定位置，扫视时不必逐行查找标签。
                telemetryGrid
                    .padding(.top, 10)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
        }
        .frame(maxWidth: Self.plateWidth, alignment: .leading)
        .opacity(
            (0.28 + 0.72 * clampedLockProgress)
                * (1 - 0.18 * clampedReleaseProgress)
        )
        // 一块有重量的铭牌应该沉降到位，而不是从侧面滑入。位移改为极小的纵向落定，
        // 归还时同样向上收回。
        .offset(
            y: suppressMotion
                ? 0
                : -3 * (1 - clampedLockProgress) - 2 * clampedReleaseProgress
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

    /// 身份行：状态灯、任务类别、NORAD 编号。三者共同回答"这是什么、可信吗"。
    private var identityRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor.opacity(0.88))
                .frame(width: 3.5, height: 3.5)

            Text(statusText)
                .foregroundStyle(statusColor.opacity(0.88))

            Rectangle()
                .fill(Palette.inkFaint.opacity(0.34))
                .frame(width: 0.5, height: 9)

            Text(object.category.title)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))

            Rectangle()
                .fill(Palette.inkFaint.opacity(0.34))
                .frame(width: 0.5, height: 9)

            Text("N\(object.noradId)")
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
        }
        .font(Typography.statusTag)
        .tracking(0.82)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    /// 两列遥测栅格。距离与高度建立空间尺度，速度与方位建立运动尺度，
    /// 因此成对排布而不是排成一列长表。
    private var telemetryGrid: some View {
        let azimuth = ephemeris.map { eph -> String in
            let value = eph.azimuth < 0 ? eph.azimuth + 2 * .pi : eph.azimuth
            return String(format: "%.0f°", value * 180 / .pi)
        }
        let elevation = ephemeris.map { String(format: "%+.0f°", $0.elevation * 180 / .pi) }
        let range = ephemeris.map { String(format: "%.0f KM", $0.rangeKm) }
        let altitude = ephemeris.map { String(format: "%.0f KM", $0.altitudeKm) }
        let velocity = ephemeris.map { String(format: "%.2f KM/S", $0.velocityKmS) }

        return VStack(alignment: .leading, spacing: 9) {
            telemetryPair(
                leading: ("距离", range ?? "—", Palette.inkHigh),
                trailing: ("高度", altitude ?? "—", Palette.inkHigh),
                index: 4
            )
            telemetryPair(
                leading: ("速度", velocity ?? "—", Palette.inkHigh),
                trailing: ("轨道", object.orbitClass, Palette.inkMid),
                index: 5
            )
            telemetryPair(
                leading: ("方位", azimuth ?? "—", Palette.inkMid),
                trailing: ("仰角", elevation ?? "—", Palette.inkMid),
                index: 6
            )

            // 时刻与过境是互斥的：非 LIVE 时看观测时刻，LIVE 时看下次过境。
            if let label = observationTimeLabel {
                telemetryPair(
                    leading: ("时刻", label, Palette.signal),
                    trailing: nil,
                    index: 7
                )
            } else if let pass = PassPredictor.label(for: nextPass) {
                telemetryPair(
                    leading: (passTitle(pass.label), pass.value, Palette.signal),
                    trailing: nil,
                    index: 7
                )
            }
        }
    }

    private func telemetryPair(
        leading: (String, String, Color),
        trailing: (String, String, Color)?,
        index: Int
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            telemetryCell(leading.0, leading.1, leading.2)
            if let trailing {
                telemetryCell(trailing.0, trailing.1, trailing.2)
            } else {
                Spacer(minLength: 0)
            }
        }
        .archiveReveal(index: index, revealed: contentVisible)
    }

    /// 标签在上、读数在下。垂直堆叠让两列的读数自然对齐成一条基线网格，
    /// 比"标签值标签值"的横排更易扫视。
    private func telemetryCell(
        _ label: String,
        _ value: String,
        _ valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.statusTag)
                .tracking(0.9)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
            Text(value)
                .font(Typography.archiveDataValue)
                .tracking(Typography.dataValueTracking)
                .foregroundStyle(valueColor.opacity(Palette.Level.full))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 104, alignment: .leading)
    }

    private func passTitle(_ raw: String) -> String {
        switch raw {
        case "NEXT PASS": "下次过境"
        case "PASS IN": "过境倒计时"
        default: raw
        }
    }

    /// 档案底板。原设计是一层向右淡出的渐变，文字末端悬在星空上，
    /// 因此显得轻。改为有明确边界的暗色板：四边收口，左缘一道身份色标，
    /// 让它读作"一块贴在视野上的仪器铭牌"。
    private var readingVeil: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Palette.voidBlack.opacity(0.90))
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Palette.inkFaint.opacity(0.34), lineWidth: 0.5)
                }

            Rectangle()
                .fill(object.identityTint.opacity(0.62))
                .frame(width: 1.5)
        }
        .opacity(clampedLockProgress * (1 - clampedReleaseProgress))
        .mask(alignment: .top) {
            // 底板从顶部向下展开，与锁定确认同相：先立边界，再填内容。
            Rectangle()
                .scaleEffect(y: max(0.001, clampedLockProgress), anchor: .top)
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

            // 状态词改为中文：这是面板上唯一说明"当前发生了什么"的标签，
            // 不应该要求用户翻译 LOCKED / IN VIEW 的区别。
            ZStack(alignment: .leading) {
                Text(captured ? "已锁定" : "视野中")
                    .opacity(isReleasing ? 0 : 1)
                Text("正在归还")
                    .opacity(isReleasing ? 1 : 0)
            }
            .font(Typography.statusTag)
            .tracking(1.15)
            .foregroundStyle(
                (captured ? Palette.signal : Palette.inkMid)
                    .opacity(Palette.Level.present)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .layoutPriority(1)

            Spacer(minLength: 4)
        }
        .frame(height: 16)
        .opacity(0.22 + 0.78 * clampedLockProgress)
    }

    private var readoutDivider: some View {
        HStack(spacing: 7) {
            Text("实时遥测")
                .font(Typography.statusTag)
                .tracking(1.0)
                .foregroundStyle(Palette.inkLow.opacity(0.58))
            Rectangle()
                .fill(Palette.inkFaint.opacity(0.34))
                .frame(height: 0.5)
        }
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
