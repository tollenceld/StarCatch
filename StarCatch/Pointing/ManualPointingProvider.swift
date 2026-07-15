import Combine
import CoreGraphics
import Foundation

/// 模拟器/无传感器指向源：拖拽驱动，带惯性衰减。
/// 水平拖 = 方位角，竖直拖 = 仰角。roll 恒为 0。
final class ManualPointingProvider: PointingProvider {
    @Published private(set) var pointing: Pointing = .initial
    let confidence: HeadingConfidence = .manual

    /// 每 pt 拖拽对应的弧度（约 0.15°/pt，全屏拖约 60°）。
    private let radiansPerPoint = 0.15 * Double.pi / 180

    private var velocity = CGVector.zero
    private var decayTimer: Timer?

    func start() {}
    func stop() { decayTimer?.invalidate() }

    #if DEBUG
    /// Deterministic simulator aim used by visual regression launch arguments.
    func focusForPreview(azimuth: Double, elevation: Double) {
        decayTimer?.invalidate()
        pointing = Pointing(azimuth: azimuth, elevation: elevation, roll: 0)
    }
    #endif

    /// 拖拽中：直接按位移增量更新指向。
    func drag(translation delta: CGSize) {
        decayTimer?.invalidate()
        apply(dx: delta.width, dy: delta.height)
    }

    /// 拖拽结束：以结束速度进入惯性衰减。
    func endDrag(velocity v: CGSize) {
        velocity = CGVector(dx: v.width, dy: v.height)
        decayTimer?.invalidate()
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let dt = 1.0 / 30.0
            self.apply(dx: self.velocity.dx * dt, dy: self.velocity.dy * dt)
            // 指数衰减，~1.2s 停下
            let decay = exp(-dt / 0.35)
            self.velocity.dx *= decay
            self.velocity.dy *= decay
            if abs(self.velocity.dx) < 2, abs(self.velocity.dy) < 2 {
                timer.invalidate()
            }
        }
    }

    private func apply(dx: CGFloat, dy: CGFloat) {
        var p = pointing
        // 拖拽方向与视野移动相反（拖动"天空"）
        p.azimuth -= Double(dx) * radiansPerPoint
        p.elevation += Double(dy) * radiansPerPoint
        p.elevation = max(-0.2, min(.pi / 2, p.elevation))
        // 方位角回绕
        if p.azimuth > .pi { p.azimuth -= 2 * .pi }
        if p.azimuth < -.pi { p.azimuth += 2 * .pi }
        pointing = p
    }
}
