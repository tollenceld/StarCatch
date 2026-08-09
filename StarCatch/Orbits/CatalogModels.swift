import Foundation

/// 轨道对象的任务语义。它继续负责档案措辞与天空基础色，不直接承担筛选。
enum CatalogCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case exploration
    case observation
    case network
    case legacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exploration: "探索"
        case .observation: "观测"
        case .network: "网络"
        case .legacy: "遗迹"
        }
    }

    var subtitle: String {
        switch self {
        case .exploration: "人类驻留、科学与实验任务"
        case .observation: "持续阅读地球与大气"
        case .network: "通信、导航与星座 · 大型星座自动收束"
        case .legacy: "失效航天器、火箭体与轨道残留"
        }
    }

    var symbolName: String {
        switch self {
        case .exploration: "sparkles"
        case .observation: "eye"
        case .network: "antenna.radiowaves.left.and.right"
        case .legacy: "circle.dashed"
        }
    }
}

/// 筛选的一级语义。它只负责组织二级镜片，不直接改变目录。
enum CatalogFilterGroup: String, CaseIterable, Identifiable, Sendable {
    case overview
    case mission
    case authority
    case constellation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "常用镜片"
        case .mission: "看它们在做什么"
        case .authority: "看谁在运行"
        case .constellation: "看一片轨道网络"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "从完整天空或少量精选目标开始"
        case .mission: "科学、地球、导航、通信与轨道历史"
        case .authority: "只看可由公开资料确认的运营者"
        case .constellation: "让某一个大型网络单独浮现"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "circle.grid.2x2"
        case .mission: "scope"
        case .authority: "building.columns"
        case .constellation: "point.3.connected.trianglepath.dotted"
        }
    }

    var filters: [CatalogFilter] {
        switch self {
        case .overview: [.all, .featured]
        case .mission:
            [.humanScience, .earthObservation, .navigation, .communications, .orbitalHeritage]
        case .authority:
            [.unitedStates, .europe, .china, .otherPublic]
        case .constellation:
            [.starlink, .oneweb, .chinaConstellations, .kuiper, .mobileConstellations]
        }
    }
}

/// 天空显示范围使用单选语义；它与下方可叠加的任务、运营方和网络镜片分离。
enum CatalogScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case lowEarth
    case mediumAndHigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部轨道"
        case .lowEarth: "近地轨道"
        case .mediumAndHigh: "中高轨道"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "scope"
        case .lowEarth: "circle.dashed"
        case .mediumAndHigh: "circle.circle"
        }
    }

    func includes(_ object: CatalogObject) -> Bool {
        switch self {
        case .all:
            true
        case .lowEarth:
            object.orbitClass == "LEO"
        case .mediumAndHigh:
            object.orbitClass != "LEO"
        }
    }
}

/// 面向观测者的具体目录镜片。每一项都必须能从随 App 打包的离线目录得到
/// 非空结果，并拥有独立的任务叙述或星座资料。
enum CatalogFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case featured
    case humanScience
    case earthObservation
    case navigation
    case communications
    case orbitalHeritage
    case unitedStates
    case europe
    case china
    case otherPublic
    case starlink
    case oneweb
    case chinaConstellations
    case kuiper
    case mobileConstellations

    /// 天空中的高频“观察镜片”。完整的机构与星座分类仍保留在第二层，
    /// 但日常观测不需要先穿过一张目录表。
    static let frequentLenses: [CatalogFilter] = [
        .all,
        .featured,
        .humanScience,
        .earthObservation,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部轨道"
        case .featured: "可读档案"
        case .humanScience: "载人与科学"
        case .earthObservation: "地球观察"
        case .navigation: "导航与授时"
        case .communications: "通信基础设施"
        case .orbitalHeritage: "历史与遗产"
        case .unitedStates: "美国公共任务"
        case .europe: "ESA / Copernicus"
        case .china: "中国公共任务"
        case .otherPublic: "其他公共任务"
        case .starlink: "Starlink"
        case .oneweb: "OneWeb"
        case .chinaConstellations: "中国低轨网络"
        case .kuiper: "Project Kuiper"
        case .mobileConstellations: "移动通信网络"
        }
    }

    /// 收起后的镜片入口只保留一个能够被迅速读懂的短名称。完整名称仍用于
    /// 展开面板和辅助功能，避免顶部工具区被机构全称挤占。
    var compactTitle: String {
        switch self {
        case .all: "观察镜片"
        case .featured: "档案"
        case .humanScience: "科学"
        case .earthObservation: "地球"
        case .navigation: "导航"
        case .communications: "通信"
        case .orbitalHeritage: "轨道历史"
        case .unitedStates: "美国公共"
        case .europe: "欧洲公共"
        case .china: "中国公共"
        case .otherPublic: "其他公共"
        case .starlink: "Starlink"
        case .oneweb: "OneWeb"
        case .chinaConstellations: "中国低轨"
        case .kuiper: "Kuiper"
        case .mobileConstellations: "移动网络"
        }
    }

    var subtitle: String {
        switch self {
        case .all: "完整离线目录 · 大型星座自动收束"
        case .featured: "具有可靠任务说明或深入资料的目标"
        case .humanScience: "空间站、望远镜与重要科学任务"
        case .earthObservation: "气象、陆地、海洋与气候记录"
        case .navigation: "GPS、Galileo、北斗等授时系统"
        case .communications: "中继、同步通信与早期链路"
        case .orbitalHeritage: "仍在轨的历史任务与沉默物体"
        case .unitedStates: "NASA、NOAA、USGS、GPS 等公共计划"
        case .europe: "ESA、EUMETSAT 与欧盟 Copernicus"
        case .china: "空间站、北斗、风云与对地观测"
        case .otherPublic: "JAXA、ISRO 与其他公开任务体系"
        case .starlink: "SpaceX 低轨宽带网络"
        case .oneweb: "Eutelsat OneWeb 近极轨通信网络"
        case .chinaConstellations: "千帆与国网低轨通信节点"
        case .kuiper: "Amazon 近地轨道宽带系统"
        case .mobileConstellations: "Iridium、Globalstar 与 Orbcomm"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "circle.grid.2x2"
        case .featured: "sparkle"
        case .humanScience: "sparkles"
        case .earthObservation: "eye"
        case .navigation: "location.north.line"
        case .communications: "antenna.radiowaves.left.and.right"
        case .orbitalHeritage: "circle.dashed"
        case .unitedStates: "star"
        case .europe: "circle.hexagongrid"
        case .china: "scope"
        case .otherPublic: "globe.asia.australia"
        case .starlink: "circle.grid.cross"
        case .oneweb: "circle.hexagongrid.fill"
        case .chinaConstellations: "point.3.filled.connected.trianglepath.dotted"
        case .kuiper: "circle.dotted.circle"
        case .mobileConstellations: "antenna.radiowaves.left.and.right"
        }
    }

    var group: CatalogFilterGroup {
        switch self {
        case .all, .featured: .overview
        case .humanScience, .earthObservation, .navigation, .communications, .orbitalHeritage:
            .mission
        case .unitedStates, .europe, .china, .otherPublic: .authority
        case .starlink, .oneweb, .chinaConstellations, .kuiper, .mobileConstellations:
            .constellation
        }
    }

    func includes(_ object: CatalogObject) -> Bool {
        switch self {
        case .all:
            true
        case .featured:
            object.hasIndividualReadableProfile
        case .humanScience:
            object.family == nil
                && (object.isRecognizedHumanScienceMission
                    || (object.kind == "science"
                        && object.category == .exploration
                        && !object.isRecognizedEarthMission))
        case .earthObservation:
            object.category == .observation && object.isRecognizedEarthMission
        case .navigation:
            object.family == nil && object.kind == "nav"
        case .communications:
            object.family == nil && object.kind == "comms"
        case .orbitalHeritage:
            object.family == nil && object.isRecognizedOrbitalHeritage
        case .unitedStates:
            object.family == nil && object.isUnitedStatesPublicMission
        case .europe:
            object.family == nil && object.isEuropeanPublicMission
        case .china:
            object.family == nil && object.isChinesePublicMission
        case .otherPublic:
            object.family == nil && object.isOtherPublicMission
        case .starlink:
            object.family == .starlink
        case .oneweb:
            object.family == .oneweb
        case .chinaConstellations:
            object.family == .qianfan || object.family == .hulianwang
        case .kuiper:
            object.family == .kuiper
        case .mobileConstellations:
            object.family == .iridium || object.family == .globalstar || object.family == .orbcomm
        }
    }
}

/// 超大星座不是任务类别，而是需要独立采样、着色与叙述的轨道家族。
enum CatalogFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case starlink
    case oneweb
    case qianfan
    case hulianwang
    case kuiper
    case iridium
    case globalstar
    case orbcomm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .starlink: "STARLINK"
        case .oneweb: "ONEWEB"
        case .qianfan: "千帆"
        case .hulianwang: "国网"
        case .kuiper: "KUIPER"
        case .iridium: "IRIDIUM"
        case .globalstar: "GLOBALSTAR"
        case .orbcomm: "ORBCOMM"
        }
    }

    static func infer(from name: String) -> CatalogFamily? {
        let upper = name.uppercased()
        if upper.hasPrefix("STARLINK") { return .starlink }
        if upper.contains("ONEWEB") { return .oneweb }
        if upper.contains("QIANFAN") { return .qianfan }
        if upper.contains("HULIANWANG") { return .hulianwang }
        if upper.contains("KUIPER") { return .kuiper }
        if upper.contains("IRIDIUM") { return .iridium }
        if upper.contains("GLOBALSTAR") { return .globalstar }
        if upper.contains("ORBCOMM") { return .orbcomm }
        return nil
    }
}

/// 公开名称能够可靠辨认的机构/主权集合。没有充分证据的对象留在 `.other`，
/// 不为了填满筛选而猜测所有权。
enum CatalogAuthority: String, Sendable {
    case unitedStates
    case europe
    case china
    case other

    static func infer(from name: String) -> CatalogAuthority {
        let upper = " \(name.uppercased()) "
        if contains(upper, tokens: chinaTokens) { return .china }
        if contains(upper, tokens: europeTokens) { return .europe }
        if contains(upper, tokens: unitedStatesTokens) { return .unitedStates }
        return .other
    }

    private static func contains(_ value: String, tokens: [String]) -> Bool {
        tokens.contains { value.contains($0) }
    }

    private static let unitedStatesTokens = [
        " ISS ", " HST ", " HUBBLE", " NOAA", " GOES", " LANDSAT",
        " TERRA ", " AQUA ", " TDRS", " NAVSTAR", " GPS", " USA ",
        " DMSP", " JPSS", " SUOMI", " NPP ", " ICESAT", " SMAP ",
        " CYGNSS", " TESS ", " FERMI", " SWIFT", " VANGUARD",
        " TELSTAR", " LAGEOS", " INTELSAT 901 ",
    ]

    private static let europeTokens = [
        " SENTINEL", " ENVISAT", " METOP", " METEOSAT", " ERS-",
        " CRYOSAT", " SWARM", " AEOLUS", " GALILEO", " EUTELSAT",
        " XMM-NEWTON", " PROBA-", " CHEOPS ", " SPOT ", " PLEIADES",
        " JASON", " SARAL", " COSMO-SKYMED", " CSG-", " TERRASAR",
        " TANDEM", " PAZ ", " SMOS", " GOCE", " CLUSTER", " INTEGRAL",
        " BIOMASS", " EARTHCARE",
    ]

    private static let chinaTokens = [
        " CSS ", " TIANHE", " TIANGONG", " FENGYUN", " BEIDOU",
        " GAOFEN", " YAOGAN", " HAIYANG", " SHIJIAN", " SHIYAN",
        " ZIYUAN", " CHUANGXIN", " CHUANG XIN",
    ]
}

/// 目录条目：发布脚本附加在 OMM 元素上的稳定任务元数据。
struct CatalogObject: Identifiable, Sendable {
    let id: String
    let name: String
    let noradId: Int
    let cosparId: String
    let orbitClass: String
    let launched: String
    let status: Status
    let kind: String
    let poetic: String
    let category: CatalogCategory
    let family: CatalogFamily?
    let elementEpoch: Date
    let isCurated: Bool

    var isStarlink: Bool { family == .starlink }
    var authority: CatalogAuthority { CatalogAuthority.infer(from: name) }

    private var normalizedName: String { " \(name.uppercased()) " }

    private func nameContains(any tokens: [String]) -> Bool {
        let normalizedName = normalizedName
        return tokens.contains { normalizedName.contains($0) }
    }

    /// 任务筛选只收录名称足以可靠辨认的公共对地任务。这样不会把数千个
    /// 只有通用类别的对象塞回天空，也不会靠猜测为未知载荷补写用途。
    var isRecognizedEarthMission: Bool {
        nameContains(any: [
            " NOAA ", " GOES ", " JPSS ", " SUOMI NPP ", " LANDSAT ",
            " TERRA ", " AQUA ", " SENTINEL-", " METOP", " METEOSAT",
            " HIMAWARI", " FENGYUN", " SWOT ", " ICESAT", " SMAP ",
            " GOSAT", " ALOS", " GCOM-", " CARTOSAT", " RESOURCESAT",
            " OCEANSAT", " METEOR-M", " ELEKTRO-L", " KANOPUS",
            " GAOFEN", " HAIYANG", " ZIYUAN", " SPOT ", " PLEIADES",
            " COSMO-SKYMED", " CSG-", " TERRASAR", " TANDEM", " PAZ ",
            " BIOMASS", " EARTHCARE", " SAOCOM", " KOMPSAT", " ARIRANG",
            " FORMOSAT", " RISAT", " INSAT", " EOS-",
        ])
    }

    /// “载人与科学”只回答任务本身，不再因为一个对象拥有精选档案，就把气象、
    /// 导航或通信目标错误地混进来。
    var isRecognizedHumanScienceMission: Bool {
        if kind == "station" || kind == "telescope" { return true }
        return nameContains(any: [
            " ISS ", " ZARYA ", " POISK ", " SOYUZ-MS ", " PROGRESS-MS ",
            " CREW DRAGON ", " CYGNUS NG-", " CSS ", " TIANHE", " WENTIAN",
            " MENGTIAN", " TIANZHOU", " SHENZHOU", " HST ", " HUBBLE",
            " CHEOPS ", " XMM-NEWTON", " CHANDRA", " TESS ", " FERMI", " SWIFT",
        ])
    }

    /// 轨道历史以早期发射年份、失效状态和明确历史系列共同界定。普通早期对象
    /// 提供真实观测密度，具有策展资料的地标继续承担深入阅读。
    var isRecognizedOrbitalHeritage: Bool {
        if nameContains(any: [
            " VANGUARD", " TELSTAR", " LAGEOS", " EXPLORER", " ARIEL",
            " OSCAR", " SYNCOM", " ATS ", " TIROS", " COSMOS 2251",
        ]) {
            return true
        }
        let launchYear = Int(launched.prefix(4)) ?? .max
        return status != .active || category == .legacy || launchYear <= 2005
    }

    var isUnitedStatesPublicMission: Bool {
        authority == .unitedStates
    }

    var isEuropeanPublicMission: Bool {
        authority == .europe
    }

    var isChinesePublicMission: Bool {
        authority == .china
    }

    /// 其余公共任务只纳入名称可辨认的日本、印度、俄罗斯、韩国、台湾与阿根廷
    /// 公开体系；`.other` 本身不代表可靠归属，因此不能直接作为筛选条件。
    var isOtherPublicMission: Bool {
        guard authority == .other else { return false }
        return nameContains(any: [
            " HIMAWARI", " GOSAT", " ALOS", " GCOM-", " MICHIBIKI",
            " IRNSS-", " CARTOSAT", " RESOURCESAT", " OCEANSAT",
            " INSAT", " GSAT-", " RISAT", " EOS-", " METEOR-M",
            " ELEKTRO-L", " KANOPUS", " GLONASS", " KOMPSAT", " ARIRANG",
            " FORMOSAT", " SAOCOM",
        ])
    }

    /// 用于筛选面板的“可读资料”计数。它不要求每个轨道节点都有长篇故事，
    /// 但必须至少有策展文字、可靠任务说明或星座共同资料。
    var hasMeaningfulProfile: Bool {
        isFeatured || isCurated || family != nil
    }

    /// “可读档案”只收录能够作为单颗对象阅读的条目。星座共有的组织名称
    /// 不足以让上万颗节点全部进入这一镜片；精选星座节点仍会保留。
    var hasIndividualReadableProfile: Bool {
        family == nil && (isFeatured || isCurated)
    }

    enum Status: String, Codable, Sendable {
        case active, silent, derelict, debris

        /// 是否用“在役”色调（冷灰绿）；否则暖偏。
        var isActive: Bool { self == .active }
    }
}
