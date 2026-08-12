import Combine
import CoreLocation
import Foundation

/// 观察者坐标：一次性精确定位；拒绝、过旧或误差过大时 fallback 内置坐标。
///
/// 低轨目标离观察者只有数百公里，50km 的近似位置足以造成数度视差，不能再
/// 冒充可用于准星捕获的真实位置。定位只参与设备内计算，不会上传或持久化。
final class ObserverLocation: NSObject, ObservableObject, CLLocationManagerDelegate {

    struct Coordinates: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var altitudeMeters: Double
        /// Core Location 报告的水平不确定半径。近似定位仍可用于卫星方向，
        /// 但必须保留其真实精度，不能把任意缓存坐标都标成“实时”。
        var horizontalAccuracyMeters: Double
        var measuredAt: Date
        /// 是否为假定坐标（未获得真实定位 → 档案标 OBSERVER: ASSUMED）。
        var assumed: Bool
    }

    /// 默认坐标：北京。未授权定位时使用。
    static let fallback = Coordinates(
        latitude: 39.9042,
        longitude: 116.4074,
        altitudeMeters: 50,
        horizontalAccuracyMeters: .infinity,
        measuredAt: .distantPast,
        assumed: true
    )

    @Published private(set) var coordinates: Coordinates = ObserverLocation.fallback
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // 完整精度获准时争取百米级；用户主动保留“近似位置”时系统仍会维持
        // reduced accuracy，界面随后按实际 horizontalAccuracy 明确提示。
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func request() {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break // 保持 fallback
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied
                    || manager.authorizationStatus == .restricted {
            // 撤销权限后立即停止沿用上一份真实坐标。界面与轨道引擎会同步回到
            // 明确标注的北京假定坐标，和应用内隐私说明保持一致。
            coordinates = Self.fallback
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = Self.bestUsableLocation(from: locations, now: Date()) else { return }
        coordinates = Coordinates(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            altitudeMeters: loc.verticalAccuracy >= 0 ? loc.altitude : 0,
            horizontalAccuracyMeters: loc.horizontalAccuracy,
            measuredAt: loc.timestamp,
            assumed: false
        )
    }

    /// `requestLocation()` 可能先交付缓存结果。只接受最近五分钟且误差半径不超过
    /// 10km 的坐标，并优先选择批次中精度最高、时间更新的样本。10km 对 500km
    /// 距离目标约等于 1.15° 的最坏视差，仍落在捕获核心之外但进入迟滞范围内；
    /// 正常完整精度通常远好于此门槛。
    nonisolated static func bestUsableLocation(
        from locations: [CLLocation],
        now: Date,
        maximumAge: TimeInterval = 300,
        maximumHorizontalAccuracy: CLLocationAccuracy = 10_000
    ) -> CLLocation? {
        locations
            .filter { location in
                CLLocationCoordinate2DIsValid(location.coordinate)
                    && location.horizontalAccuracy >= 0
                    && location.horizontalAccuracy <= maximumHorizontalAccuracy
                    && abs(now.timeIntervalSince(location.timestamp)) <= maximumAge
            }
            .min { lhs, rhs in
                if lhs.horizontalAccuracy == rhs.horizontalAccuracy {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.horizontalAccuracy < rhs.horizontalAccuracy
            }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 保持 fallback，不打扰用户
    }

    var isDeniedOrRestricted: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
}
