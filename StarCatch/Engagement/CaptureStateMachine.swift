import Foundation
import simd

/// 捕捉状态机：准星进入窄范围后积累驻留进度，完成后自动建立稳定阅读目标。
///
/// ```
/// EXPLORING ─(θ<2.5°)→ ACQUIRING ─(驻留完成)→ LOCKED
///     ▲                                           │
///     └──────── DISMISSING (点击详情叉号) ─────────┘
/// ```
///
/// 锁定不会因准星移开或经过另一目标而自动解除。关闭后，同一目标必须先离开
/// 4° 退出范围才会重新布防；其他目标仍可在关闭完成后立即进入新的驻留。
@MainActor
final class CaptureStateMachine: ObservableObject {

    enum Phase: Equatable {
        case exploring
        case acquiring(objectId: String)
        case locked(objectId: String)
        case dismissing(objectId: String, startedAt: Date)

        var isDismissing: Bool {
            if case .dismissing = self { return true }
            return false
        }
    }

    @Published private(set) var phase: Phase = .exploring

    /// 捕捉强度 0...1（低通后），驱动点位亮度、刻度环和十字丝。
    @Published private(set) var strength: Double = 0

    /// 驻留进度 0...1。轻微晃动只会暂停或缓慢回退，不会瞬间清空。
    @Published private(set) var acquisitionProgress: Double = 0

    /// 一次性扫描动效触发时刻（进入 ACQUIRING 时设置一次）。
    @Published private(set) var scanTriggeredAt: Date?

    // 阈值（弧度）。1×、55° 纵向视场下约对应 35pt / 18pt / 57pt 屏幕半径。
    static let enterAcquiring = 2.5 * .pi / 180
    static let enterLocked = 1.25 * .pi / 180
    static let exitAcquiring = 4.0 * .pi / 180

    // 自动锁定需要一次明确、持续的对准。
    static let lockDwell: TimeInterval = 1.8
    static let acquireExitDwell: TimeInterval = 0.75

    /// 主天空按 30Hz 采样准星附近目标。
    static let samplingInterval: TimeInterval = 1.0 / 30.0

    private var exitCandidateSince: Date?
    private var lastUpdate: Date?

    /// 叉号关闭后的同目标重新布防。它不依赖倒计时，必须观察到目标真正离开退出范围。
    private var rearmObjectId: String?

    /// 面板暂停期间不把未观测时间计入驻留。
    func resumeSampling(now: Date = Date()) {
        lastUpdate = now
        exitCandidateSince = nil
    }

    /// 关闭当前稳定目标。消隐只是视觉过渡，不再暴露“取消捕获”业务动作。
    func dismissCurrentTarget(now: Date = Date()) {
        guard case .locked(let id) = phase else { return }
        phase = .dismissing(objectId: id, startedAt: now)
        rearmObjectId = id
        exitCandidateSince = nil
    }

    /// 筛选变更可以终止尚未完成的驻留，但不能关闭已经锁定的信息面板。
    func cancelAcquisition() {
        guard case .acquiring = phase else { return }
        transitionToExploring()
    }

    /// 每帧调用：传入准星最近对象，以及当前跟踪/重新布防对象自己的角距。
    func update(
        nearest rawNearest: (objectId: String, angularDistance: Double)?,
        trackedDistance: Double? = nil,
        now: Date
    ) {
        updateRearmState(trackedDistance: trackedDistance)

        let nearest: (objectId: String, angularDistance: Double)?
        if let rawNearest, rawNearest.objectId == rearmObjectId {
            nearest = nil
        } else {
            nearest = rawNearest
        }

        let dt = min(0.2, max(0, lastUpdate.map { now.timeIntervalSince($0) } ?? 1.0 / 30.0))
        lastUpdate = now

        var engagedDistance: Double?

        switch phase {
        case .exploring:
            if let nearest, nearest.angularDistance < Self.enterAcquiring {
                beginAcquiring(objectId: nearest.objectId, now: now)
                engagedDistance = nearest.angularDistance
            }

        case .acquiring(let id):
            let theta = trackedDistance
                ?? nearest.flatMap { $0.objectId == id ? $0.angularDistance : nil }
                ?? .infinity
            engagedDistance = theta

            if theta > Self.exitAcquiring {
                if let since = exitCandidateSince {
                    if now.timeIntervalSince(since) > Self.acquireExitDwell {
                        transitionToExploring()
                    }
                } else {
                    exitCandidateSince = now
                }
            } else {
                exitCandidateSince = nil
            }

            if theta <= Self.enterAcquiring {
                let quality = proximity(for: theta)
                let rate = (0.18 + 0.82 * quality) / Self.lockDwell
                acquisitionProgress = min(1, acquisitionProgress + dt * rate)
            } else if theta <= Self.exitAcquiring {
                acquisitionProgress = max(0, acquisitionProgress - dt * 0.10)
            } else {
                acquisitionProgress = max(0, acquisitionProgress - dt * 0.30)
            }

            if acquisitionProgress >= 1 {
                phase = .locked(objectId: id)
                exitCandidateSince = nil
            }

        case .locked:
            // 当前阅读对象是唯一目标；移动手机或经过另一对象都不会改写它。
            acquisitionProgress = 1
            engagedDistance = trackedDistance

        case .dismissing(_, let startedAt):
            if now.timeIntervalSince(startedAt) > Motion.interfaceCollapseDuration {
                transitionToExploring()
            }
        }

        updateStrength(distance: engagedDistance, nearest: nearest, dt: dt)
    }

    /// 当前参与绘制的对象。关闭动画结束后不再把已抑制对象留在视觉层。
    var engagedObjectId: String? {
        switch phase {
        case .exploring: nil
        case .acquiring(let id), .locked(let id), .dismissing(let id, _): id
        }
    }

    /// 采样层在探索态仍需测量刚关闭的对象，以判断它是否真正离开 4° 范围。
    var trackedObjectId: String? {
        engagedObjectId ?? rearmObjectId
    }

    var isLocked: Bool {
        if case .locked = phase { return true }
        return false
    }

    var lockedObjectId: String? {
        if case .locked(let id) = phase { return id }
        return nil
    }

    var isAcquiring: Bool {
        if case .acquiring = phase { return true }
        return false
    }

    private func beginAcquiring(objectId: String, now: Date) {
        phase = .acquiring(objectId: objectId)
        acquisitionProgress = 0
        scanTriggeredAt = now
        exitCandidateSince = nil
    }

    private func transitionToExploring() {
        phase = .exploring
        exitCandidateSince = nil
        scanTriggeredAt = nil
        acquisitionProgress = 0
    }

    private func updateRearmState(trackedDistance: Double?) {
        guard rearmObjectId != nil else { return }
        guard let trackedDistance else {
            rearmObjectId = nil
            return
        }
        if trackedDistance > Self.exitAcquiring {
            rearmObjectId = nil
        }
    }

    private func updateStrength(
        distance: Double?,
        nearest: (objectId: String, angularDistance: Double)?,
        dt: TimeInterval
    ) {
        let target: Double
        switch phase {
        case .locked:
            target = 1
        case .dismissing:
            target = 0
        case .acquiring:
            let spatial = distance.map { proximity(for: $0) } ?? 0
            target = max(spatial, acquisitionProgress * 0.86)
        case .exploring:
            target = nearest.map { proximity(for: $0.angularDistance) } ?? 0
        }
        let alpha = 1 - exp(-dt / Motion.strengthSmoothing)
        strength += (target - strength) * alpha
    }

    /// 距离质量：感应边缘为 0，进入核心锁定区后趋近 1。
    private func proximity(for angle: Double) -> Double {
        smoothstep(edge0: Self.enterAcquiring, edge1: Self.enterLocked, x: angle)
    }

    /// edge0 > edge1 的反向 smoothstep（θ 越小强度越大）。
    private func smoothstep(edge0: Double, edge1: Double, x: Double) -> Double {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
