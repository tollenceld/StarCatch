import SwiftUI

/// 仅首次启动出现的产品署名。它不伪装成加载进度，也不承担手册职责；
/// 回访用户使用不带介绍文案的 StartupLoadingView。
struct BootSequenceView: View {
    /// 轨道目录已在后台完成准备。未完成时仍保持可见，不把用户退回纯黑画面。
    let isReady: Bool
    /// true 表示用户主动打断；调用方可直接进入主观测界面。
    let onFinished: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    @State private var contentVisible = false
    @State private var actionVisible = false
    @State private var fadingOut = false
    @State private var handoffProgress: Double = 0
    @State private var titleVisible = false
    @State private var bodyVisible = false
    @State private var startedAt = Date()

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var fadeOutDuration: TimeInterval { suppressMotion ? 0.08 : 0.18 }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            SystemWakeView(
                isReady: isReady,
                handoffProgress: handoffProgress,
                suppressMotion: suppressMotion
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.text("boot.intro.eyebrow"))
                    .font(Typography.statusTag)
                    .tracking(1.65)
                    .foregroundStyle(Palette.signal.opacity(0.72))
                    .opacity(titleVisible ? 1 : 0)

                Text("STARCATCH")
                    .font(Typography.objectName)
                    .tracking(4.2)
                    .foregroundStyle(Palette.inkHigh.opacity(Palette.Level.full))
                    .padding(.top, 12)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: suppressMotion || titleVisible ? 0 : 3)

                // 分隔线从零宽度展开，是"仪器完成一次标定"的收束动作。
                Rectangle()
                    .fill(Palette.inkFaint.opacity(0.52))
                    .frame(width: titleVisible ? 54 : 0, height: 0.5)
                    .padding(.vertical, 20)

                Text(L10n.text("boot.intro.title"))
                    .font(.system(.body, design: .default, weight: .light))
                    .tracking(SupportedLanguage.current == .english ? 0.2 : 0.1)
                    .foregroundStyle(Palette.inkMid.opacity(0.82))
                    .opacity(bodyVisible ? 1 : 0)
                    .offset(y: suppressMotion || bodyVisible ? 0 : 2)

                Text(L10n.text("boot.intro.body"))
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .tracking(SupportedLanguage.current == .english ? 0.1 : 0.05)
                    .lineSpacing(6)
                    .foregroundStyle(Palette.inkLow.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .opacity(bodyVisible ? 1 : 0)
                    .offset(y: suppressMotion || bodyVisible ? 0 : 2)

                Button {
                    finish(interrupted: true)
                } label: {
                    HStack(spacing: 11) {
                        Text(L10n.text("boot.action.enter"))
                            .font(.system(.footnote, design: .default, weight: .medium))
                            .tracking(SupportedLanguage.current == .english ? 0.25 : 0.5)
                        Rectangle()
                            .fill(Palette.signal.opacity(0.42))
                            .frame(width: 20, height: 0.5)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Palette.inkHigh.opacity(0.9))
                    .frame(width: 156, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Palette.inkHigh.opacity(0.055))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Palette.inkFaint.opacity(0.58), lineWidth: 0.65)
                            }
                    }
                }
                .buttonStyle(.plain)
                .opacity(actionVisible ? 1 : 0)
                .offset(y: suppressMotion || actionVisible ? 0 : 3)
                .padding(.top, 28)
                .accessibilityLabel(L10n.text("boot.action.enter"))
                .accessibilityHint(
                    isReady
                        ? L10n.text("boot.action.enter.hint")
                        : L10n.text("boot.action.wait.hint")
                )
            }
            .frame(maxWidth: 330, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 42)
            .opacity(contentVisible ? 1 : 0)
            .offset(y: suppressMotion || contentVisible ? 0 : 4)

        }
        .opacity(fadingOut ? 0 : 1)
        .task(id: isReady) { await runWhenReady() }
    }

    /// 显影顺序表达一次仪器自检：星野先在真空中积累，署名随之确认，说明文字最后
    /// 落位，进入动作在自检收束时才可用。任何一步都可以被点击跳过。
    private func runWhenReady() async {
        guard isReady else { return }
        if suppressMotion {
            handoffProgress = 1
            contentVisible = true
            titleVisible = true
            bodyVisible = true
            actionVisible = true
            return
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = max(0, BootVisualTimeline.minimumPresentationDuration - elapsed)
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        guard !Task.isCancelled else { return }

        // READY 先稳定停留，再只让文字退场；星场从头到尾保持原位。
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            handoffProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.manualReveal) {
            contentVisible = true
            titleVisible = true
        }

        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.manualReveal) { bodyVisible = true }

        try? await Task.sleep(for: .milliseconds(480))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.manualReveal) { actionVisible = true }
    }

    private func finish(interrupted: Bool = false) {
        guard !fadingOut else { return }
        guard isReady else { return }
        let duration = interrupted ? (suppressMotion ? 0.08 : 0.2) : fadeOutDuration
        withAnimation(.easeIn(duration: duration)) { fadingOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            onFinished(interrupted)
        }
    }
}

/// 回访用户只看到极简品牌准备层，不重复首启文案；数据完成即进入天空。
/// 与首启共用同一自检层，因此两条入口读作同一台仪器的不同开机时长。
struct StartupLoadingView: View {
    let isReady: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    @State private var handoffProgress: Double = 0
    @State private var completed = false
    @State private var startedAt = Date()

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            SystemWakeView(
                isReady: isReady,
                handoffProgress: handoffProgress,
                suppressMotion: suppressMotion
            )
            .ignoresSafeArea()
        }
        .task(id: isReady) {
            guard isReady, !completed else { return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--holdStartup") {
                return
            }
            #endif
            if suppressMotion {
                handoffProgress = 1
                completed = true
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                onFinished()
                return
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = max(0, BootVisualTimeline.minimumPresentationDuration - elapsed)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled, !completed else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, !completed else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                handoffProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(460))
            guard !Task.isCancelled else { return }
            completed = true
            onFinished()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("boot.accessibility.preparing"))
    }
}
