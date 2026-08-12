import Foundation
import simd

/// 捕捉状态机：准星先建立可随视线出现/消失的感应档案；只有“确认捕获”开启时，
/// 锁定与换锁才由用户明确确认。
///
/// ```
/// EXPLORING ─(θ<2.5°)→ ACQUIRING ─(主动确认)→ LOCKED
///     ▲                    │(θ>4° 持续0.75s)              │
///     └──── RELEASING (主动释放后的消隐) ←────────────────┘
/// ```
///
/// ACQUIRING 同时使用距离迟滞与有记忆的驻留进度：轻微晃动只会暂停或缓慢回退，
/// 不会把已经建立的捕获感知瞬间清空。进度到达 1 后，默认模式一次性开放完整档案；
/// 确认模式仍只代表“可以确认”，LOCKED 只能由明确用户行为进入或退出。
@MainActor
final class CaptureStateMachine: ObservableObject {

    enum Phase: Equatable {
        case exploring
        case acquiring(objectId: String)
        case locked(objectId: String)
        case releasing(objectId: String, startedAt: Date)

        var isReleasing: Bool {
            if case .releasing = self { return true }
            return false
        }
    }

    @Published private(set) var phase: Phase = .exploring

    /// 捕捉强度 0..1（低通后），驱动点位亮度/刻度环合拢/十字丝。
    @Published private(set) var strength: Double = 0

    /// 驻留捕获进度 0..1。与单纯角距分离，专门驱动锁定外环和渐进触觉。
    @Published private(set) var acquisitionProgress: Double = 0

    /// 默认即时识别模式下，只有捕获环完整收束后才开放档案。
    /// 一旦完成便保持到本次 acquiring 结束，避免手持抖动令面板在阈值附近闪烁。
    @Published private(set) var recognitionReady = false

    /// 阅读已锁定档案时，准星可以在不销毁旧锁定的前提下感应另一目标。
    /// 新目标驻留完成后只进入待确认态，避免经过其他点位时内容闪换。
    @Published private(set) var replacementObjectId: String?
    @Published private(set) var replacementProgress: Double = 0
    @Published private(set) var replacementTriggeredAt: Date?

    /// 一次性扫描动效触发时刻（进入 ACQUIRING 时设置一次）。
    @Published private(set) var scanTriggeredAt: Date?

    /// 锁定目标是否仍在准星的迟滞范围内。只表达空间关系，不会自行解除锁定。
    @Published private(set) var lockedTargetAligned = false

    // 阈值（弧度）。1×、55° 纵向视场下约对应 35pt / 18pt / 57pt 屏幕半径。
    static let enterAcquiring = 2.5 * .pi / 180
    static let enterLocked = 1.25 * .pi / 180
    static let exitAcquiring = 4.0 * .pi / 180

    // 驻留时间
    static let lockDwell: TimeInterval = 1.05
    static let acquireExitDwell: TimeInterval = 0.75
    static let replacementDwell: TimeInterval = 1.15

    /// 主天空按 30Hz 采样准星附近目标。90°/s 的快速转动在相邻样本间约跨越 3°，
    /// 配合 4° 退出迟滞仍不会把一次普通手持扫过直接判成离开；更高频率只会让
    /// 数千目标的候选扫描与 60Hz 绘制争抢主线程。
    static let samplingInterval: TimeInterval = 1.0 / 30.0

    private var exitCandidateSince: Date?
    private var lastUpdate: Date?

    /// 手动释放后的再锁定抑制：对该对象短时间内不再进入 acquiring/locked，
    /// 否则释放动画一结束（若仍指着它）会立即重新捕捉，"释放"就失去意义。
    private var suppressedObjectId: String?
    private var suppressedUntil: Date?
    private static let resuppressWindow: TimeInterval = 6.0

    /// 已确认锁定或已完成的即时识别都可以由独立释放操作结束。
    /// 两种路径共用释放消隐与短暂再捕获抑制，避免仍指向目标时立即弹回。
    func releaseSignal(now: Date = Date()) {
        let id: String
        switch phase {
        case .locked(let objectId):
            id = objectId
        case .acquiring(let objectId) where recognitionReady:
            id = objectId
        default:
            return
        }
        phase = .releasing(objectId: id, startedAt: now)
        recognitionReady = false
        suppressedObjectId = id
        suppressedUntil = now.addingTimeInterval(Self.resuppressWindow)
        exitCandidateSince = nil
        lockedTargetAligned = false
        clearReplacement()
    }

    /// 用户在感应态点按底部确认动作，进入稳定的 LOCKED 状态。
    @discardableResult
    func confirmAcquisition(now: Date = Date()) -> Bool {
        guard case .acquiring(let id) = phase else { return false }
        acquisitionProgress = 1
        recognitionReady = false
        phase = .locked(objectId: id)
        exitCandidateSince = nil
        lockedTargetAligned = true
        clearReplacement()
        lastUpdate = now
        return true
    }

    /// 锁定阅读时确认当前替换候选。驻留只负责建立候选，不会自行替换档案。
    @discardableResult
    func confirmReplacement(now: Date = Date()) -> Bool {
        guard case .locked(let current) = phase,
              let candidate = replacementObjectId,
              candidate != current else { return false }
        return selectLockedTarget(candidate, now: now)
    }

    /// 锁定阅读时直接选择另一个明确点位。只允许从稳定锁定态切换，避免探索态误触。
    @discardableResult
    func selectLockedTarget(_ objectId: String, now: Date = Date()) -> Bool {
        guard case .locked(let current) = phase, current != objectId else { return false }
        phase = .locked(objectId: objectId)
        acquisitionProgress = 1
        scanTriggeredAt = now
        exitCandidateSince = nil
        lockedTargetAligned = true
        lastUpdate = now
        clearReplacement()
        return true
    }

    /// 筛选等明确界面行为使当前目标失效时，主动返回探索；锁定态仍走统一消隐。
    func returnToExploring(now: Date = Date()) {
        switch phase {
        case .locked:
            releaseSignal(now: now)
        case .acquiring:
            transitionToExploring()
        case .exploring, .releasing:
            break
        }
    }

    /// 该对象当前是否处于再锁定抑制期。
    private func isSuppressed(_ objectId: String, now: Date) -> Bool {
        guard objectId == suppressedObjectId, let until = suppressedUntil else { return false }
        if now > until {
            suppressedObjectId = nil
            suppressedUntil = nil
            return false
        }
        return true
    }

    /// 每帧调用：传入当前最近对象及其角距。
    /// `nearest` 为 nil 表示视野内没有任何对象。
    func update(
        nearest rawNearest: (objectId: String, angularDistance: Double)?,
        trackedDistance: Double? = nil,
        captureEnabled: Bool = true,
        now: Date
    ) {
        // 抑制期内该对象视为不存在
        let nearest: (objectId: String, angularDistance: Double)?
        if let n = rawNearest, isSuppressed(n.objectId, now: now) {
            nearest = nil
        } else {
            nearest = rawNearest
        }

        let dt = min(0.2, max(0, lastUpdate.map { now.timeIntervalSince($0) } ?? 1.0 / 30.0))
        lastUpdate = now

        var engagedDistance: Double?

        switch phase {
        case .exploring:
            if let n = nearest, n.angularDistance < Self.enterAcquiring {
                beginAcquiring(objectId: n.objectId, now: now)
                engagedDistance = n.angularDistance
            }

        case .acquiring(let id):
            // acquiring 对当前对象有短时粘性；最近对象变化不再导致锁定环闪跳。
            let theta = trackedDistance
                ?? nearest.flatMap { $0.objectId == id ? $0.angularDistance : nil }
                ?? .infinity
            engagedDistance = theta

            if theta > Self.exitAcquiring {
                if let since = exitCandidateSince {
                    let exitDwell = captureEnabled ? Self.acquireExitDwell : 0.12
                    if now.timeIntervalSince(since) > exitDwell {
                        transitionToExploring()
                    }
                } else {
                    exitCandidateSince = now
                }
            } else {
                exitCandidateSince = nil
            }

            if theta <= Self.enterAcquiring {
                // 在感应边缘也会缓慢积累；越靠近中心，收缩越快。
                let quality = proximity(for: theta)
                let rate = (0.18 + 0.82 * quality) / Self.lockDwell
                acquisitionProgress = min(1, acquisitionProgress + dt * rate)
            } else if theta <= Self.exitAcquiring {
                // 轻微越界只慢慢回退，不归零。
                acquisitionProgress = max(0, acquisitionProgress - dt * 0.10)
            } else {
                acquisitionProgress = max(0, acquisitionProgress - dt * 0.30)
            }

            if captureEnabled {
                recognitionReady = false
            } else if acquisitionProgress >= 1 {
                recognitionReady = true
            }

        case .locked(let currentID):
            // 旧档案稳定保留；另一目标只形成待确认候选，不会自动替换。
            acquisitionProgress = 1
            updateLockedAlignment(distance: trackedDistance)
            updateReplacement(
                currentObjectId: currentID,
                nearest: nearest,
                dt: dt,
                now: now
            )

        case .releasing(_, let startedAt):
            // 释放是明确用户行为；即使仍指向目标，也不反向恢复锁定。
            if now.timeIntervalSince(startedAt) > Motion.releaseDuration {
                transitionToExploring()
            }
        }

        updateStrength(distance: engagedDistance, nearest: nearest, dt: dt)
    }

    /// 当前正在交互的对象（acquiring/locked/releasing）。
    var engagedObjectId: String? {
        switch phase {
        case .exploring: nil
        case .acquiring(let id), .locked(let id): id
        case .releasing(let id, _): id
        }
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

    var isAcquiringReplacement: Bool { replacementObjectId != nil }

    private func beginAcquiring(objectId: String, now: Date) {
        phase = .acquiring(objectId: objectId)
        acquisitionProgress = 0
        recognitionReady = false
        scanTriggeredAt = now
        exitCandidateSince = nil
        lockedTargetAligned = false
    }

    private func transitionToExploring() {
        phase = .exploring
        exitCandidateSince = nil
        scanTriggeredAt = nil
        acquisitionProgress = 0
        recognitionReady = false
        lockedTargetAligned = false
        clearReplacement()
    }

    /// 进入和离开使用不同阈值，设备在边界附近轻微抖动时按钮不会反复改字。
    private func updateLockedAlignment(distance: Double?) {
        let theta = distance ?? .infinity
        if lockedTargetAligned {
            if theta > Self.exitAcquiring { lockedTargetAligned = false }
        } else if theta < Self.enterAcquiring {
            lockedTargetAligned = true
        }
    }

    private func updateReplacement(
        currentObjectId: String,
        nearest: (objectId: String, angularDistance: Double)?,
        dt: TimeInterval,
        now: Date
    ) {
        guard let nearest, nearest.objectId != currentObjectId else {
            decayReplacement(by: dt * 0.42)
            return
        }

        if replacementObjectId != nearest.objectId {
            guard nearest.angularDistance < Self.enterAcquiring else {
                decayReplacement(by: dt * 0.42)
                return
            }
            replacementObjectId = nearest.objectId
            replacementProgress = 0
            replacementTriggeredAt = now
        }

        if nearest.angularDistance <= Self.enterAcquiring {
            let quality = proximity(for: nearest.angularDistance)
            let rate = (0.16 + 0.84 * quality) / Self.replacementDwell
            replacementProgress = min(1, replacementProgress + dt * rate)
        } else if nearest.angularDistance <= Self.exitAcquiring {
            replacementProgress = max(0, replacementProgress - dt * 0.12)
        } else {
            decayReplacement(by: dt * 0.42)
        }

    }

    private func decayReplacement(by amount: Double) {
        guard replacementObjectId != nil else { return }
        replacementProgress = max(0, replacementProgress - amount)
        if replacementProgress <= 0 {
            clearReplacement()
        }
    }

    private func clearReplacement() {
        replacementObjectId = nil
        replacementProgress = 0
        replacementTriggeredAt = nil
    }

    private func updateStrength(
        distance: Double?,
        nearest: (objectId: String, angularDistance: Double)?,
        dt: TimeInterval
    ) {
        // 目标强度同时保留距离感和已经积累的捕获进度；锁定态恒 1。
        let target: Double
        switch phase {
        case .locked:
            target = 1
        case .releasing:
            target = 0
        case .acquiring:
            let spatial = distance.map { proximity(for: $0) } ?? 0
            target = max(spatial, acquisitionProgress * 0.86)
        case .exploring:
            target = nearest.map { proximity(for: $0.angularDistance) } ?? 0
        }
        // 低通
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
