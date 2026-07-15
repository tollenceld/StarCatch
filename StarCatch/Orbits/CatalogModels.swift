import Foundation

/// 面向观测者的四类目录。`.all` 属于筛选状态，不是目标本身的类别。
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

enum CatalogFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case exploration
    case observation
    case network
    case legacy

    var id: String { rawValue }
    var category: CatalogCategory? { CatalogCategory(rawValue: rawValue) }

    var title: String {
        category?.title ?? "全部"
    }

    var subtitle: String {
        category?.subtitle ?? "显示本地目录中的全部轨道目标"
    }

    var symbolName: String {
        category?.symbolName ?? "circle.grid.2x2"
    }

    func includes(_ object: CatalogObject) -> Bool {
        category == nil || category == object.category
    }
}

/// 超大星座不是新的任务类别，而是类别内部需要特殊呈现的轨道家族。
enum CatalogFamily: String, Codable, Sendable {
    case starlink
}

/// 目录条目：档案元数据与一个已经在本地解码的 OMM/TLE 元素集。
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

    enum Status: String, Codable, Sendable {
        case active, silent, derelict, debris

        /// 是否用“在役”色调（冷灰绿）；否则暖偏。
        var isActive: Bool { self == .active }
    }
}
