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
        case targetSummary
        case hidden
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
                capturePhase: capturePhase
            )
            dockMode = resolvedDock
            resetAction = resolvedDock == .exploration && localFieldResetAvailable
                ? .localField
                : nil
        }
    }

    private static func resolveLocalDock(
        capturePhase: CaptureStateMachine.Phase
    ) -> DockMode {
        switch capturePhase {
        case .exploring:
            return .exploration

        case .acquiring:
            return .sensing

        case .locked, .dismissing:
            return .targetSummary
        }
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
