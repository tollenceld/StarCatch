import Combine
import CoreLocation
import Foundation

/// 观察者坐标：一次性粗定位（km 级精度足够），拒绝/失败时 fallback 内置坐标。
final class ObserverLocation: NSObject, ObservableObject, CLLocationManagerDelegate {

    struct Coordinates: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var altitudeMeters: Double
        /// 是否为假定坐标（未获得真实定位 → 档案标 OBSERVER: ASSUMED）。
        var assumed: Bool
    }

    /// 默认坐标：北京。未授权定位时使用。
    static let fallback = Coordinates(latitude: 39.9042, longitude: 116.4074, altitudeMeters: 50, assumed: true)

    @Published private(set) var coordinates: Coordinates = ObserverLocation.fallback
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
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
        guard let loc = locations.last,
              loc.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(loc.coordinate) else { return }
        coordinates = Coordinates(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            altitudeMeters: loc.altitude,
            assumed: false
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 保持 fallback，不打扰用户
    }

    var isDeniedOrRestricted: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
}
