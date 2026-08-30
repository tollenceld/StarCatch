import SwiftUI

/// Unified first-launch and returning-user boot film. It owns only presentation
/// time and one-shot completion; the real preparation work stays in `RootView`.
struct OrbitalBootView: View {
    let preparation: BootPreparationState
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    @State private var startedAt = Date()
    @State private var completed = false

    private var suppressMotion: Bool { systemReducedMotion || reducedMotion }
    private var isReady: Bool { preparation.isReady }

    var body: some View {
        Group {
            #if DEBUG
            if let previewElapsed {
                BootOrbitalFieldView(
                    timeline: BootOrbitalTimeline(
                        elapsed: previewElapsed,
                        reducedMotion: suppressMotion
                    )
                )
            } else {
                runtimeFilm
            }
            #else
            runtimeFilm
            #endif
        }
        .ignoresSafeArea()
        .task(id: isReady) { await finishWhenReady() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("boot.accessibility.preparing"))
    }

    @ViewBuilder
    private var runtimeFilm: some View {
        if suppressMotion {
            BootOrbitalFieldView(
                timeline: BootOrbitalTimeline(
                    elapsed: BootOrbitalTimeline.minimumPresentationDuration,
                    reducedMotion: true
                )
            )
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { frame in
                BootOrbitalFieldView(
                    timeline: BootOrbitalTimeline(
                        elapsed: frame.date.timeIntervalSince(startedAt)
                    )
                )
            }
        }
    }

    private func finishWhenReady() async {
        guard !completed,
              let remaining = BootCompletionPolicy.remainingDelay(
                  elapsed: Date().timeIntervalSince(startedAt),
                  isReady: isReady,
                  reducedMotion: suppressMotion
              )
        else { return }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--holdStartup") { return }
        if arguments.contains("--previewBootHandoff") {
            try? await Task.sleep(for: .milliseconds(1_100))
        }
        #endif

        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        guard !Task.isCancelled, !completed else { return }
        completed = true
        onFinished()
    }

    #if DEBUG
    private var previewElapsed: TimeInterval? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--previewBootTime"),
              index + 1 < arguments.count,
              let value = TimeInterval(arguments[index + 1])
        else { return nil }
        return max(0, value)
    }
    #endif
}
