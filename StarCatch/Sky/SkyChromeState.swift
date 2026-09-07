import Foundation

/// 天空控制层的纯值快照。
///
/// 它只解释现有捕获、时间和场景状态，不拥有任何业务事实；视图可以据此决定当前
/// 唯一需要出现的控制，而不再在多个 `if` 分支中各自猜测动作优先级。
struct SkyChromeState: Equatable {
    enum Scene: Equatable {
        case local
        case global
        case transitioning
    }

    enum DockMode: Equatable {
        case exploration
        case sensing
        case capture(PrimaryAction)
        case targetSummary
        case hidden
    }

    enum PrimaryAction: Equatable {
        case confirm(progress: Double)
        case replace(progress: Double)
        case release
        case releasing
    }

    enum ResetAction: Equatable {
        case localField
    }

    let scene: Scene
    let dockMode: DockMode
    let resetAction: ResetAction?

    init(
        presentationMode: SkyPresentationMode,
        capturePhase: CaptureStateMachine.Phase,
        captureConfirmationEnabled: Bool,
        recognitionReady: Bool,
        replacementObjectID: String?,
        acquisitionProgress: Double,
        replacementProgress: Double,
        targetSummaryVisible: Bool,
        localFieldResetAvailable: Bool
    ) {
        switch presentationMode {
        case .enteringGlobal, .exitingGlobal:
            scene = .transitioning
            dockMode = .hidden
            resetAction = nil

        case .global:
            scene = .global
            dockMode = .hidden
            resetAction = nil

        case .local:
            scene = .local
            let resolvedDock = Self.resolveLocalDock(
                capturePhase: capturePhase,
                captureConfirmationEnabled: captureConfirmationEnabled,
                recognitionReady: recognitionReady,
                replacementObjectID: replacementObjectID,
                acquisitionProgress: acquisitionProgress,
                replacementProgress: replacementProgress,
                targetSummaryVisible: targetSummaryVisible
            )
            dockMode = resolvedDock
            resetAction = resolvedDock == .exploration && localFieldResetAvailable
                ? .localField
                : nil
        }
    }

    private static func resolveLocalDock(
        capturePhase: CaptureStateMachine.Phase,
        captureConfirmationEnabled: Bool,
        recognitionReady: Bool,
        replacementObjectID: String?,
        acquisitionProgress: Double,
        replacementProgress: Double,
        targetSummaryVisible: Bool
    ) -> DockMode {
        switch capturePhase {
        case .exploring:
            return .exploration

        case .acquiring:
            if recognitionReady {
                return targetSummaryVisible ? .targetSummary : .capture(.release)
            }
            guard captureConfirmationEnabled else { return .sensing }
            return .capture(.confirm(progress: clamped(acquisitionProgress)))

        case .locked:
            if targetSummaryVisible { return .targetSummary }
            if replacementObjectID != nil {
                return .capture(.replace(progress: clamped(replacementProgress)))
            }
            return .capture(.release)

        case .releasing:
            return targetSummaryVisible ? .targetSummary : .capture(.releasing)
        }
    }

    private static func clamped(_ progress: Double) -> Double {
        min(1, max(0, progress))
    }
}

/// 一次只允许一个短时浮层占据天空；所有临时界面都由同一个可空枚举表达。
enum SkyTransientOverlay: String, Identifiable, Equatable {
    case observationStatus
    case direction

    var id: String { rawValue }

    nonisolated static func toggled(
        from current: SkyTransientOverlay?,
        requested: SkyTransientOverlay
    ) -> SkyTransientOverlay? {
        current == requested ? nil : requested
    }
}
