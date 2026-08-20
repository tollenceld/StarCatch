import SwiftUI

struct SatelliteInsightGraphic: View {
    let insight: SatelliteInsightSnapshot
    let tint: Color
    var compact = false

    var body: some View {
        Group {
            if let pass = insight.pass, pass.phase != .stationary {
                SatellitePassArcView(
                    pass: pass,
                    observationTime: insight.observationTime,
                    tint: tint,
                    compact: compact
                )
            } else {
                OrbitFingerprintView(
                    fingerprint: insight.fingerprint,
                    tint: tint,
                    compact: compact
                )
            }
        }
    }
}

struct SatellitePassArcView: View {
    let pass: PassWindow
    let observationTime: Date
    let tint: Color
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            Canvas { context, size in
                let inset: CGFloat = compact ? 7 : 10
                let baseline = size.height - (compact ? 7 : 10)
                let peakHeight = max(8, size.height - (compact ? 13 : 19))
                var arc = Path()
                arc.move(to: CGPoint(x: inset, y: baseline))
                arc.addQuadCurve(
                    to: CGPoint(x: size.width - inset, y: baseline),
                    control: CGPoint(x: size.width / 2, y: baseline - peakHeight * 2)
                )
                context.stroke(
                    arc,
                    with: .color(tint.opacity(0.56)),
                    style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
                )

                var horizon = Path()
                horizon.move(to: CGPoint(x: 0, y: baseline))
                horizon.addLine(to: CGPoint(x: size.width, y: baseline))
                context.stroke(
                    horizon,
                    with: .color(Palette.inkFaint.opacity(0.34)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 4])
                )

                let progress = markerProgress
                let x = inset + (size.width - inset * 2) * progress
                let normalized = 2 * progress - 1
                let y = baseline - peakHeight * (1 - normalized * normalized)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4)),
                    with: .color(tint.opacity(0.95))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)),
                    with: .color(tint.opacity(0.08))
                )
            }
            .frame(height: compact ? 34 : 56)

            if !compact {
                HStack {
                    Text(pass.phase == .approaching ? "NEXT RISE" : "RISE")
                    Spacer()
                    if let maximum = pass.maximumElevationDegrees {
                        Text(String(format: "PEAK %+.0f°", maximum))
                    }
                    Spacer()
                    Text("SET")
                }
                .font(Typography.statusTag)
                .tracking(0.55)
                .foregroundStyle(Palette.inkLow.opacity(0.68))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var markerProgress: Double {
        if pass.phase == .approaching { return 0.04 }
        return pass.progress(at: observationTime) ?? 0.5
    }

    private var accessibilitySummary: String {
        switch pass.phase {
        case .approaching:
            return "目标下一次过境轨迹"
        case .visible:
            let percent = Int((pass.progress(at: observationTime) ?? 0) * 100)
            return "目标正在过境，已完成约百分之\(percent)"
        case .stationary:
            return "目标方向短时间内保持稳定"
        }
    }
}

struct OrbitFingerprintView: View {
    let fingerprint: OrbitFingerprint
    let tint: Color
    var compact = false

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let eccentricity = min(0.82, max(0, fingerprint.eccentricity))
            let width = size.width - (compact ? 20 : 34)
            let height = max(compact ? 13 : 22, width * CGFloat(0.38 - eccentricity * 0.22))
            let rect = CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            )
            var transformed = context
            transformed.translateBy(x: center.x, y: center.y)
            transformed.rotate(by: .degrees(fingerprint.inclinationDegrees * 0.28 - 14))
            transformed.translateBy(x: -center.x, y: -center.y)
            transformed.stroke(
                Path(ellipseIn: rect),
                with: .color(tint.opacity(0.55)),
                style: StrokeStyle(lineWidth: 0.65, dash: [5, 3])
            )
            transformed.fill(
                Path(ellipseIn: CGRect(x: center.x - 2.1, y: center.y - 2.1, width: 4.2, height: 4.2)),
                with: .color(Palette.inkHigh.opacity(0.72))
            )
            let objectX = rect.maxX - width * CGFloat(eccentricity * 0.22)
            transformed.fill(
                Path(ellipseIn: CGRect(x: objectX - 2.4, y: center.y - 2.4, width: 4.8, height: 4.8)),
                with: .color(tint.opacity(0.96))
            )
        }
        .frame(height: compact ? 34 : 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: "轨道指纹，周期 %.1f 分钟，倾角 %.1f 度，离心率 %.4f",
                fingerprint.periodMinutes,
                fingerprint.inclinationDegrees,
                fingerprint.eccentricity
            )
        )
    }
}
