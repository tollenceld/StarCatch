import SwiftUI

/// StarCatch 字体系统。
///
/// 数据字段：SF Mono 度量（只能经 `design: .monospaced` 取得，不能按名字加载）。
/// 连续正文使用系统字体，让 iOS 根据当前 App 语言选择合适的中文或拉丁字形；
/// 等宽体仅留给编号、短标签和数据。
enum Typography {

    /// 数据字段值：随 Dynamic Type 缩放的 callout 等宽体。
    static let dataValue = Font.system(.callout, design: .monospaced, weight: .regular)
    static let dataValueTracking: CGFloat = 0.4

    /// 字段标签：不低于 11pt，使用中等字重抵消深色背景损失。
    static let fieldLabel = Font.system(.caption2, design: .default, weight: .medium)
    static let fieldLabelTracking: CGFloat = 0.3

    /// 对象名称：20pt 系统 semibold，随 Dynamic Type 缩放。
    static let objectName = Font.system(.title3, design: .default, weight: .semibold)
    static let objectNameTracking: CGFloat = 0.15

    /// 主天空窄档案带：比页面标题低一级，把空间让给任务故事。
    static let archiveObjectName = Font.system(.callout, design: .default, weight: .semibold)

    /// 中文描述：正文级系统字体，兼顾苹方形态与 Dynamic Type。
    static let poetic = Font.system(.body, design: .default, weight: .regular)
    static let poeticTracking: CGFloat = 1.0
    static let poeticLineSpacing: CGFloat = 10

    /// 阅读型页面的中文正文。仪器感由版式和标签承担，连续中文不再强制等宽或大字距。
    static let readingBody = Font.system(.callout, design: .default, weight: .regular)
    static let readingBodyTracking: CGFloat = 0.1
    static let readingBodyLineSpacing: CGFloat = 6

    /// 设置说明与列表摘要使用的紧凑正文。
    static let readingCompact = Font.system(.footnote, design: .default, weight: .regular)
    static let readingCompactTracking: CGFloat = 0.1

    /// 天体档案的简短说明，层级低于目标名称与遥测数据。
    static let archivePoetic = Font.system(.footnote, design: .default, weight: .regular)
    static let archivePoeticTracking: CGFloat = 0.15
    static let archivePoeticLineSpacing: CGFloat = 6

    static let archiveNarrative = Font.system(.footnote, design: .default, weight: .regular)
    static let archiveNarrativeTracking: CGFloat = 0.1
    static let archiveNarrativeLineSpacing: CGFloat = 5

    /// 窄档案带使用的紧凑遥测字号；仍随 Dynamic Type 缩放。
    static let archiveFieldLabel = Font.system(.caption2, design: .default, weight: .medium)
    static let archiveDataValue = Font.system(.callout, design: .monospaced, weight: .regular)

    /// 引导提示：callout regular，避免极细字重在暗背景消失。
    static let guide = Font.system(.callout, design: .default, weight: .regular)
    static let guideTracking: CGFloat = 0.15

    /// 状态角标：caption2 medium，最低约 11pt。
    static let statusTag = Font.system(.caption2, design: .monospaced, weight: .medium)
    static let statusTagTracking: CGFloat = 0.5
}

/// A custom point size that still follows the view's Dynamic Type environment.
private struct InstrumentFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, relativeTo: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func instrumentFont(
        _ size: CGFloat,
        relativeTo: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(InstrumentFont(size: size, relativeTo: relativeTo, weight: weight, design: design))
    }
}
