import XCTest
import SatelliteKit
import simd
import CoreLocation
@testable import StarCatch

@MainActor
final class ObservationSceneTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private let size = CGSize(width: 393, height: 852)
    private static let catalog = CatalogStore()

    func testGlobalEndpointMatchesExistingProjectionAtArbitraryOrientationAndZoom() {
        let geometry = SkyOverviewView.GlobeGeometry(center: CGPoint(x: 180, y: 360), radius: 210,
            orientation: SkyOverviewView.orientation(yaw: 1.2, pitch: -0.7, roll: 0.3))
        let camera = ObservationCameraState(size: size, geometry: geometry, zoom: 1.26, localProgress: 0,
            observer: ObserverLocation.fallback, pointing: .initial, observation: date)
        for radius in [6800.0, 20000, 42164] {
            for angle in stride(from: 0.0, to: 2 * .pi, by: 0.2) {
                let position = simd_normalize(SIMD3(cos(angle), sin(angle), 0.3)) * radius
                let old = SkyOverviewView.project(orbitalPosition: position, center: geometry.center,
                    radius: geometry.radius, orientation: geometry.orientation, zoom: 1.26)!
                let new = camera.project(position)!
                XCTAssertEqual(new.point.x, old.point.x, accuracy: 0.000001)
                XCTAssertEqual(new.point.y, old.point.y, accuracy: 0.000001)
            }
        }
    }

    func testLocalEndpointMatchesSkyForPolesWrapRollAndZenith() {
        for latitude in [-89.9, -45, 0, 31.2304, 89.9] {
            for longitude in [-179.99, 121.4737, 179.99] {
                var observer = ObserverLocation.fallback
                observer.latitude = latitude; observer.longitude = longitude
                for elevation in [-Double.pi / 2, -0.3, 0.5, Double.pi / 2] {
                    let pointing = Pointing(azimuth: -3.13, elevation: elevation, roll: 0.37)
                    let camera = ObservationCameraState(size: size,
                        geometry: SkyOverviewView.globeGeometry(in: size), zoom: 0.82,
                        localProgress: 1, observer: observer, pointing: pointing, observation: date)
                    let projection = Projection(pointing: pointing, screenSize: size)
                    for delta in [-0.2, 0, 0.2] {
                        let az = pointing.azimuth + delta
                        let el = max(-Double.pi / 2, min(Double.pi / 2, elevation + delta))
                        let eph = ephemeris(camera: camera, azimuth: az, elevation: el)
                        guard let expected = projection.project(azimuth: az, elevation: el),
                              let actual = camera.project(eph) else { XCTFail("Missing endpoint"); continue }
                        XCTAssertEqual(actual.point.x, expected.point.x, accuracy: 0.001)
                        XCTAssertEqual(actual.point.y, expected.point.y, accuracy: 0.001)
                    }
                }
            }
        }
    }

    func testProjectionHasNoNaNOrExplodingVisiblePointsThroughDescent() {
        for progress in stride(from: 0.0, through: 1, by: 0.005) {
            let camera = ObservationCameraState(size: size, geometry: SkyOverviewView.globeGeometry(in: size),
                zoom: 2.2, localProgress: progress, observer: ObserverLocation.fallback, pointing: .initial, observation: date)
            for axis in [SIMD3<Double>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
                if let sample = camera.project(axis * 6900) {
                    XCTAssertTrue(sample.point.x.isFinite && sample.point.y.isFinite)
                    XCTAssertTrue((0...1).contains(sample.visibility))
                }
            }
        }
    }

    func testFastStartupCompletesOnceInAboutTwoPointSixSeconds() {
        var state = ObservationEstablishment()
        var observer = ObserverLocation.fallback
        observer.assumed = false
        var confirmations = 0
        for tick in 0...90 {
            if state.advance(at: Double(tick) / 30, active: true, sessionReady: true,
                frameReady: true, locating: false, coordinates: observer) { confirmations += 1 }
        }
        XCTAssertEqual(state.phase, .live)
        XCTAssertEqual(state.elapsed, 2.6, accuracy: 0.08)
        XCTAssertEqual(confirmations, 1)
    }

    func testDelayedFrameDoesNotReplayEarthAndPausedTimeDoesNotAdvance() {
        var state = ObservationEstablishment()
        for tick in 0...120 {
            _ = state.advance(at: Double(tick) / 30, active: true, sessionReady: true,
                frameReady: false, locating: false, coordinates: ObserverLocation.fallback)
        }
        XCTAssertEqual(state.phase, .network)
        XCTAssertEqual(state.reveal.land, 1)
        XCTAssertEqual(state.reveal.satellites, 0)
        state.pause()
        _ = state.advance(at: 100, active: true, sessionReady: true, frameReady: true,
            locating: false, coordinates: ObserverLocation.fallback)
        XCTAssertEqual(state.elapsed, 4, accuracy: 0.001)
        for tick in 1...65 {
            _ = state.advance(at: 100 + Double(tick) / 30, active: true, sessionReady: true,
                frameReady: true, locating: false, coordinates: ObserverLocation.fallback)
        }
        XCTAssertEqual(state.phase, .live)
        XCTAssertEqual(state.observer?.assumed, true)
    }

    func testLocationWaitIsBoundedAndAssumedPositionNeverConfirms() {
        var state = ObservationEstablishment()
        for tick in 0...120 {
            XCTAssertFalse(state.advance(at: Double(tick) / 30, active: true, sessionReady: true,
                frameReady: true, locating: true, coordinates: ObserverLocation.fallback))
        }
        XCTAssertEqual(state.phase, .live)
        XCTAssertLessThan(state.elapsed, 3.6)
    }

    func testReducedMotionAndUnavailableDataDoNotTrapTheUser() {
        var reduced = ObservationEstablishment()
        for tick in 0...10 {
            _ = reduced.advance(at: Double(tick) / 30, active: true, sessionReady: true, frameReady: true,
                locating: false, coordinates: ObserverLocation.fallback, reduced: true)
        }
        XCTAssertTrue(reduced.isComplete)
        XCTAssertEqual(reduced.rotation, 0)
        var timeout = ObservationEstablishment()
        _ = timeout.advance(at: 0, active: true, sessionReady: true, frameReady: false,
            locating: false, coordinates: ObserverLocation.fallback)
        _ = timeout.advance(at: 8, active: true, sessionReady: true, frameReady: false,
            locating: false, coordinates: ObserverLocation.fallback)
        XCTAssertEqual(timeout.phase, .live)
        XCTAssertEqual(SkyObservationIssue.resolve(availability: .manual, authorization: .notDetermined,
            locating: false, assumed: true, accuracy: .infinity, confidence: .manual,
            orbitAge: 0, orbitFrameReady: false), .orbitPreparing)
    }

    func testFailureIsTerminalAndNeverConfirms() {
        var state = ObservationEstablishment()
        XCTAssertFalse(state.advance(at: 0, active: true, sessionReady: true, frameReady: false,
            locating: false, coordinates: ObserverLocation.fallback, failed: true))
        XCTAssertEqual(state.phase, .failed)
        XCTAssertFalse(state.advance(at: 10, active: true, sessionReady: true, frameReady: true,
            locating: false, coordinates: ObserverLocation.fallback))
        XCTAssertEqual(state.phase, .failed)
    }

    func testReturnClockUsesElapsedForegroundTimeNotNominalRefreshRate() {
        XCTAssertEqual(SkyClock.elapsedFrameTime(previous: 10, current: 10.1, fallback: 1.0 / 120),
                       0.1, accuracy: 0.000001)
        XCTAssertEqual(SkyClock.elapsedFrameTime(previous: nil, current: 100, fallback: 1.0 / 30),
                       1.0 / 30, accuracy: 0.000001)
    }

    func testLateAccurateLocationLocksOnceAndFreezesThePresentationVersion() {
        var state = ObservationEstablishment()
        var measured = ObserverLocation.fallback
        measured.latitude = -33.86; measured.longitude = 151.21
        measured.assumed = false; measured.measuredAt = date; measured.horizontalAccuracyMeters = 3000
        var confirmations = 0
        for tick in 0...80 {
            let coordinates = tick < 48 ? ObserverLocation.fallback : measured
            if state.advance(at: Double(tick) / 30, active: true, sessionReady: true,
                frameReady: true, locating: tick < 48, coordinates: coordinates) { confirmations += 1 }
        }
        XCTAssertEqual(state.observer, measured)
        measured.latitude = 0
        _ = state.advance(at: 3, active: true, sessionReady: true, frameReady: true,
            locating: false, coordinates: measured)
        XCTAssertEqual(state.observer?.latitude, -33.86)
        XCTAssertEqual(confirmations, 1)
    }

    func testObserverHoldDefersUpdatesAndReleasesLatestMeasurement() {
        let observer = ObserverLocation()
        let manager = CLLocationManager()
        observer.holdForPresentation()
        for latitude in [10.0, 20.0] {
            let location = CLLocation(coordinate: .init(latitude: latitude, longitude: 120), altitude: 0,
                horizontalAccuracy: 100, verticalAccuracy: 100, timestamp: Date())
            observer.locationManager(manager, didUpdateLocations: [location])
        }
        XCTAssertTrue(observer.coordinates.assumed)
        observer.releasePresentationHold()
        XCTAssertEqual(observer.coordinates.latitude, 20)
        XCTAssertFalse(observer.coordinates.assumed)
        observer.releasePresentationHold()
        XCTAssertEqual(observer.coordinates.latitude, 20)
    }

    func testLocalEndpointMatchesVisibilityAndCustomFieldOfView() {
        let pointing = Pointing(azimuth: 0, elevation: 0, roll: -.pi / 2)
        let fov = Projection.verticalFOV(forMagnification: 0.52)
        let camera = ObservationCameraState(size: size, geometry: SkyOverviewView.globeGeometry(in: size),
            zoom: 2.2, localProgress: 1, observer: ObserverLocation.fallback, pointing: pointing,
            observation: date, verticalFOV: fov)
        let projection = Projection(pointing: pointing, screenSize: size, verticalFOV: fov)
        for degrees in [0.0, 45, 60, 65, 69, 71, 90, 180] {
            let az = degrees * .pi / 180
            let eph = ephemeris(camera: camera, azimuth: az, elevation: 0.01)
            let expected = projection.project(azimuth: az, elevation: 0.01)
            let actual = camera.project(eph)
            XCTAssertEqual(actual == nil, expected == nil)
            if let actual, let expected {
                XCTAssertEqual(actual.point.x, expected.point.x, accuracy: 0.001)
                XCTAssertEqual(actual.point.y, expected.point.y, accuracy: 0.001)
                XCTAssertEqual(actual.visibility, expected.visibility, accuracy: 0.001)
                XCTAssertGreaterThan(actual.depth, 0)
            }
        }
    }

    func testSphereSilhouetteRemainsFiniteAndClippedAcrossArbitraryReturn() {
        for progress in stride(from: 0.0, through: 1, by: 0.01) {
            let geometry = SkyOverviewView.GlobeGeometry(center: CGPoint(x: 195, y: 380), radius: 230,
                orientation: SkyOverviewView.orientation(yaw: -2.6, pitch: 1.4, roll: -0.8))
            let camera = ObservationCameraState(size: size, geometry: geometry, zoom: 2.2,
                localProgress: progress, observer: ObserverLocation.fallback, pointing: .initial, observation: date)
            let bounds = camera.surfaceOutline().boundingRect
            guard !bounds.isNull else { continue }
            XCTAssertTrue(bounds.minX.isFinite && bounds.minY.isFinite)
            XCTAssertLessThanOrEqual(bounds.width, size.width + 32.001)
            XCTAssertLessThanOrEqual(bounds.height, size.height + 32.001)
        }
    }

    func testRealSceneFrameKeepsIDsAndOnlyReadsPreparedEphemerides() async throws {
        let session = SkySession(catalog: Self.catalog)
        let recordsBefore = session.log.entries.count
        XCTAssertTrue(session.sceneFrame(at: date).targets.isEmpty)
        XCTAssertFalse(session.ephemeris.hasUsableFrame)
        session.start()
        defer { session.stop() }
        for _ in 0..<300 where !session.ephemeris.hasUsableFrame {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(session.ephemeris.hasUsableFrame)
        let global = session.sceneFrame(at: date)
        let local = session.sceneFrame(at: date, includeLocal: true)
        XCTAssertEqual(global.observerVersion, local.observerVersion)
        XCTAssertLessThanOrEqual(global.targets.count, 4600)
        XCTAssertFalse(global.targets.isEmpty)
        XCTAssertTrue(Set(global.targets.map { $0.object.id }).isSubset(of: Set(local.targets.map { $0.object.id })))
        let indexed = Dictionary(uniqueKeysWithValues: local.targets.map { ($0.object.id, $0) })
        for target in global.targets {
            XCTAssertEqual(target.object.id, target.ephemeris.objectId)
            XCTAssertEqual(target.ephemeris.orbitalPosition, indexed[target.object.id]?.ephemeris.orbitalPosition)
            XCTAssertEqual(target.revealOrder, indexed[target.object.id]?.revealOrder)
        }
        var changed = ObserverLocation.fallback
        changed.latitude = -33.86; changed.longitude = 151.21
        session.ephemeris.updateObserver(changed)
        XCTAssertFalse(session.ephemeris.hasUsableFrame)
        for _ in 0..<300 where !session.ephemeris.hasUsableFrame {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(session.ephemeris.frameObserver, changed)
        XCTAssertEqual(session.log.entries.count, recordsBefore)
    }

    func testHistoricalReturnMatchesByIDAndDoesNotCutThroughEarth() throws {
        let objects = Array(Self.catalog.objects.prefix(2))
        func frame(reversed: Bool, angle: Double) -> ObservationSceneFrame {
            let targets = objects.enumerated().map { index, object in
                let phase = angle + Double(index)
                return ObservationSceneFrame.Target(object: object,
                    ephemeris: Ephemeris(objectId: object.id, azimuth: phase, elevation: 0.5,
                        rangeKm: 1200, altitudeKm: 600, velocityKmS: 7,
                        orbitalPosition: SIMD3(cos(phase), sin(phase), 0) * 6900),
                    isOverview: true, revealOrder: Double(index) / 2)
            }
            return ObservationSceneFrame(observation: date.addingTimeInterval(angle * 100),
                observer: ObserverLocation.fallback, pointing: .initial,
                targets: reversed ? targets.reversed() : targets)
        }
        let old = frame(reversed: true, angle: 0)
        let live = frame(reversed: false, angle: .pi)
        let origin = live.returning(from: old, progress: 0)
        XCTAssertEqual(origin.targets.first?.ephemeris.orbitalPosition, old.targets.last?.ephemeris.orbitalPosition)
        for target in live.returning(from: old, progress: 0.5).targets {
            XCTAssertEqual(simd_length(target.ephemeris.orbitalPosition), 6900, accuracy: 0.001)
        }
        XCTAssertEqual(live.returning(from: old, progress: 1).targets.first?.ephemeris.orbitalPosition,
                       live.targets.first?.ephemeris.orbitalPosition)
    }

    private func ephemeris(camera: ObservationCameraState, azimuth: Double, elevation: Double) -> Ephemeris {
        let enu = SIMD3(cos(elevation) * sin(azimuth), cos(elevation) * cos(azimuth), sin(elevation))
        let position = camera.observerPosition + (camera.east * enu.x + camera.north * enu.y + camera.up * enu.z) * 1200
        return Ephemeris(objectId: "test", azimuth: azimuth, elevation: elevation,
            rangeKm: 1200, altitudeKm: 600, velocityKmS: 7, orbitalPosition: position)
    }
}
