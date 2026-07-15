import Foundation
import QuartzCore

/// 观测时钟 —— 仪器读取的时间坐标。
///
/// 手机指向决定"看哪里"，观测时钟决定"看何时"。
/// `offset == 0` 时仪器与现实时间同步（LIVE）；拨动时间标尺改变 offset，
/// 整片天空按对应时刻推算。所有行为都是"仪器时钟"的物理行为：
/// 拖动直接写入，松手带惯性衰减，"回到此刻"是一次平滑的指数回归。
@MainActor
final class SkyClock: ObservableObject {

    /// 观测时刻相对现实的偏移（秒）。0 = LIVE。
    @Published private(set) var offset: TimeInterval = 0

    /// 时间轴拖动驱动的镜头进度。0 = 全屏天空，1 = 全局天空球。
    /// 它与 offset 解耦：松手后仍可停留在过去/未来，但镜头立即回到全屏。
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

    /// 松手或返回此刻时，恢复全屏天空。动画事务由视图层提供。
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

    /// 回到此刻：指数回归，不瞬跳。仪器的指针转回去，需要一点时间。
    func returnToLive() {
        endScrubPresentation()
        velocity = 0
        guard !isLive else {
            isReturningToLive = false
            stopTicking()
            return
        }
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
            // 指数回归：τ=0.28s，快而不跳；接近零点时截断收敛
            let alpha = 1 - exp(-dt / 0.28)
            offset += (0 - offset) * alpha
            if abs(offset) < 0.5 {
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
        guard !isLive else { return "此刻 · LIVE" }
        let direction = offset >= 0 ? "未来" : "过去"
        let total = Int(abs(offset).rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if days > 0 {
            return hours > 0
                ? "\(direction) \(days)天 \(hours)小时"
                : "\(direction) \(days)天"
        }
        if hours > 0 {
            return minutes > 0
                ? "\(direction) \(hours)小时 \(minutes)分"
                : "\(direction) \(hours)小时"
        }
        if minutes > 0 {
            return "\(direction) \(minutes)分"
        }
        return "\(direction) \(max(1, seconds))秒"
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
