import Foundation
import QuartzCore

/// 观测时钟 —— 仪器读取的时间坐标。
///
/// 手机指向决定"看哪里"，观测时钟决定"看何时"。
/// `offset == 0` 时仪器与现实时间同步（LIVE）；拨动时间标尺改变 offset，
/// 整片天空按对应时刻推算。所有行为都是"仪器时钟"的物理行为：
/// 拖动直接写入，松手带惯性衰减，"回到此刻"按距离在线性时限内完成。
@MainActor
final class SkyClock: ObservableObject {

    /// 观测时刻相对现实的偏移（秒）。0 = LIVE。
    @Published private(set) var offset: TimeInterval = 0

    /// 时间轴拖动驱动的全局星图强调进度。0 = 静止读数，1 = 正在直接操纵时间。
    /// 它与 offset 解耦：松手后仍可停留在过去/未来，全局星图继续保留当前时刻。
    @Published private(set) var scrubPresentationProgress: Double = 0

    /// “返回此刻”的连续回归状态。视图用它增强轨迹与按钮反馈，不自行推断 offset。
    @Published private(set) var isReturningToLive = false

    /// 是否与现实同步。判断用小容差 —— 结束回归后严格归零。
    var isLive: Bool { offset == 0 }

    var isScrubbing: Bool { scrubPresentationProgress > 0.001 }

    /// 偏移上限：前后 24 小时。
    /// LEO 的 TLE 在 ±1 天内漂移可忽略；GEO 数月稳定。再远，仪器不假装可信。
    static let maxOffset: TimeInterval = 24 * 3600

    /// 当前观测时刻。
    func observationTime(realNow: Date = Date()) -> Date {
        realNow.addingTimeInterval(offset)
    }

    // MARK: - 拨动

    /// 惯性速度（秒/秒）。
    private var velocity: Double = 0
    private var displayLink: CADisplayLink?
    private var returnStartOffset: TimeInterval = 0
    private var returnElapsed: TimeInterval = 0
    private var activeReturnDuration: TimeInterval = 0

    /// 无论从 ±24h 的哪个位置回归，都不会超过这个时间。
    static let maximumReturnDuration: TimeInterval = 2.4

    /// 回归用时随偏移距离线性增长：近距离不拖沓，最远距离仍在 2.4 秒内完成。
    static func returnDuration(forOffset offset: TimeInterval) -> TimeInterval {
        let normalized = min(1, abs(offset) / maxOffset)
        return 0.38 + normalized * (maximumReturnDuration - 0.38)
    }

    /// 纯线性时间插值，便于测试回归节奏，不把曲线语义藏在显示链路里。
    static func returningOffset(startOffset: TimeInterval, progress: Double) -> TimeInterval {
        let p = min(1, max(0, progress))
        return startOffset * (1 - p)
    }

    /// 拖动中：直接累加偏移（由 TimeDial 换算好秒数传入）。
    func scrub(by deltaSeconds: TimeInterval) {
        cancelMomentum()
        isReturningToLive = false
        offset = clamp(offset + deltaSeconds)
    }

    /// 将真实拖动距离映射为连续镜头进度；约 72pt 完成全览切换，起步无阈值。
    /// 更长的行程让主视野退后与天空球接管的关系能被眼睛读到。
    func updateScrubPresentation(translationPoints: Double) {
        scrubPresentationProgress = min(1, max(0, abs(translationPoints) / 72))
    }

    /// 松手或返回此刻时，撤去时间操纵强调。动画事务由视图层提供。
    func endScrubPresentation() {
        scrubPresentationProgress = 0
    }

    /// 拖动结束：以标尺速度进入惯性。
    func endScrub(velocitySecondsPerSecond v: Double) {
        guard abs(v) > 40 else { return } // 太慢不值得惯性
        velocity = v
        isReturningToLive = false
        startTicking()
    }

    /// 回到此刻：按初始距离确定固定时长，并以恒定时间速度归零。
    func returnToLive() {
        endScrubPresentation()
        velocity = 0
        guard !isLive else {
            isReturningToLive = false
            stopTicking()
            return
        }
        returnStartOffset = offset
        returnElapsed = 0
        activeReturnDuration = Self.returnDuration(forOffset: offset)
        isReturningToLive = true
        startTicking()
    }

    /// 立即静止在当前观测时刻（拨动开始前调用）。
    func cancelMomentum() {
        velocity = 0
        if !isReturningToLive {
            stopTicking()
        }
    }

    /// Scene 离开前台时显式释放 CADisplayLink；观测偏移本身仍保留。
    func suspend() {
        stopTicking()
    }

    /// 回到前台后只恢复尚未完成的惯性或 LIVE 回归，不额外制造常驻刷新。
    func resume() {
        if isReturningToLive || velocity != 0 {
            startTicking()
        }
    }

    // MARK: - 时基

    private func startTicking() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = link.targetTimestamp - link.timestamp

        if isReturningToLive {
            returnElapsed += dt
            let progress = activeReturnDuration > 0
                ? min(1, returnElapsed / activeReturnDuration)
                : 1
            offset = Self.returningOffset(
                startOffset: returnStartOffset,
                progress: progress
            )
            if progress >= 1 {
                offset = 0
                isReturningToLive = false
                stopTicking()
            }
            return
        }

        if velocity != 0 {
            offset = clamp(offset + velocity * dt)
            // 惯性衰减 τ=0.6s
            velocity *= exp(-dt / 0.6)
            if abs(velocity) < 20 {
                velocity = 0
                stopTicking()
            }
            // 撞到边界即停
            if offset == -Self.maxOffset || offset == Self.maxOffset {
                velocity = 0
                stopTicking()
            }
        } else if !isReturningToLive {
            stopTicking()
        }
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        min(Self.maxOffset, max(-Self.maxOffset, value))
    }

    // MARK: - 显示格式

    /// 偏移的仪器读法："T+02:14:36" / "T−00:41:09"；LIVE 时为空。
    var offsetLabel: String {
        guard !isLive else { return "" }
        let sign = offset >= 0 ? "+" : "−"
        let total = Int(abs(offset).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "T%@%02d:%02d:%02d", sign, h, m, s)
    }

    /// 面向时间轴的自然读法，明确方向与单位，不要求用户理解 T+/T− 记号。
    var relativeOffsetLabel: String {
        guard !isLive else { return "\(L10n.text("time.live")) · LIVE" }
        let direction = offset >= 0
            ? L10n.text("time.relative.future")
            : L10n.text("time.relative.past")
        let total = Int(abs(offset).rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if days > 0 {
            return hours > 0
                ? L10n.format("time.relative.day_hour", direction, days, hours)
                : L10n.format("time.relative.day", direction, days)
        }
        if hours > 0 {
            return minutes > 0
                ? L10n.format("time.relative.hour_minute", direction, hours, minutes)
                : L10n.format("time.relative.hour", direction, hours)
        }
        if minutes > 0 {
            return L10n.format("time.relative.minute", direction, minutes)
        }
        return L10n.format("time.relative.second", direction, max(1, seconds))
    }

    /// 观测时刻的 UTC 读数："07-10 14:23:05Z"。
    func utcLabel(realNow: Date = Date()) -> String {
        Self.utcFormatter.string(from: observationTime(realNow: realNow))
    }

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
