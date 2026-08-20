import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 顶部状态翼与其展开框共用的材质。几何尺寸由调用方决定，材质、边框与圆角
/// 始终保持一致，避免展开前后看起来像两套互不相关的浮层。
struct SkyWingSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    var interactive = true

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(Palette.voidBlack.opacity(0.075))
                        .interactive(interactive),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        Palette.inkFaint.opacity(0.24),
                        lineWidth: AppChromeMetrics.strokeWidth
                    )
                }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Palette.voidBlack.opacity(0.58), in: shape)
                .overlay {
                    shape.stroke(
                        Palette.inkFaint.opacity(0.24),
                        lineWidth: AppChromeMetrics.strokeWidth
                    )
                }
        }
    }
}

/// iPhone 17 系列顶部构图参数。
///
/// Apple 不向普通 App 暴露灵动岛的实时 frame，因此这里不按机型名称判断，而用
/// 原生像素短边识别 17 / 17 Pro、Air、17 Pro Max，再按实际 SwiftUI 画布缩放。
/// 真正的系统内容仍由安全区保护；这些参数只决定两枚非关键状态翼的视觉对齐。
struct DynamicIslandWingMetrics: Equatable {
    enum DisplayFamily: Equatable {
        case regular
        case air
        case proMax
        case unsupported
    }

    let family: DisplayFamily
    let islandGapWidth: CGFloat
    let statusWingWidth: CGFloat
    let directionWingWidth: CGFloat
    let topPadding: CGFloat
    let wingHeight: CGFloat
    let wingCornerRadius: CGFloat

    var usesIslandLayout: Bool { family != .unsupported }
    /// 左右翼统一宽度；保留单一入口供布局与测试读取。
    var wingWidth: CGFloat { directionWingWidth }
    var islandCenterY: CGFloat {
        topPadding + SkyTopBarMetrics.controlHeight / 2
    }

    init(viewportSize: CGSize, nativePixelSize: CGSize? = nil) {
        #if canImport(UIKit)
        let resolvedNativeSize = nativePixelSize ?? UIScreen.main.nativeBounds.size
        #else
        let resolvedNativeSize = nativePixelSize ?? .zero
        #endif
        let nativeShortEdge = min(resolvedNativeSize.width, resolvedNativeSize.height)

        guard nativeShortEdge >= 1_180 else {
            family = .unsupported
            islandGapWidth = 0
            directionWingWidth = 116
            statusWingWidth = directionWingWidth
            topPadding = 0
            wingHeight = SkyTopBarMetrics.visualHeight
            wingCornerRadius = AppChromeMetrics.wingCornerRadius
            return
        }

        let referenceWidth: CGFloat
        let baseGapWidth: CGFloat
        let baseWingWidth: CGFloat
        let baseTopPadding: CGFloat

        if nativeShortEdge >= 1_300 {
            family = .proMax
            referenceWidth = 440
            baseGapWidth = 136
            baseWingWidth = 126
            baseTopPadding = 11
        } else if nativeShortEdge >= 1_230 {
            family = .air
            referenceWidth = 420
            baseGapWidth = 136
            baseWingWidth = 122
            baseTopPadding = 10
        } else {
            family = .regular
            referenceWidth = 402
            baseGapWidth = 134
            baseWingWidth = 116
            baseTopPadding = 9
        }

        // Xcode 的优化截图和 Display Zoom 可能让 SwiftUI 画布小于官方 point 宽度。
        // 用原生像素识别机型族，再按实际容器宽度缩放，避免同一组常量在不同画布
        // 上横向侵入岛体或纵向漂移。
        let scale = min(1, max(0.82, viewportSize.width / referenceWidth))
        islandGapWidth = baseGapWidth * scale
        statusWingWidth = baseWingWidth * scale
        directionWingWidth = baseWingWidth * scale
        topPadding = baseTopPadding * scale
        wingHeight = SkyTopBarMetrics.visualHeight
        wingCornerRadius = AppChromeMetrics.wingCornerRadius
    }
}

/// 灵动岛两侧的观测功能翼。状态和姿态各自成组，中间始终保持透明，
/// 让系统区域成为构图的一部分，而不是再在下方叠一条完整 Banner。
struct SkyStatusIndicator: View {

    enum Mode: Equatable {
        case observing
        case sensing
        case focusing
        case locked(identifier: String, confirmedAt: Date?)
        case releasing(identifier: String)
        case field(timeLabel: String)
        case degraded(reason: String)

        func label(at date: Date) -> String {
            switch self {
            case .observing: L10n.text("sky.status.observing")
            case .sensing: L10n.text("sky.status.sensing")
            case .focusing: L10n.text("sky.status.focusing")
            case .locked(let identifier, let confirmedAt):
                if let confirmedAt,
                   date.timeIntervalSince(confirmedAt) < Motion.lockStatusHoldDuration {
                    L10n.text("sky.status.locked")
                } else {
                    identifier
                }
            case .releasing: L10n.text("sky.status.releasing")
            case .field: L10n.text("sky.status.global")
            case .degraded: L10n.text("sky.status.degraded")
            }
        }

        var fullLabel: String {
            switch self {
            case .field(let timeLabel): timeLabel
            case .degraded(let reason): reason
            case .releasing(let identifier): L10n.format("sky.status.release_object", identifier)
            default: label(at: Date())
            }
        }

        var indicatorTint: Color {
            switch self {
            case .observing, .field: Palette.inkMid
            case .sensing, .focusing, .locked, .releasing: Palette.signal
            case .degraded: Palette.legacyTint
            }
        }

        var breathes: Bool {
            switch self {
            case .sensing, .focusing: true
            default: false
            }
        }

        var isEvent: Bool {
            switch self {
            case .sensing, .focusing, .locked, .releasing: true
            default: false
            }
        }

        var isLocked: Bool {
            if case .locked = self { return true }
            return false
        }
    }

    let mode: Mode
    let azimuth: String
    let elevation: String
    let presence: Double
    var activation: Double = 0
    var islandLayout: Bool = true
    var islandGapWidth: CGFloat = 134
    var islandStatusWingWidth: CGFloat = 116
    var islandDirectionWingWidth: CGFloat = 116
    var wingHeight: CGFloat = SkyTopBarMetrics.visualHeight
    var wingCornerRadius: CGFloat = AppChromeMetrics.wingCornerRadius
    var backTitle: String?
    var onBack: (() -> Void)?
    var onStatusTap: () -> Void = {}
    var onDirectionTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @AppStorage("reducedMotion") private var reducedMotion = false

    private var suppressMotion: Bool { reducedMotion || systemReducedMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: false)) { timeline in
            let breath = mode.breathes && !suppressMotion
                ? Motion.breath(at: timeline.date.timeIntervalSinceReferenceDate)
                : 1
            let label = mode.label(at: timeline.date)

            if islandLayout {
                islandWingPair(label: label, breath: breath)
            } else if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: 12) {
                        compactWingPair(label: label, breath: breath)
                    }
                    .frame(maxWidth: .infinity)
            } else {
                compactWingPair(label: label, breath: breath)
                    .frame(maxWidth: .infinity)
            }
        }
        .opacity(presence)
        .animation(
            suppressMotion ? .easeOut(duration: 0.14) : Motion.interfaceExpand,
            value: mode
        )
    }

    private func islandWingPair(label: String, breath: Double) -> some View {
        GeometryReader { geo in
            if backTitle != nil {
                statusWing(label: label, breath: breath)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(
                        width: geo.size.width,
                        height: SkyTopBarMetrics.controlHeight,
                        alignment: .leading
                    )
                    .padding(.leading, SkyTopBarMetrics.outerMargin)

                let centerX = geo.size.width / 2
                let directionCenterOffset = islandGapWidth / 2
                    + islandDirectionWingWidth / 2
                directionWing
                    .frame(width: islandDirectionWingWidth, alignment: .leading)
                    .position(
                        x: centerX + directionCenterOffset,
                        y: SkyTopBarMetrics.controlHeight / 2
                    )
            } else {
                let centerX = geo.size.width / 2
                let statusCenterOffset = islandGapWidth / 2
                    + islandStatusWingWidth / 2
                let directionCenterOffset = islandGapWidth / 2
                    + islandDirectionWingWidth / 2

                statusWing(label: label, breath: breath)
                    .frame(width: islandStatusWingWidth, alignment: .trailing)
                    .position(
                        x: centerX - statusCenterOffset,
                        y: SkyTopBarMetrics.controlHeight / 2
                    )

                directionWing
                    .frame(width: islandDirectionWingWidth, alignment: .leading)
                    .position(
                        x: centerX + directionCenterOffset,
                        y: SkyTopBarMetrics.controlHeight / 2
                    )
            }
        }
    }

    private func compactWingPair(label: String, breath: Double) -> some View {
        HStack(spacing: 0) {
            statusWing(label: label, breath: breath)
                .frame(width: backTitle == nil ? resolvedStatusWingWidth : nil)
                .fixedSize(horizontal: backTitle != nil, vertical: false)
            Spacer(minLength: 12)
            directionWing
                .frame(width: islandDirectionWingWidth)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SkyTopBarMetrics.outerMargin)
    }

    private var resolvedStatusWingWidth: CGFloat {
        guard backTitle != nil else { return islandStatusWingWidth }
        return min(islandStatusWingWidth, AppChromeMetrics.compactBackWingWidth)
    }

    @ViewBuilder
    private func statusWing(label: String, breath: Double) -> some View {
        if let backTitle, let onBack {
            AppBackControl(title: backTitle, action: onBack)
                .padding(.horizontal, 8)
                .frame(height: wingHeight)
                .modifier(
                    SkyWingSurfaceModifier(
                        cornerRadius: wingCornerRadius,
                        interactive: true
                    )
                )
                .frame(height: SkyTopBarMetrics.controlHeight)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            statusSurface(label: label, breath: breath)
        }
    }

    @ViewBuilder
    private func statusSurface(label: String, breath: Double) -> some View {
        let core = Button(action: onStatusTap) {
            HStack(spacing: 6) {
                indicator(breath: breath)

                if mode.isLocked, label != L10n.text("sky.status.locked") {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Palette.signal.opacity(0.88))
                }

                Text(label)
                    .font(Typography.statusTag)
                    .tracking(0.7)
                    .foregroundStyle(Palette.inkMid.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: wingHeight, maxHeight: wingHeight)
            .offset(y: -0.25)
            .contentShape(RoundedRectangle(cornerRadius: wingCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("sky.status.accessibility", mode.fullLabel))
        .accessibilityHint(L10n.text("sky.status.accessibility.hint"))
        core
            .modifier(
                SkyWingSurfaceModifier(
                    cornerRadius: wingCornerRadius,
                    interactive: true
                )
            )
            .frame(height: SkyTopBarMetrics.controlHeight)
    }

    @ViewBuilder
    private var directionWing: some View {
        let core = Button(action: onDirectionTap) {
            HStack(spacing: 4) {
                Text(azimuth)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Rectangle()
                    .fill(Palette.inkFaint.opacity(0.3))
                    .frame(width: 0.5, height: 10)
                Text(elevation)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .tracking(0.3)
            .foregroundStyle(Palette.inkMid.opacity(Palette.Level.secondary))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: wingHeight, maxHeight: wingHeight)
            .offset(y: -0.55)
            .contentShape(RoundedRectangle(cornerRadius: wingCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("sky.direction.accessibility", azimuth, elevation))
        .accessibilityHint(L10n.text("sky.direction.accessibility.hint"))

        core
            .modifier(
                SkyWingSurfaceModifier(
                    cornerRadius: wingCornerRadius,
                    interactive: true
                )
            )
            .frame(height: SkyTopBarMetrics.controlHeight)
    }

    private func indicator(breath: Double) -> some View {
        ZStack {
            if mode.breathes {
                Circle()
                    .trim(from: 0, to: max(0.18, min(1, activation)))
                    .stroke(
                        mode.indicatorTint.opacity(0.34 * breath),
                        style: StrokeStyle(lineWidth: 0.6, lineCap: .round)
                    )
                    .frame(width: 9, height: 9)
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .fill(mode.indicatorTint.opacity(Palette.Level.present * breath))
                .frame(width: 3.5, height: 3.5)
        }
        .frame(width: 9, height: 9)
    }
}
