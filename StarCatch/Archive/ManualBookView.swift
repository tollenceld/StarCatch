import SwiftUI

/// FIELD MANUAL —— 观测手册。分页翻阅，不是滚动列表。
///
/// 每一页是一节独立的仪器说明：文字快速渐现，用户可随时继续或跳过。
/// 底部一列极细的刻度暗示页码。
/// 最后一页收束成"开始观测"，整套结束后再进入天空。
///
/// 交付语气：像一份深空探测器的任务档案，不像 App onboarding。
struct ManualBookView: View {
    @ObservedObject var session: SkySession
    var revisiting = false
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    @State private var pageIndex = 0
    @State private var pageRevealed = false
    @State private var fadingOut = false

    private let pages: [ManualPage] = ManualPage.all
    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }

    // MARK: - body

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            // 极暗的天空底层：让手册漂浮在深空之上
            starfield

            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.horizontal, 40)
                    .padding(.top, 68)
                    .padding(.bottom, 22)

                ScrollView(showsIndicators: false) {
                    pageBody
                        .padding(.horizontal, 40)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(pageIndex) // 换页时视图重建 → transition 生效
                }

                footer
                    .padding(.horizontal, 40)
                    .padding(.bottom, 52)
            }
        }
        .opacity(fadingOut ? 0 : 1)
        .task { await initialSetup() }
    }

    private func initialSetup() async {
        #if DEBUG
        // 调试：--manualPage <n>（1-based）跳到指定页
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--manualPage"),
           idx + 1 < args.count,
           let n = Int(args[idx + 1]),
           (1 ... pages.count).contains(n) {
            pageIndex = n - 1
        }
        #endif
        await revealCurrent()
    }

    // MARK: - 组件

    /// 手册铭牌：全流程恒定。轻描淡写的三行——名称、副题、REV 号。
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("FIELD MANUAL")
                    .font(Typography.fieldLabel)
                    .tracking(Typography.fieldLabelTracking + 1.4)
                    .foregroundStyle(Palette.signal.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Rectangle()
                    .fill(Palette.inkFaint.opacity(0.5))
                    .frame(height: 0.5)
                Text(String(format: "%02d / %02d", pageIndex + 1, pages.count))
                    .font(Typography.fieldLabel)
                    .tracking(Typography.fieldLabelTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
                Button {
                    finish(interrupted: true)
                } label: {
                    Text(revisiting ? "返回设置" : "跳过")
                        .font(Typography.statusTag)
                        .tracking(Typography.statusTagTracking)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revisiting ? "返回设置" : "跳过观测手册")
            }
            Text("STARCATCH · 观测手册")
                .font(Typography.guide)
                .tracking(Typography.guideTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.faint))
        }
    }

    /// 页面正文。每次换页整块重生：由 revealed 驱动逐行浮现。
    @ViewBuilder
    private var pageBody: some View {
        let page = pages[pageIndex]

        VStack(alignment: .leading, spacing: 20) {
            // 页码/章节标记（一行小字，独立浮现）
            Text(page.chapterMark)
                .font(Typography.fieldLabel)
                .tracking(Typography.fieldLabelTracking + 0.6)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                .modifier(LineReveal(index: 0, revealed: pageRevealed))

            // 标题：中英各一行
            VStack(alignment: .leading, spacing: 6) {
                Text(page.titleEN)
                    .font(Typography.objectName)
                    .tracking(Typography.objectNameTracking + 0.5)
                    .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                Text(page.titleCN)
                    .font(Typography.guide)
                    .tracking(Typography.guideTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
            }
            .modifier(LineReveal(index: 1, revealed: pageRevealed))

            // 一条极细的分节线（signal 色微弱）
            Rectangle()
                .fill(Palette.signal.opacity(0.35))
                .frame(width: 56, height: 0.5)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .modifier(LineReveal(index: 2, revealed: pageRevealed))

            // 正文分段：每段一行渐显
            ForEach(Array(page.paragraphs.enumerated()), id: \.offset) { idx, para in
                paragraph(para)
                    .modifier(LineReveal(index: 3 + idx, revealed: pageRevealed))
            }

            // 页脚数据字段（可选）：字段值来自 session，真实数据
            if !page.fields.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(page.fields.enumerated()), id: \.offset) { idx, field in
                        fieldRow(field.label, resolve(field.value))
                            .modifier(LineReveal(index: 3 + page.paragraphs.count + idx, revealed: pageRevealed))
                    }
                }
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: 340, alignment: .leading)
    }

    /// 页脚：左侧推进标识 + 右侧极细刻度页码。
    private var footer: some View {
        HStack(alignment: .center) {
            advanceHint
            Spacer()
            pageTicks
        }
    }

    /// 底部页码刻度：填充过的刻度 signal 微光，未到达的刻度是 inkFaint。
    private var pageTicks: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< pages.count, id: \.self) { i in
                Rectangle()
                    .fill(
                        i <= pageIndex
                            ? Palette.signal.opacity(0.55)
                            : Palette.inkFaint.opacity(Palette.Level.faint)
                    )
                    .frame(width: 10, height: 0.5)
                    .animation(.easeOut(duration: suppressMotion ? 0.16 : 0.48), value: pageIndex)
            }
        }
    }

    /// 推进标识：最后一页文字是"开始观测"，其他页是"继续"。
    private var advanceHint: some View {
        let isLast = pageIndex == pages.count - 1
        return Button(action: advance) {
            HStack(spacing: 12) {
                Text(isLast ? (revisiting ? "返回设置" : "开始观测") : "继续")
                    .font(Typography.guide)
                    .tracking(Typography.guideTracking + 0.4)
                    .foregroundStyle(
                        isLast
                            ? Palette.signal.opacity(0.82)
                            : Palette.inkMid.opacity(Palette.Level.present)
                    )
                Rectangle()
                    .fill(
                        (isLast ? Palette.signal : Palette.inkLow)
                            .opacity(isLast ? 0.72 : Palette.Level.present)
                    )
                    .frame(width: 28, height: 0.75)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isLast ? (revisiting ? "返回设置" : "开始观测") : "继续到下一页"
        )
        .opacity(pageRevealed ? 1 : 0.72)
        .animation(.easeOut(duration: suppressMotion ? 0.12 : 0.28), value: pageRevealed)
    }

    // MARK: - 换页时序

    private func advance() {
        guard !fadingOut else { return }
        if pageIndex >= pages.count - 1 {
            finish()
            return
        }
        withAnimation(.easeIn(duration: suppressMotion ? 0.08 : 0.16)) {
            pageRevealed = false
            pageIndex += 1
        }
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, !fadingOut else { return }
            pageRevealed = true
        }
    }

    private func revealCurrent() async {
        pageRevealed = false
        // 只留一帧换页呼吸，不制造空白等待。
        do {
            try await Task.sleep(for: .seconds(suppressMotion ? 0 : 0.04))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        pageRevealed = true
    }

    private func finish(interrupted: Bool = false) {
        guard !fadingOut else { return }
        let duration = suppressMotion ? 0.14 : (interrupted ? 0.24 : 0.46)
        withAnimation(.easeIn(duration: duration)) { fadingOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onFinished() }
    }

    // MARK: - 组件

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(Typography.poetic)
            .tracking(Typography.poeticTracking)
            .lineSpacing(Typography.poeticLineSpacing)
            .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fieldRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Typography.fieldLabel)
                .tracking(Typography.fieldLabelTracking)
                .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(Typography.dataValue)
                .tracking(Typography.dataValueTracking)
                .foregroundStyle(Palette.inkMid.opacity(Palette.Level.full))
        }
    }

    /// 手册底部一块极缓漂移的星尘 —— 让页面漂浮在深空之上，而非白板之上。
    private var starfield: some View {
        StaticDustBackdrop()
            .ignoresSafeArea()
            .opacity(0.35)
    }

    // MARK: - 字段值解析

    private func resolve(_ value: ManualPage.FieldValue) -> String {
        switch value {
        case .literal(let s): return s
        case .catalogCount: return "\(session.catalog.objects.count) OBJECTS"
        case .epochAge: return "\(session.tleAgeDays)D"
        case .snapshotDate:
            if session.catalog.snapshotEpoch == .distantPast { return "—" }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            return f.string(from: session.catalog.snapshotEpoch)
        }
    }
}

// MARK: - 手册页面模型

/// 一页手册的静态内容。
struct ManualPage: Equatable {
    enum FieldValue: Equatable {
        case literal(String)
        case catalogCount
        case epochAge
        case snapshotDate
    }

    struct Field: Equatable {
        let label: String
        let value: FieldValue
    }

    let chapterMark: String  // 例如 "CHAPTER 01"
    let titleEN: String      // 例如 "THE INSTRUMENT"
    let titleCN: String      // 例如 "这台仪器"
    let paragraphs: [String]
    let fields: [Field]

    static let all: [ManualPage] = [
        ManualPage(
            chapterMark: "CHAPTER 01",
            titleEN: "THE INSTRUMENT",
            titleCN: "这台仪器",
            paragraphs: [
                "此刻，空间站、望远镜、导航星座与旧火箭正在越过你头顶。",
                "它们不发光，肉眼不可见。这台仪器把它们放回你的感知范围。",
            ],
            fields: []
        ),
        ManualPage(
            chapterMark: "CHAPTER 02",
            titleEN: "HOW TO OBSERVE",
            titleCN: "如何观察",
            paragraphs: [
                "举起设备，屏幕即视野，中心十字丝即指向。",
                "缓慢移动。视野中的光点是真实在轨物；空域之外的目标会由屏幕边缘提示方向。",
                "让十字丝靠近它，档案会随视线浮现，移开后自行消失。若在设置中开启“确认捕获”，主视野才会出现确认、切换与取消捕获按钮。",
                "完整信息出现后，画面下方会浮现“深入档案”。单体卫星读取自己的资料；大型星座的任意节点进入同一份项目档案，避免用重复文字伪装成不同故事。",
            ],
            fields: []
        ),
        ManualPage(
            chapterMark: "CHAPTER 03",
            titleEN: "TIME COORDINATE",
            titleCN: "时间坐标",
            paragraphs: [
                "点按左上角进入全局星图，屏幕下缘才会出现观测时钟。左右拨动刻度，即可抵达过去或未来。",
                "点按“返回此刻”即可回到 LIVE；退出全局星图时，时间也会先归还到此刻。",
            ],
            fields: []
        ),
        ManualPage(
            chapterMark: "CHAPTER 04",
            titleEN: "DATA & FRAME",
            titleCN: "数据与坐标",
            paragraphs: [
                "轨道来自 NORAD 两行根数，并由 SGP4 在设备上推算；数据龄期会被如实标注。",
                "位置与姿态只用于建立观察者坐标和设备指向，不离开设备。拒绝定位后，仪器会明确使用假定坐标。",
            ],
            fields: [
                Field(label: "MODEL", value: .literal("SGP4 / WGS-72")),
                Field(label: "SOURCE", value: .literal("CELESTRAK · NORAD GP")),
                Field(label: "EPOCH AGE", value: .epochAge),
            ]
        ),
        ManualPage(
            chapterMark: "FINAL",
            titleEN: "READY FOR OBSERVATION",
            titleCN: "观测就绪",
            paragraphs: [
                "右上角的设置入口可以重新打开手册、显示控制与隐私说明。",
                "天空一直在那里。它只负责在你抬头的时候，替你看见。",
            ],
            fields: []
        ),
    ]
}

// MARK: - 行浮现

private struct LineReveal: ViewModifier {
    let index: Int
    let revealed: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: suppressMotion || revealed ? 0 : Motion.archiveRise + 2)
            .animation(
                suppressMotion
                    ? .easeOut(duration: 0.16)
                    : Motion.manualReveal.delay(Double(index) * Motion.manualRevealStagger),
                value: revealed
            )
    }
}

// MARK: - 静态星尘背景

/// 手册与仪器面板共用的静态星尘背景。
/// 不做视差、不做漂移，只是一层极暗的介质，让"文档"漂浮在深空之上。
struct StaticDustBackdrop: View {
    private static let dust = StarDust(count: 140, seed: 0x0B_5CA7)

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Palette.voidBlack)
            )
            SkyRenderer.drawDust(context, dust: Self.dust, time: 0, size: size, parallax: .zero)
            SkyRenderer.drawVignette(context, size: size)
        }
    }
}
