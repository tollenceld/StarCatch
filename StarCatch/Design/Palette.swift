import SwiftUI

/// StarCatch 色彩系统。
///
/// 原则：暖灰阶负责信息层级，暗琥珀负责交互信号；轨道类别只在星体光晕、
/// 轨迹与筛选图标里使用低饱和光谱色。星核始终保持纸白，避免彩色点阵感。
enum Palette {

    // MARK: - 基底

    /// 屏幕基底。不用纯黑 #000 —— OLED 上纯黑会让颗粒噪声失效，留一丝"介质感"。
    static let voidBlack = Color(hex: 0x070706)

    /// 四周径向 vignette 渐入的终点。
    static let voidEdge = Color(hex: 0x000000)

    // MARK: - 灰阶（全部暖灰）

    /// 星尘底噪 —— 背景假星点，最暗层。
    static let dust = Color(hex: 0x292927)

    /// 刻度线、非激活轨迹。
    static let inkFaint = Color(hex: 0x5D5A54)

    /// 次级文字、字段标签。
    static let inkLow = Color(hex: 0x908C83)

    /// 数据正文。
    static let inkMid = Color(hex: 0xBDB8AD)

    /// 对象名称、锁定态主文字 —— 暖纸白，绝不用 #FFFFFF。
    static let inkHigh = Color(hex: 0xEEE9DE)

    // MARK: - 信号色

    /// 信号/捕捉指示 —— 暗琥珀，永远低透明度使用（≤ 0.65）。
    static let signal = Color(hex: 0xD7BE8E)

    // MARK: - 轨道类别

    /// 科学、驻留与深空探索：旧纸张般的微金色。
    static let explorationTint = Color(hex: 0xC7B892)

    /// 地球与大气观测：低饱和灰绿。
    static let observationTint = Color(hex: 0xA7BBAE)

    /// 通信、导航与一般网络节点：克制的灰紫钢色。
    static let networkTint = Color(hex: 0xACA7B8)

    /// Starlink 星座：与网络类同源、但更冷更清晰的轨道钢蓝灰。
    static let starlinkTint = Color(hex: 0x99A9BA)

    /// 失效航天器与轨道残留：灰化的陶土色。
    static let legacyTint = Color(hex: 0xB79282)

    /// 兼容仍按运行状态着色的旧界面；新星图统一使用类别语义色。
    static let derelictTint = legacyTint

    /// 兼容旧状态读数的中性在役色。
    static let activeTint = Color(hex: 0xC1C7C0)

    // MARK: - 透明度层级

    /// 全部信息层级由同一颜色的四档透明度构成。
    enum Level {
        static let ghost: Double = 0.22
        static let faint: Double = 0.58
        static let present: Double = 0.84
        static let full: Double = 0.98
    }
}

extension CatalogCategory {
    /// 类别色只是一层身份光谱，不承担可读性或状态反馈。
    var tint: Color {
        switch self {
        case .exploration: Palette.explorationTint
        case .observation: Palette.observationTint
        case .network: Palette.networkTint
        case .legacy: Palette.legacyTint
        }
    }
}

extension CatalogFilter {
    /// “全部”保持中性；其余筛选与天空中的类别光晕一一对应。
    var tint: Color {
        category?.tint ?? Palette.inkMid
    }
}

extension CatalogObject {
    /// Starlink 是网络类别中的高密度家族，需要在相同色族中单独辨识。
    var identityTint: Color {
        isStarlink ? Palette.starlinkTint : category.tint
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
