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
    @State private var pendingInterrupted: Bool?
    /// 自检层进度。与文字显影共享同一时间轴，但由较慢的缓动推进。
    @State private var fieldProgress: Double = 0
    @State private var titleVisible = false
    @State private var bodyVisible = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var fadeOutDuration: TimeInterval { suppressMotion ? 0.08 : 0.18 }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            BootFieldView(progress: fieldProgress, suppressMotion: suppressMotion)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("ORBITAL FIELD INSTRUMENT")
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

                Text("一台面向真实天空的轨道观测仪。")
                    .font(.custom("PingFangSC-Light", size: 15, relativeTo: .body))
                    .tracking(0.72)
                    .foregroundStyle(Palette.inkMid.opacity(0.82))
                    .opacity(bodyVisible ? 1 : 0)
                    .offset(y: suppressMotion || bodyVisible ? 0 : 2)

                Text("举起手机，辨认此刻经过你上空的人造天体，沿时间查看它们的轨迹。")
                    .font(.custom("PingFangSC-Light", size: 13, relativeTo: .body))
                    .tracking(0.58)
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
                        Text(pendingInterrupted == nil ? "进入观测" : "正在进入")
                            .font(.custom("PingFangSC-Medium", size: 13, relativeTo: .body))
                            .tracking(1.2)
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
                .disabled(pendingInterrupted != nil)
                .opacity(actionVisible ? 1 : 0)
                .offset(y: suppressMotion || actionVisible ? 0 : 3)
                .padding(.top, 28)
                .accessibilityLabel("进入观测")
                .accessibilityHint(isReady ? "进入主天空" : "数据准备完成后进入主天空")
            }
            .frame(maxWidth: 330, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 42)
            .opacity(contentVisible ? 1 : 0)
            .offset(y: suppressMotion || contentVisible ? 0 : 4)

            Text(isReady ? "LOCAL ORBIT CATALOG · READY" : "LOCAL ORBIT CATALOG · PREPARING")
                .font(Typography.statusTag)
                .tracking(1.05)
                .foregroundStyle(Palette.inkLow.opacity(0.38))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 42)
                .padding(.bottom, 30)
                .opacity(contentVisible ? 1 : 0)
        }
        .opacity(fadingOut ? 0 : 1)
        .task { await run() }
        .onChange(of: isReady) { _, ready in
            guard ready, let interrupted = pendingInterrupted else { return }
            pendingInterrupted = nil
            finish(interrupted: interrupted)
        }
    }

    /// 显影顺序表达一次仪器自检：星野先在真空中积累，署名随之确认，说明文字最后
    /// 落位，进入动作在自检收束时才可用。任何一步都可以被点击跳过。
    private func run() async {
        if suppressMotion {
            fieldProgress = 1
            contentVisible = true
            titleVisible = true
            bodyVisible = true
            actionVisible = true
            return
        }

        contentVisible = true
        // 自检层用一条长缓动独立推进，比文字慢，让星野始终领先于文案。
        withAnimation(.timingCurve(0.22, 0.6, 0.2, 1, duration: 2.1)) {
            fieldProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.manualReveal) { titleVisible = true }

        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.manualReveal) { bodyVisible = true }

        try? await Task.sleep(for: .milliseconds(480))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.manualReveal) { actionVisible = true }
    }

    private func finish(interrupted: Bool = false) {
        guard !fadingOut else { return }
        guard isReady else {
            // 记住用户意图，但绝不淡成一张无法交互的黑屏；目录完成后立即兑现。
            pendingInterrupted = interrupted
            return
        }
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
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    @State private var fieldProgress: Double = 0
    @State private var textVisible = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }

    var body: some View {
        ZStack {
            Palette.voidBlack.ignoresSafeArea()

            BootFieldView(progress: fieldProgress, suppressMotion: suppressMotion)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                Text("STARCATCH")
                    .font(Typography.objectName)
                    .tracking(4.2)
                    .foregroundStyle(Palette.inkHigh.opacity(0.82))
                Text("LOCAL ORBIT CATALOG · PREPARING")
                    .font(Typography.statusTag)
                    .tracking(1.15)
                    .foregroundStyle(Palette.inkLow.opacity(0.42))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 42)
            .opacity(textVisible ? 1 : 0)
        }
        .task {
            if suppressMotion {
                fieldProgress = 1
                textVisible = true
                return
            }
            // 回访路径通常只存在几百毫秒，因此自检推进得更快，不制造人为等待。
            withAnimation(.timingCurve(0.22, 0.6, 0.2, 1, duration: 1.2)) {
                fieldProgress = 1
            }
            withAnimation(.easeOut(duration: 0.3)) { textVisible = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在准备本地星图")
    }
}
