import SwiftUI

/// 深空各层的绘制函数。被 SkyView 的 Canvas 调用。
enum SkyRenderer {

    // MARK: - 星尘

    static func drawDust(
        _ context: GraphicsContext,
        dust: StarDust,
        time: TimeInterval,
        size: CGSize,
        parallax: CGPoint
    ) {
        for grain in dust.grains {
            let p = dust.screenPosition(of: grain, time: time, canvasSize: size, parallax: parallax)
            // 少数颗粒极慢呼吸（周期取 3 倍标准呼吸，进一步放慢）
            let breath = 1.0 + 0.25 * sin(time / (Motion.breathPeriod * 3) * 2 * .pi + grain.phase)
            let rect = CGRect(
                x: p.x - grain.radius, y: p.y - grain.radius,
                width: grain.radius * 2, height: grain.radius * 2
            )
            // 亮度分层：多数颗粒是 dust 底噪，最亮的少数升到 inkFaint / inkLow
            let color: Color = grain.alpha > 0.85
                ? Palette.inkLow
                : (grain.alpha > 0.6 ? Palette.inkFaint : Palette.dust)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(color.opacity(grain.alpha * breath))
            )
        }
    }

    // MARK: - 十字丝

    /// 屏幕中心十字丝：精细但始终可辨，捕捉时进一步增强。
    static func drawCrosshair(
        _ context: GraphicsContext,
        center: CGPoint,
        emphasis: Double,
        presence: Double = 1
    ) {
        let visible = min(1, max(0, presence))
        guard visible > 0.01 else { return }
        let alpha = (0.38 + 0.38 * emphasis) * visible
        let gap: CGFloat = 6
        let len: CGFloat = 9
        var path = Path()
        path.move(to: CGPoint(x: center.x - gap - len, y: center.y))
        path.addLine(to: CGPoint(x: center.x - gap, y: center.y))
        path.move(to: CGPoint(x: center.x + gap, y: center.y))
        path.addLine(to: CGPoint(x: center.x + gap + len, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - gap - len))
        path.addLine(to: CGPoint(x: center.x, y: center.y - gap))
        path.move(to: CGPoint(x: center.x, y: center.y + gap))
        path.addLine(to: CGPoint(x: center.x, y: center.y + gap + len))
        context.stroke(
            path,
            with: .color(Palette.inkHigh.opacity(alpha)),
            style: StrokeStyle(lineWidth: 0.85, lineCap: .butt)
        )

        let coreRadius: CGFloat = 1.5
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - coreRadius, y: center.y - coreRadius,
                width: coreRadius * 2, height: coreRadius * 2
            )),
            with: .color(Palette.signal.opacity((0.42 + 0.28 * emphasis) * visible))
        )
    }

    // MARK: - 对象点位

    /// 点位：core + halo 双层圆。halo 用模糊层单独绘制（先 halo 后 core，避免全场糊）。
    /// `brightness` 0..1 由捕捉强度驱动；`tint` 表达轨道类别身份。
    static func drawTarget(
        _ context: GraphicsContext,
        at point: CGPoint,
        brightness: Double,
        tint: Color,
        time: TimeInterval,
        breathPhase: Double = 0
    ) {
        let breath = Motion.breath(at: time, phase: breathPhase)
        let coreAlpha = (0.42 + 0.55 * brightness) * breath
        let haloAlpha = (0.08 + 0.14 * brightness) * breath

        // halo 层（独立 layer 内加 blur）
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            let haloR: CGFloat = 8
            layer.fill(
                Path(ellipseIn: CGRect(x: point.x - haloR, y: point.y - haloR,
                                       width: haloR * 2, height: haloR * 2)),
                with: .color(tint.opacity(haloAlpha))
            )
        }

        // core 层
        let coreR: CGFloat = 1.65
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - coreR, y: point.y - coreR,
                                   width: coreR * 2, height: coreR * 2)),
            with: .color(Palette.inkHigh.opacity(coreAlpha))
        )
    }

    /// 大目录的普通点位合并为单一路径和一个光晕层；锁定/精选目标仍用上方的
    /// 完整点位绘制。这样点数增加不会线性制造数千个模糊图层。
    static func drawTargetField(
        _ context: GraphicsContext,
        points: [CGPoint],
        tint: Color,
        opacity: Double,
        coreRadius: CGFloat = 1.15,
        haloStrength: Double = 0.12
    ) {
        guard !points.isEmpty else { return }
        var cores = Path()
        var halos = Path()
        for point in points {
            cores.addEllipse(in: CGRect(
                x: point.x - coreRadius,
                y: point.y - coreRadius,
                width: coreRadius * 2,
                height: coreRadius * 2
            ))
            if haloStrength > 0 {
                halos.addEllipse(in: CGRect(x: point.x - 3.6, y: point.y - 3.6, width: 7.2, height: 7.2))
            }
        }
        if haloStrength > 0 {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.2))
                layer.fill(halos, with: .color(tint.opacity(opacity * haloStrength)))
            }
        }
        context.fill(cores, with: .color(Palette.inkHigh.opacity(opacity)))
    }

    // MARK: - 捕捉刻度环

    /// 围绕感应目标的 4 段圆弧刻度。进入感应范围时先出现较大的疏朗外环，
    /// 驻留进度增加后再向点位收缩；它表达“正在捕获”，不是武器准星。
    static func drawAcquisitionRing(
        _ context: GraphicsContext,
        at point: CGPoint,
        progress: Double,
        presence: Double,
        tint: Color = Palette.signal
    ) {
        let p = min(1, max(0, progress))
        let eased = p * p * (3 - 2 * p)
        let pCGFloat = CGFloat(eased)
        let visible = min(1, max(0, presence))
        guard visible > 0.01 else { return }
        let radius: CGFloat = 38 - 24 * pCGFloat
        let alpha = (0.20 + 0.36 * eased) * visible
        let segmentSweep = Angle.degrees(18 + 58 * eased)

        // 先让目标周围的介质逐渐聚拢，再由细刻度给出精度；比单独出现圆环更自然。
        let haloRadius = 8 + 7 * CGFloat(1 - eased)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3.4))
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - haloRadius,
                    y: point.y - haloRadius,
                    width: haloRadius * 2,
                    height: haloRadius * 2
                )),
                with: .color(tint.opacity((0.09 + 0.13 * eased) * visible))
            )
        }
        for i in 0 ..< 4 {
            let start = Angle.degrees(Double(i) * 90 + 45 - segmentSweep.degrees / 2)
            var path = Path()
            path.addArc(
                center: point, radius: radius,
                startAngle: start, endAngle: start + segmentSweep,
                clockwise: false
            )
            context.stroke(
                path,
                with: .color(tint.opacity(alpha)),
                style: StrokeStyle(lineWidth: 0.62, lineCap: .butt)
            )
        }

        // 四条极短径向刻度随进度靠近，增强“收束”而不增加亮度噪声。
        for i in 0 ..< 4 {
            let angle = Double(i) * .pi / 2
            let cosine = CGFloat(cos(angle))
            let sine = CGFloat(sin(angle))
            let inner = radius + 2
            let outer = inner + 2.5 + 1.5 * (1 - pCGFloat)
            var tick = Path()
            tick.move(to: CGPoint(
                x: point.x + cosine * inner,
                y: point.y + sine * inner
            ))
            tick.addLine(to: CGPoint(
                x: point.x + cosine * outer,
                y: point.y + sine * outer
            ))
            context.stroke(
                tick,
                with: .color(tint.opacity(alpha * 0.72)),
                style: StrokeStyle(lineWidth: 0.5, lineCap: .butt)
            )
        }
    }

    /// 稳定锁定标记与离屏信标共用同一结构。标记接近边缘时被可用视场自然裁切，
    /// 完全离屏后在同一锁定环上渐进补出方向尖角与较长引线，不硬切成另一套控件。
    static func drawLockedMarker(
        _ context: GraphicsContext,
        at point: CGPoint,
        edgeProgress: Double,
        inward: CGVector,
        clippedTo bounds: CGRect,
        tint: Color,
        time: TimeInterval,
        confirmationProgress: Double,
        releaseProgress: Double,
        showsDirectionCue: Bool,
        alpha: Double
    ) {
        let edge = min(1, max(0, edgeProgress))
        let edgeCGFloat = CGFloat(edge)
        let confirmation = min(1, max(0, confirmationProgress))
        let release = min(1, max(0, releaseProgress))
        let releaseCGFloat = CGFloat(release)
        let visibility = min(1, max(0, alpha))
        guard visibility > 0.01 else { return }
        let breath = Motion.breath(at: time, phase: 0.7)
        var clipped = context
        clipped.clip(to: Path(bounds))

        // 捕获环抵达目标后只做极小的精度校准；主动归还时四段结构向外松开。
        let radius: CGFloat = 14 - 0.5 * CGFloat(confirmation)
            - 0.8 * edgeCGFloat + 4.5 * releaseCGFloat
        let sweep = 76.0 - 9.0 * confirmation - 7.0 * edge - 22.0 * release
        let rotation = 5.0 * release
        for i in 0 ..< 4 {
            let start = Angle.degrees(Double(i) * 90 + 45 + rotation - sweep / 2)
            var arc = Path()
            arc.addArc(
                center: point,
                radius: radius,
                startAngle: start,
                endAngle: start + .degrees(sweep),
                clockwise: false
            )
            clipped.stroke(
                arc,
                with: .color(tint.opacity(
                    (0.42 + 0.08 * edge) * visibility * breath * (1 - 0.34 * release)
                )),
                style: StrokeStyle(lineWidth: 0.65, lineCap: .butt)
            )
        }

        // 一次性的确认回声：从原锁定环轻轻外扩，不形成瞄准或爆炸感。
        if confirmation > 0, confirmation < 1, release < 0.01 {
            let echoAlpha = sin(confirmation * .pi) * 0.28 * visibility
            let echoRadius = 14 + 13 * CGFloat(confirmation)
            let echoSweep = 46.0 - 12.0 * confirmation
            for i in 0 ..< 4 {
                let start = Angle.degrees(Double(i) * 90 + 45 - echoSweep / 2)
                var echo = Path()
                echo.addArc(
                    center: point,
                    radius: echoRadius,
                    startAngle: start,
                    endAngle: start + .degrees(echoSweep),
                    clockwise: false
                )
                clipped.stroke(
                    echo,
                    with: .color(tint.opacity(echoAlpha)),
                    style: StrokeStyle(lineWidth: 0.5, lineCap: .butt)
                )
            }
        }

        if edge > 0.02 {
            let start = CGPoint(
                x: point.x + inward.dx * (radius + 2),
                y: point.y + inward.dy * (radius + 2)
            )
            let calibrationLength: CGFloat = showsDirectionCue
                ? 22
                : 4 + 5 * edgeCGFloat
            let end = CGPoint(
                x: start.x + inward.dx * calibrationLength,
                y: start.y + inward.dy * calibrationLength
            )
            var calibration = Path()
            calibration.move(to: start)
            calibration.addLine(to: end)
            clipped.stroke(
                calibration,
                with: .color(Palette.signal.opacity(
                    (showsDirectionCue ? 0.68 : 0.4)
                        * edge * visibility * (1 - 0.5 * release)
                )),
                style: StrokeStyle(
                    lineWidth: showsDirectionCue ? 0.85 : 0.55,
                    lineCap: .butt
                )
            )

            if showsDirectionCue {
                // 目标已离屏：在锁定环原有结构上加一枚朝外的空心尖角。
                // 它和较长的内向引线共同表达方位，但仍保持仪器刻度的克制感。
                let perpendicular = CGVector(dx: -inward.dy, dy: inward.dx)
                let base = CGPoint(
                    x: point.x + inward.dx * 9,
                    y: point.y + inward.dy * 9
                )
                var chevron = Path()
                chevron.move(to: CGPoint(
                    x: base.x + perpendicular.dx * 4,
                    y: base.y + perpendicular.dy * 4
                ))
                chevron.addLine(to: point)
                chevron.addLine(to: CGPoint(
                    x: base.x - perpendicular.dx * 4,
                    y: base.y - perpendicular.dy * 4
                ))
                clipped.stroke(
                    chevron,
                    with: .color(tint.opacity(0.76 * visibility * (1 - 0.45 * release))),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                )

                var terminal = Path()
                terminal.move(to: CGPoint(
                    x: end.x + perpendicular.dx * 3,
                    y: end.y + perpendicular.dy * 3
                ))
                terminal.addLine(to: CGPoint(
                    x: end.x - perpendicular.dx * 3,
                    y: end.y - perpendicular.dy * 3
                ))
                clipped.stroke(
                    terminal,
                    with: .color(Palette.signal.opacity(0.46 * visibility)),
                    style: StrokeStyle(lineWidth: 0.65, lineCap: .butt)
                )
            }
        }
    }

    // MARK: - 视野外目标信标

    /// 屏幕边缘的方向信标：朝目标方向的细线箭头 + 极弱信号光晕。
    static func drawEdgeCue(
        _ context: GraphicsContext,
        direction: CGVector,
        inside bounds: CGRect,
        rank: Int,
        time: TimeInterval
    ) {
        let length = hypot(direction.dx, direction.dy)
        guard length > 1e-6 else { return }

        let ux = direction.dx / length
        let uy = direction.dy / length
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let horizontal = abs(ux) > 1e-6
            ? (ux > 0 ? bounds.maxX - center.x : center.x - bounds.minX) / abs(ux)
            : .greatestFiniteMagnitude
        let vertical = abs(uy) > 1e-6
            ? (uy > 0 ? bounds.maxY - center.y : center.y - bounds.minY) / abs(uy)
            : .greatestFiniteMagnitude
        let travel = min(horizontal, vertical)
        let tip = CGPoint(x: center.x + ux * travel, y: center.y + uy * travel)

        let breath = Motion.breath(at: time, phase: Double(rank) * 1.7)
        let rankAlpha = rank == 0 ? 0.72 : (rank == 1 ? 0.54 : 0.42)
        let alpha = rankAlpha * breath

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            let radius: CGFloat = rank == 0 ? 8 : 6
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: tip.x - radius, y: tip.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(Palette.signal.opacity(0.18 * alpha))
            )
        }

        let base = CGPoint(x: tip.x - ux * 9, y: tip.y - uy * 9)
        let px = -uy
        let py = ux
        var chevron = Path()
        chevron.move(to: CGPoint(x: base.x + px * 4, y: base.y + py * 4))
        chevron.addLine(to: tip)
        chevron.addLine(to: CGPoint(x: base.x - px * 4, y: base.y - py * 4))
        context.stroke(
            chevron,
            with: .color(Palette.signal.opacity(alpha)),
            style: StrokeStyle(lineWidth: 0.85, lineCap: .butt, lineJoin: .miter)
        )

        // 箭头内侧留一段断开的校准线，延续准星与刻度的仪器语言。
        var calibration = Path()
        calibration.move(to: CGPoint(x: base.x - ux * 4, y: base.y - uy * 4))
        calibration.addLine(to: CGPoint(x: base.x - ux * 9, y: base.y - uy * 9))
        context.stroke(
            calibration,
            with: .color(Palette.inkLow.opacity(alpha * 0.65)),
            style: StrokeStyle(lineWidth: 0.5, lineCap: .butt)
        )
    }

    // MARK: - 时间拖影

    /// 拨动时间时对象留下的运动痕迹。尾端渐隐，龄期越老越透明。
    static func drawTrail(
        _ context: GraphicsContext,
        points: [TrailStore.TrailPoint],
        frameTime: TimeInterval,
        tint: Color,
        intensity: Double = 0.55,
        maximumSegmentLength: CGFloat = 44,
        lifetime: TimeInterval = TrailStore.lifetime
    ) {
        guard points.count >= 2 else { return }

        // 每颗对象只创建一次模糊层。旧实现每一小段都 blur，拖动时会制造上千图层。
        var glowPath = Path()
        glowPath.move(to: points[0].point)
        var previous = points[0].point
        for point in points.dropFirst() {
            if hypot(point.point.x - previous.x, point.point.y - previous.y) > maximumSegmentLength {
                glowPath.move(to: point.point)
            } else {
                glowPath.addLine(to: point.point)
            }
            previous = point.point
        }
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 2.0))
            glow.stroke(
                glowPath,
                with: .color(tint.opacity(0.07 * intensity)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
        }

        // 细芯仍分段绘制，以年龄控制尾端渐隐。
        for i in 1 ..< points.count {
            let a = points[i - 1]
            let b = points[i]
            let age = frameTime - b.at
            let life = max(0, 1 - age / lifetime)
            let alpha = 0.48 * intensity * life * life
            guard alpha > 0.01 else { continue }
            guard hypot(b.point.x - a.point.x, b.point.y - a.point.y) <= maximumSegmentLength else {
                continue
            }
            var seg = Path()
            seg.move(to: a.point)
            seg.addLine(to: b.point)
            context.stroke(
                seg,
                with: .color(tint.opacity(alpha)),
                style: StrokeStyle(lineWidth: 0.64, lineCap: .round)
            )
        }
    }

    // MARK: - 轨迹弧

    /// 锁定对象的过去/未来轨迹。过去段实线 0.30 渐隐尾，未来段虚线 0.22。
    /// `alpha` 整体透明度（用于生长/消隐）。
    static func drawTrack(
        _ context: GraphicsContext,
        pastPoints: [CGPoint],
        futurePoints: [CGPoint],
        alpha: Double
    ) {
        guard alpha > 0.01 else { return }

        if pastPoints.count >= 2 {
            var path = Path()
            path.move(to: pastPoints[0])
            for p in pastPoints.dropFirst() { path.addLine(to: p) }
            context.stroke(
                path,
                with: .color(Palette.inkFaint.opacity(0.30 * alpha)),
                style: StrokeStyle(lineWidth: 0.5, lineCap: .butt)
            )
        }
        if futurePoints.count >= 2 {
            var path = Path()
            path.move(to: futurePoints[0])
            for p in futurePoints.dropFirst() { path.addLine(to: p) }
            context.stroke(
                path,
                with: .color(Palette.inkFaint.opacity(0.22 * alpha)),
                style: StrokeStyle(lineWidth: 0.5, lineCap: .butt, dash: [1, 6])
            )
        }
    }

    // MARK: - 信号连线

    /// 锁定目标 → 档案边界的极细关系线。锚点由几何层选择最近边界，因此直线
    /// 在抵达档案前不会穿过正文；稳定阅读时弱化，目标移动时短暂增强。
    static func drawSignalLine(
        _ context: GraphicsContext,
        from point: CGPoint,
        to anchor: CGPoint,
        progress: Double,
        alpha: Double
    ) {
        guard progress > 0.01, alpha > 0.01 else { return }
        let dx = anchor.x - point.x
        let dy = anchor.y - point.y
        let total = hypot(dx, dy)
        guard total > 0.75 else { return }

        let p = min(1, max(0, progress))
        let pCGFloat = CGFloat(p)
        let distanceAttenuation = 1 - min(CGFloat(0.38), max(0, (total - 180) / 620))
        let attenuation = Double(distanceAttenuation)
        let end = CGPoint(x: point.x + dx * pCGFloat, y: point.y + dy * pCGFloat)
        var path = Path()
        path.move(to: point)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(Palette.signal.opacity(0.30 * alpha * attenuation)),
            style: StrokeStyle(lineWidth: 0.5, lineCap: .butt)
        )

        // 完成生长后在档案边界留一条横向校准刻度，明确“关系终点”而非装饰线。
        if p > 0.92 {
            let ux = dx / total
            let uy = dy / total
            let px = -uy
            let py = ux
            let notchProgress = min(1, (p - 0.92) / 0.08)
            let notchCGFloat = CGFloat(notchProgress)
            var notch = Path()
            notch.move(to: CGPoint(
                x: anchor.x + px * 2.5 * notchCGFloat,
                y: anchor.y + py * 2.5 * notchCGFloat
            ))
            notch.addLine(to: CGPoint(
                x: anchor.x - px * 2.5 * notchCGFloat,
                y: anchor.y - py * 2.5 * notchCGFloat
            ))
            context.stroke(
                notch,
                with: .color(Palette.signal.opacity(0.3 * alpha * attenuation)),
                style: StrokeStyle(lineWidth: 0.5, lineCap: .butt)
            )
        }
    }

    // MARK: - 扫描带

    /// 进入捕捉态的一次性扫描：一条水平细亮带从点位上方 40pt 扫过 80pt 区域。
    /// `progress` 0..1。
    static func drawScanBand(
        _ context: GraphicsContext,
        around point: CGPoint,
        width: CGFloat,
        progress: Double
    ) {
        guard progress > 0, progress < 1 else { return }
        // easeInOut
        let eased = progress < 0.5
            ? 2 * progress * progress
            : 1 - pow(-2 * progress + 2, 2) / 2
        let y = point.y - 40 + CGFloat(eased) * 80
        // 两端渐弱
        let fade = sin(progress * .pi)
        let bandRect = CGRect(x: point.x - width / 2, y: y - 0.5, width: width, height: 1)
        let gradient = Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Palette.signal.opacity(0.3 * fade), location: 0.5),
            .init(color: .clear, location: 1),
        ])
        context.fill(
            Path(bandRect),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: bandRect.minX, y: y),
                endPoint: CGPoint(x: bandRect.maxX, y: y)
            )
        )
    }

    // MARK: - Vignette

    static func drawVignette(_ context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(size.width, size.height) * 0.72
        let gradient = Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.55),
            .init(color: Palette.voidEdge.opacity(0.55), location: 1),
        ])
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
        )
    }
}
