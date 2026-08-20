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

    private var language: SupportedLanguage { .current }
    private var pages: [ManualPage] { ManualPage.all(language: language) }
    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }

    private func copy(_ key: String) -> String { L10n.text(key, language: language) }

    // MARK: - body

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            // 极暗的天空底层：让手册漂浮在深空之上
            starfield

            ScrollView(showsIndicators: false) {
                pageBody
                    .padding(.horizontal, 34)
                    .padding(.top, revisiting ? 18 : 64)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(pageIndex)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if revisiting {
                ArchiveTopBar(
                    backTitle: copy("navigation.settings"),
                    title: copy("navigation.manual"),
                    onBack: { finish(interrupted: true) }
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .padding(.horizontal, 34)
                .padding(.vertical, 8)
                .background(Palette.voidBlack.opacity(0.96))
                .overlay(alignment: .top) { ContentHairline() }
        }
        .appEdgeBackGesture(enabled: revisiting) {
            finish(interrupted: true)
        }
        .simultaneousGesture(pageSwipeGesture)
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

    /// 页面正文。每次换页整块重生：由 revealed 驱动逐行浮现。
    @ViewBuilder
    private var pageBody: some View {
        let page = pages[pageIndex]

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Text(page.chapterMark)
                    .font(Typography.fieldLabel)
                    .tracking(Typography.fieldLabelTracking + 0.6)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.present))
                Spacer(minLength: 8)
                Text(String(format: "%02d / %02d", pageIndex + 1, pages.count))
                    .font(Typography.statusTag)
                    .tracking(Typography.statusTagTracking)
                    .foregroundStyle(Palette.inkLow.opacity(Palette.Level.secondary))
                if !revisiting {
                    Button(copy("manual.skip")) { finish(interrupted: true) }
                        .font(Typography.statusTag)
                        .foregroundStyle(Palette.inkMid.opacity(Palette.Level.present))
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                }
            }
            .modifier(LineReveal(index: 0, revealed: pageRevealed))

            Text(page.title)
                .font(Typography.objectName)
                .tracking(language == .english ? Typography.objectNameTracking + 0.5 : 0.15)
                .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
            .modifier(LineReveal(index: 1, revealed: pageRevealed))

            ManualChapterVisual(pageIndex: pageIndex, revealed: pageRevealed)
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
        .frame(maxWidth: 360, alignment: .leading)
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
            ForEach(0 ..< pages.count, id: \.self) { index in
                Button {
                    go(to: index)
                } label: {
                    Capsule()
                        .fill(
                            index == pageIndex
                                ? Palette.signal.opacity(0.68)
                                : Palette.inkFaint.opacity(Palette.Level.secondary)
                        )
                        .frame(width: index == pageIndex ? 18 : 8, height: 2)
                        .frame(minWidth: 22, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    L10n.format("manual.page", language: language, index + 1)
                )
            }
        }
    }

    /// 推进标识：最后一页文字是"开始观测"，其他页是"继续"。
    private var advanceHint: some View {
        let isLast = pageIndex == pages.count - 1
        return Button(action: advance) {
            HStack(spacing: 12) {
                Text(
                    isLast
                        ? copy(revisiting ? "manual.finish_reading" : "manual.begin")
                        : copy("manual.continue")
                )
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
            isLast
                ? copy(revisiting ? "manual.finish_reading" : "manual.begin")
                : copy("manual.continue.hint")
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

    private func retreat() {
        guard pageIndex > 0, !fadingOut else { return }
        go(to: pageIndex - 1)
    }

    private func go(to index: Int) {
        guard pages.indices.contains(index), index != pageIndex, !fadingOut else { return }
        withAnimation(.easeIn(duration: suppressMotion ? 0.08 : 0.16)) {
            pageRevealed = false
            pageIndex = index
        }
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, !fadingOut else { return }
            pageRevealed = true
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                if revisiting, value.startLocation.x < 32 { return }
                let horizontal = value.predictedEndTranslation.width
                guard abs(horizontal) > abs(value.predictedEndTranslation.height) * 1.25,
                      abs(horizontal) > 54
                else { return }
                if horizontal < 0 { advance() } else { retreat() }
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
            .font(Typography.readingBody)
            .tracking(Typography.readingBodyTracking)
            .lineSpacing(Typography.readingBodyLineSpacing)
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
        case .catalogCount:
            return L10n.format("manual.catalog_count", language: language, session.catalog.objects.count)
        case .epochAge:
            return L10n.format("manual.epoch_age", language: language, session.tleAgeDays)
        case .snapshotDate:
            if session.catalog.snapshotEpoch == .distantPast { return "—" }
            return Self.snapshotDateFormatter.string(
                from: session.catalog.snapshotEpoch
            )
        }
    }

    private static let snapshotDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// 手册页复用主界面的细线、准星与轨道语法，承担章节示意而不是装饰插画。
private struct ManualChapterVisual: View {
    let pageIndex: Int
    let revealed: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let signal = Palette.signal.opacity(revealed ? 0.48 : 0.18)
            let line = Palette.inkFaint.opacity(Palette.Level.secondary)

            switch pageIndex {
            case 0:
                drawField(context, size: size, center: center, signal: signal, line: line)
            case 1:
                drawFocus(context, center: center, signal: signal, line: line)
            case 2:
                drawTimeline(context, size: size, center: center, signal: signal, line: line)
            case 3:
                drawLocalGlobe(context, center: center, signal: signal, line: line)
            default:
                drawReady(context, center: center, signal: signal, line: line)
            }
        }
        .frame(height: 122)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.inkFaint.opacity(0.22), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func drawField(
        _ context: GraphicsContext,
        size: CGSize,
        center: CGPoint,
        signal: Color,
        line: Color
    ) {
        for index in 0 ..< 18 {
            let seed = CGFloat(index)
            let point = CGPoint(
                x: 18 + (seed * 47).truncatingRemainder(dividingBy: max(1, size.width - 36)),
                y: 16 + (seed * 31).truncatingRemainder(dividingBy: max(1, size.height - 32))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 1.4, height: 1.4)),
                with: .color(index == 9 ? signal : line.opacity(0.72))
            )
        }
        drawCrosshair(context, center: center, color: signal)
    }

    private func drawFocus(
        _ context: GraphicsContext,
        center: CGPoint,
        signal: Color,
        line: Color
    ) {
        drawCrosshair(context, center: center, color: signal)
        for radius in [22.0, 34.0] {
            var arc = Path()
            arc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(-64),
                endAngle: .degrees(58),
                clockwise: false
            )
            context.stroke(arc, with: .color(radius < 30 ? signal : line), lineWidth: 0.7)
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
            with: .color(Palette.inkHigh.opacity(0.82))
        )
    }

    private func drawTimeline(
        _ context: GraphicsContext,
        size: CGSize,
        center: CGPoint,
        signal: Color,
        line: Color
    ) {
        var axis = Path()
        axis.move(to: CGPoint(x: 22, y: center.y))
        axis.addLine(to: CGPoint(x: size.width - 22, y: center.y))
        context.stroke(axis, with: .color(line), lineWidth: 0.6)
        for index in 0 ... 12 {
            let x = 22 + (size.width - 44) * CGFloat(index) / 12
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: center.y - (index == 6 ? 9 : 4)))
            tick.addLine(to: CGPoint(x: x, y: center.y + (index == 6 ? 9 : 4)))
            context.stroke(tick, with: .color(index == 6 ? signal : line), lineWidth: 0.65)
        }
    }

    private func drawLocalGlobe(
        _ context: GraphicsContext,
        center: CGPoint,
        signal: Color,
        line: Color
    ) {
        let globe = CGRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84)
        context.stroke(Path(ellipseIn: globe), with: .color(line), lineWidth: 0.7)
        context.stroke(
            Path(ellipseIn: globe.insetBy(dx: 25, dy: 0)),
            with: .color(line.opacity(0.72)),
            lineWidth: 0.5
        )
        var equator = Path()
        equator.addEllipse(in: globe.insetBy(dx: 0, dy: 29))
        context.stroke(equator, with: .color(line.opacity(0.72)), lineWidth: 0.5)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x + 16, y: center.y - 18, width: 4, height: 4)),
            with: .color(signal)
        )
    }

    private func drawReady(
        _ context: GraphicsContext,
        center: CGPoint,
        signal: Color,
        line: Color
    ) {
        drawCrosshair(context, center: center, color: signal)
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - 31, y: center.y - 31, width: 62, height: 62)),
            with: .color(line),
            lineWidth: 0.6
        )
    }

    private func drawCrosshair(
        _ context: GraphicsContext,
        center: CGPoint,
        color: Color
    ) {
        var path = Path()
        path.move(to: CGPoint(x: center.x - 24, y: center.y))
        path.addLine(to: CGPoint(x: center.x - 7, y: center.y))
        path.move(to: CGPoint(x: center.x + 7, y: center.y))
        path.addLine(to: CGPoint(x: center.x + 24, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - 24))
        path.addLine(to: CGPoint(x: center.x, y: center.y - 7))
        path.move(to: CGPoint(x: center.x, y: center.y + 7))
        path.addLine(to: CGPoint(x: center.x, y: center.y + 24))
        context.stroke(path, with: .color(color), lineWidth: 0.7)
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

    let chapterMark: String
    let title: String
    let paragraphs: [String]
    let fields: [Field]

    static func all(language: SupportedLanguage = .current) -> [ManualPage] {
        func text(_ key: String) -> String { L10n.text(key, language: language) }
        func page(_ number: Int, paragraphCount: Int, fields: [Field] = []) -> ManualPage {
            ManualPage(
                chapterMark: text(number == 5 ? "manual.chapter.final" : "manual.chapter.\(number)"),
                title: text("manual.\(number).title"),
                paragraphs: (1 ... paragraphCount).map { text("manual.\(number).paragraph.\($0)") },
                fields: fields
            )
        }
        return [
            page(1, paragraphCount: 2),
            page(2, paragraphCount: 4),
            page(3, paragraphCount: 2),
            page(
                4,
                paragraphCount: 3,
                fields: [
                    Field(label: text("manual.field.model"), value: .literal("SGP4 / WGS-72")),
                    Field(label: text("manual.field.source"), value: .literal("CELESTRAK · NORAD GP")),
                    Field(label: text("manual.field.epoch_age"), value: .epochAge),
                ]
            ),
            page(5, paragraphCount: 2),
        ]
    }
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
            SkyRenderer.drawDust(context, dust: Self.dust, size: size)
            SkyRenderer.drawVignette(context, size: size)
        }
    }
}
