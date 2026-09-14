import Foundation

/// 主天空之上的互斥工具面板只有一个事实源。关联值只携带轻量路由，
/// 不保存 View 或业务状态。
enum AppPageDestination: Identifiable, Hashable {
    case filters
    case observations
    case settings(initialRoute: SettingsRoute?)

    var id: String {
        switch self {
        case .filters: "filters"
        case .observations: "observations"
        case .settings: "settings"
        }
    }
}

/// 设置页内部的可导航页面。
enum SettingsRoute: Hashable {
    case systemStatus
}

/// 观测记录页内部的可导航页面。
enum ObservationRoute: Hashable {
    case detail(String)
}
