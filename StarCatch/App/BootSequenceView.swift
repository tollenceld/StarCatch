import SwiftUI

/// 启动唤醒序列 —— 不是 loading，是一次仪器上电。
///
/// 逐行浮现的都是真实状态：观察者坐标、星历对象数、快照历元、指向模式。
/// 全部就绪后短暂停驻，整层缓慢淡出，天空从下面透出来。轻触可跳过。
struct BootSequenceView: View {
    @ObservedObject var session: SkySession
    let compact: Bool
    /// true 表示用户主动打断；调用方可直接进入主观测界面。
    let onFinished: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    @State private var revealedLines = 0
    @State private var fadingOut = false
    @State private var promptVisible = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var lineInterval: TimeInterval { compact ? 0.2 : 0.24 }
    private var holdAfterReady: TimeInterval { compact ? 1.8 : 2.15 }
    private var fadeOutDuration: TimeInterval {
        suppressMotion ? 0.16 : (compact ? 0.68 : 0.86)
    }

    private var totalLines: Int { 5 }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                // 铭牌
                Text("STARCATCH")
                    .font(Typography.objectName)
                    .tracking(4.0)
                    .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                    .bootReveal(index: 0, revealed: revealedLines)

                Text("人造天体观察器")
                    .font(Typography.guide)
                    .tracking(Typography.guideTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                    .padding(.bottom, 14)
                    .bootReveal(index: 0, revealed: revealedLines)

                Text("把手机举向天空。\n让看不见的轨道逐一显影。")
                    .font(.custom("PingFangSC-Light", size: 15, relativeTo: .body))
                    .tracking(1.15)
                    .lineSpacing(7)
                    .foregroundStyle(Palette.inkMid.opacity(0.76))
                    .padding(.bottom, 18)
                    .bootReveal(index: 1, revealed: revealedLines)

                progressRail
                    .padding(.bottom, 24)

                bootLine(index: 2, label: "OBSERVER", value: observerText)
                bootLine(index: 3, label: "CATALOG", value: "\(session.catalog.objects.count) OBJECTS")
                bootLine(index: 4, label: "EPOCH", value: epochText)
                bootLine(index: 5, label: "POINTING", value: pointingText, valueColor: Palette.signal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 44)
            .padding(.trailing, 24)

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Palette.signal.opacity(0.68))
                    Text("轻触任意位置 · 立即进入观测")
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                }
                .opacity(promptVisible ? 1 : 0)
                .offset(y: promptVisible ? 0 : 3)
                .animation(.easeOut(duration: 0.42), value: promptVisible)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.bottom, 34)
            }
        }
        .opacity(fadingOut ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish(interrupted: true) }
        .accessibilityAction(named: "进入观测") { finish(interrupted: true) }
        .task { await run() }
    }

    // MARK: - 内容

    private var observerText: String {
        let c = session.observer.coordinates
        let lat = String(format: "%.2f°%@", abs(c.latitude), c.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.2f°%@", abs(c.longitude), c.longitude >= 0 ? "E" : "W")
        return c.assumed ? "\(lat) \(lon) · ASSUMED" : "\(lat) \(lon)"
    }

    private var epochText: String {
        let days = session.tleAgeDays
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = session.catalog.snapshotEpoch == .distantPast
            ? "—" : formatter.string(from: session.catalog.snapshotEpoch)
        return "\(dateStr) · AGE \(days)D"
    }

    private var pointingText: String {
        switch session.confidence {
        case .trueNorth: "TRUE NORTH"
        case .uncalibrated: "UNCALIBRATED"
        case .manual: "MANUAL"
        }
    }

    private var progressRail: some View {
        let widths: [CGFloat] = [22, 12, 26, 16, 20, 14]
        return HStack(spacing: 6) {
            ForEach(widths.indices, id: \.self) { index in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Palette.inkFaint.opacity(0.24))
                        .frame(width: widths[index], height: 0.5)
                    Rectangle()
                        .fill(Palette.signal.opacity(0.52))
                        .frame(
                            width: revealedLines > index ? widths[index] : 0,
                            height: 0.75
                        )
                }
                .frame(width: widths[index], alignment: .leading)
            }
        }
        .animation(
            .timingCurve(0.25, 0.1, 0.18, 1, duration: 0.72),
            value: revealedLines
        )
    }

    @ViewBuilder
    private func bootLine(
        index: Int, label: String, value: String,
        valueColor: Color = Palette.inkMid
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Typography.fieldLabel)
                .tracking(Typography.fieldLabelTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(Typography.dataValue)
                .tracking(Typography.dataValueTracking)
                .foregroundStyle(valueColor.opacity(Palette.Level.full))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .bootReveal(index: index, revealed: revealedLines)
    }

    // MARK: - 时序

    private func run() async {
        if suppressMotion {
            revealedLines = totalLines + 1
            promptVisible = true
            guard await pause(for: 1.1) else { return }
            finish()
            return
        }

        // 每次启动都保留可读的排版节奏；回访略快，但不再整页一闪而过。
        guard await pause(for: compact ? 0.32 : 0.46) else { return }
        withAnimation(.easeOut(duration: 0.42)) { promptVisible = true }
        guard await pause(for: 0.16) else { return }
        for i in 1 ... (totalLines + 1) {
            guard !fadingOut else { return }
            withAnimation(Motion.bootReveal) { revealedLines = i }
            guard await pause(for: lineInterval) else { return }
        }
        guard await pause(for: holdAfterReady) else { return }
        finish()
    }

    /// A removed boot view must never complete a stale transition.
    private func pause(for seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func finish(interrupted: Bool = false) {
        guard !fadingOut else { return }
        let duration = interrupted ? (suppressMotion ? 0.12 : 0.28) : fadeOutDuration
        withAnimation(.easeIn(duration: duration)) { fadingOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            onFinished(interrupted)
        }
    }
}

/// 启动行浮现：与档案层同一语言（fade + 2pt 上浮）。
private struct BootLineReveal: ViewModifier {
    let index: Int
    let revealed: Int

    func body(content: Content) -> some View {
        content
            .opacity(revealed > index ? 1 : 0)
            .offset(y: revealed > index ? 0 : Motion.archiveRise)
    }
}

private extension View {
    func bootReveal(index: Int, revealed: Int) -> some View {
        modifier(BootLineReveal(index: index, revealed: revealed))
    }
}
