import SwiftUI

/// StarCatch 字体系统。
///
/// 数据字段：SF Mono 度量（只能经 `design: .monospaced` 取得，不能按名字加载）。
/// 中文描述：苹方细体 —— 小字号深底下宋体横画会糊，细体苹方更接近"仪器铭牌"。
/// 中英分行呈现，不同段混排，各守各的节奏。
enum Typography {

    /// 数据字段值：随 Dynamic Type 缩放的 callout 等宽体。
    static let dataValue = Font.system(.callout, design: .monospaced, weight: .regular)
    static let dataValueTracking: CGFloat = 0.4

    /// 字段标签：不低于 11pt，使用中等字重抵消深色背景损失。
    static let fieldLabel = Font.system(.caption, design: .monospaced, weight: .medium)
    static let fieldLabelTracking: CGFloat = 1.8

    /// 对象名称：headline 等宽 semibold。
    static let objectName = Font.system(.headline, design: .monospaced, weight: .semibold)
    static let objectNameTracking: CGFloat = 1.0

    /// 主天空窄档案带：比页面标题低一级，把空间让给任务故事。
    static let archiveObjectName = Font.system(.subheadline, design: .monospaced, weight: .semibold)

    /// 中文描述：正文级系统字体，兼顾苹方形态与 Dynamic Type。
    static let poetic = Font.system(.body, design: .default, weight: .regular)
    static let poeticTracking: CGFloat = 1.0
    static let poeticLineSpacing: CGFloat = 10

    /// 天体档案的诗意说明：刻意退到遥测数据之后，恢复较轻、较暗的旧版气质。
    static let archivePoetic = Font.custom("PingFangSC-Light", size: 12.5, relativeTo: .footnote)
    static let archivePoeticTracking: CGFloat = 0.9
    static let archivePoeticLineSpacing: CGFloat = 6

    static let archiveNarrative = Font.custom("PingFangSC-Light", size: 11.5, relativeTo: .caption)
    static let archiveNarrativeTracking: CGFloat = 0.7
    static let archiveNarrativeLineSpacing: CGFloat = 5

    /// 窄档案带使用的紧凑遥测字号；仍随 Dynamic Type 缩放。
    static let archiveFieldLabel = Font.system(.caption2, design: .monospaced, weight: .medium)
    static let archiveDataValue = Font.system(.caption, design: .monospaced, weight: .regular)

    /// 引导提示：footnote regular，避免极细字重在暗背景消失。
    static let guide = Font.system(.footnote, design: .default, weight: .regular)
    static let guideTracking: CGFloat = 1.2

    /// 状态角标：caption2 medium，最低约 11pt。
    static let statusTag = Font.system(.caption2, design: .monospaced, weight: .medium)
    static let statusTagTracking: CGFloat = 1.3
}
