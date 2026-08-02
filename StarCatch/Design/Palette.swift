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

    /// 其他大型星座使用同样克制的低饱和光谱，只改变外晕，不把天空变成彩色点阵。
    static let oneWebTint = Color(hex: 0xA7A0B8)
    static let qianfanTint = Color(hex: 0xB8AA92)
    static let hulianwangTint = Color(hex: 0xAF9991)
    static let kuiperTint = Color(hex: 0x93AEAA)
    static let iridiumTint = Color(hex: 0xA3A9AD)
    static let globalstarTint = Color(hex: 0x9EAFA2)
    static let orbcommTint = Color(hex: 0xB0A49B)

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
        /// 功能性次级文字。它比装饰层清晰，但仍明显退后于正文与实时数据。
        static let secondary: Double = 0.70
        /// 需要被读懂、但不应与核心数据竞争的说明文字。
        static let readableSecondary: Double = 0.78
        /// 承担分组和导航边界的功能性细线；装饰线仍使用更低透明度。
        static let functionalDivider: Double = 0.42
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
    /// 具体镜片沿用低饱和任务色；大型网络只改变微光，不把天空做成彩色图例。
    var tint: Color {
        switch self {
        case .all: Palette.inkMid
        case .featured: Palette.signal
        case .humanScience: Palette.explorationTint
        case .earthObservation: Palette.observationTint
        case .navigation, .communications: Palette.networkTint
        case .orbitalHeritage: Palette.legacyTint
        case .unitedStates: Palette.explorationTint
        case .europe: Palette.observationTint
        case .china: Palette.legacyTint
        case .otherPublic: Palette.signal
        case .starlink: Palette.starlinkTint
        case .oneweb: Palette.oneWebTint
        case .chinaConstellations: Palette.qianfanTint
        case .kuiper: Palette.kuiperTint
        case .mobileConstellations: Palette.iridiumTint
        }
    }
}

extension CatalogFilterGroup {
    var tint: Color {
        switch self {
        case .overview: Palette.inkMid
        case .mission: Palette.explorationTint
        case .authority: Palette.observationTint
        case .constellation: Palette.networkTint
        }
    }
}

extension CatalogFamily {
    var tint: Color {
        switch self {
        case .starlink: Palette.starlinkTint
        case .oneweb: Palette.oneWebTint
        case .qianfan: Palette.qianfanTint
        case .hulianwang: Palette.hulianwangTint
        case .kuiper: Palette.kuiperTint
        case .iridium: Palette.iridiumTint
        case .globalstar: Palette.globalstarTint
        case .orbcomm: Palette.orbcommTint
        }
    }
}

extension CatalogObject {
    /// 大型星座使用各自的低饱和光谱；普通目标仍由任务类别表达身份。
    var identityTint: Color {
        family?.tint ?? category.tint
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
