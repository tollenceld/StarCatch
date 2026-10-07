import Combine
import CoreGraphics
import Foundation
import QuartzCore

/// 手动浏览指向源，真机与模拟器共用；种子保留显示姿态及屏幕 roll。
final class ManualPointingProvider: PointingProvider {
    @Published private(set) var pointing: Pointing = .initial
    let confidence: HeadingConfidence = .manual

    /// 每 pt 拖拽对应的弧度（约 0.15°/pt，全屏拖约 60°）。
    private let radiansPerPoint = 0.15 * Double.pi / 180

    private var velocity = CGVector.zero
    private var decayTimer: Timer?

    func start() {}
    func stop() {
        decayTimer?.invalidate()
        decayTimer = nil
        velocity = .zero
    }

    /// A reset also cancels momentum so the next tick cannot move away again.
    func reset(to reference: Pointing) {
        decayTimer?.invalidate()
        decayTimer = nil
        velocity = .zero
        pointing = reference
    }

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
        var previousTick = CACurrentMediaTime()
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = CACurrentMediaTime()
            let dt = SpatialMotion.resolvedDeltaTime(
                now: now,
                previous: previousTick
            )
            previousTick = now
            let elevationVelocity = Double(self.velocity.dy) * self.radiansPerPoint
            let boundaryScale = SpatialMotion.boundaryVelocityScale(
                value: self.pointing.elevation,
                velocity: elevationVelocity,
                lowerBound: -.pi / 2 + 0.0001,
                upperBound: .pi / 2,
                slowZone: 0.22
            )
            self.velocity.dy *= boundaryScale
            self.apply(dx: self.velocity.dx * dt, dy: self.velocity.dy * dt)
            let decay = SpatialMotion.decayFactor(
                rate: SpatialMotion.rotationDecay,
                deltaTime: dt
            )
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
        let horizontal = Double(dx) * cos(p.roll) - Double(dy) * sin(p.roll)
        let vertical = Double(dy) * cos(p.roll) + Double(dx) * sin(p.roll)
        p.azimuth -= horizontal * radiansPerPoint
        p.elevation += vertical * radiansPerPoint
        p.elevation = max(-.pi / 2 + 0.0001, min(.pi / 2, p.elevation))
        // 方位角回绕
        p.azimuth = (p.azimuth + .pi).truncatingRemainder(dividingBy: 2 * .pi)
        if p.azimuth < 0 { p.azimuth += 2 * .pi }
        p.azimuth -= .pi
        pointing = p
    }
}
