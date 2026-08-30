import Foundation

/// 天空之上的系统 Sheet 只有一个事实源；关联值只携带轻量路由，不保存 View。
enum AppSheetDestination: Identifiable, Hashable {
    case filters
    case instrument(initialRoute: InstrumentRoute?)

    var id: String {
        switch self {
        case .filters: "filters"
        case .instrument: "instrument"
        }
    }
}

/// 仪器 Sheet 内部的可导航页面。根页始终是快速设置。
enum InstrumentRoute: Hashable {
    case systemStatus
    case observations
    case observationDetail(String)
}
