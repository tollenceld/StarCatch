import CoreGraphics
import CoreMotion
import simd
import XCTest
@testable import StarCatch
import SatelliteKit

final class OrbitTests: XCTestCase {
    private static let store = CatalogStore()

    func testCatalogLoads() throws {
        let store = Self.store
        XCTAssertGreaterThan(store.objects.count, 15_000, "应载入完整的离线活动轨道快照")
        XCTAssertEqual(store.satellites.count, store.objects.count)
        XCTAssertEqual(Set(store.objects.map(\.id)).count, store.objects.count)
        XCTAssertEqual(Set(store.objects.map(\.noradId)).count, store.objects.count)
        for category in CatalogCategory.allCases {
            XCTAssertGreaterThan(
                store.categoryCounts[category, default: 0],
                0,
                "\(category.title) 分类不应为空"
            )
        }
    }

    func testGeneratedCatalogKeepsCuratedIdentities() {
        let store = Self.store
        XCTAssertEqual(store.objectsByID["iss"]?.noradId, 25_544)
        XCTAssertEqual(store.objectsByID["himawari9"]?.category, .observation)
        XCTAssertEqual(store.objectsByID["starlink-32000"]?.category, .network)
        XCTAssertTrue(store.objectsByID["starlink-32000"]?.isStarlink == true)
    }

    func testStarlinkDensityUsesStableRepresentativesWithoutDroppingCatalogData() {
        let store = Self.store
        let starlink = store.objects.filter(\.isStarlink)
        let display = SkySession.makeDisplaySample(from: store.objects, starlinkDivisor: 8)
        let displayedStarlink = display.filter(\.isStarlink)

        XCTAssertGreaterThan(starlink.count, 8_000)
        XCTAssertLessThan(displayedStarlink.count, starlink.count / 4)
        XCTAssertTrue(display.contains(where: { $0.id == "starlink-32000" }))
        XCTAssertEqual(store.objects(matching: .all).count, store.objects.count)
    }

    func testCatalogFiltersAreCompleteAndDisjoint() {
        let store = Self.store
        let categorySets = CatalogCategory.allCases.map { category in
            Set(store.objects(matching: CatalogFilter(rawValue: category.rawValue)!).map(\.id))
        }
        XCTAssertEqual(categorySets.reduce(0) { $0 + $1.count }, store.objects.count)
        XCTAssertEqual(Set(categorySets.flatMap { $0 }).count, store.objects.count)
        XCTAssertEqual(store.objects(matching: .all).count, store.objects.count)
    }

    func testGeneratedElementsWereFreshAtPackaging() throws {
        let store = Self.store
        let generatedAt = try XCTUnwrap(store.generatedAt)
        for object in store.objects where object.category != .legacy {
            let age = generatedAt.timeIntervalSince(object.elementEpoch)
            XCTAssertGreaterThanOrEqual(age, -4 * 86_400, "预测元素不应领先打包时间超过 4 天")
            XCTAssertLessThanOrEqual(age, 14 * 86_400, "活动目标元素在打包时不应超过 14 天")
        }
    }

    /// ISS：TLE 历元附近推算的高度/速度应在 LEO 合理区间。
    func testISSPhysicalPlausibility() throws {
        let store = Self.store
        guard let sat = store.satellites["iss"] else {
            return XCTFail("ISS 缺失")
        }
        let eci: Vector = try sat.position(minsAfterEpoch: 0)
        let vel: Vector = try sat.velocity(minsAfterEpoch: 0)
        let altitude = eci.magnitude() - 6378.137
        let speed = vel.magnitude()
        XCTAssert((350...460).contains(altitude), "ISS 高度应约 420km，实得 \(altitude)")
        XCTAssert((7.4...7.9).contains(speed), "ISS 速度应约 7.66km/s，实得 \(speed)")
    }

    /// GEO 卫星 Himawari-9（东经 140.7 度）：从东京看仰角应显著为正、方位大致朝南，
    /// 且一小时后 az/el 几乎不变 —— 静止轨道的定义性检验。
    func testGeostationaryIsStationary() throws {
        let store = Self.store
        guard let sat = store.satellites["himawari9"] else {
            return XCTFail("Himawari-9 缺失")
        }
        let tokyo = LatLonAlt(35.68, 139.69, 0)

        let t0 = try sat.topPosition(minsAfterEpoch: 0, observer: tokyo)
        let t1 = try sat.topPosition(minsAfterEpoch: 60, observer: tokyo)

        XCTAssert(t0.elev > 30, "东京看 Himawari-9 仰角应大于 30 度，实得 \(t0.elev)")
        XCTAssert(abs(t0.azim - t1.azim) < 1.5, "GEO 方位角一小时漂移应小于 1.5 度")
        XCTAssert(abs(t0.elev - t1.elev) < 1.5, "GEO 仰角一小时漂移应小于 1.5 度")
        XCTAssert((150...210).contains(t0.azim), "从东京看东经 140.7 度 GEO 应大致朝南，实得 \(t0.azim)")
    }

    /// 角度插值的正负 pi 回绕。
    func testLerpAngleWraparound() {
        let mid = EphemerisEngine.lerpAngle(3.0, -3.0, 0.5)
        XCTAssertEqual(abs(mid), Double.pi, accuracy: 0.15)
    }

    func testProjectionScreenDirectionPointsRightForEastTarget() throws {
        let projection = Projection(
            pointing: Pointing(azimuth: 0, elevation: 0, roll: 0),
            screenSize: CGSize(width: 390, height: 844)
        )
        let direction = try XCTUnwrap(
            projection.screenDirection(azimuth: .pi / 2, elevation: 0)
        )
        XCTAssertGreaterThan(direction.vector.dx, 0.99)
        XCTAssertEqual(direction.vector.dy, 0, accuracy: 0.01)
    }

    func testProjectionScreenDirectionPointsUpForHigherTarget() throws {
        let projection = Projection(
            pointing: Pointing(azimuth: 0, elevation: 0, roll: 0),
            screenSize: CGSize(width: 390, height: 844)
        )
        let direction = try XCTUnwrap(
            projection.screenDirection(azimuth: 0, elevation: .pi / 4)
        )
        XCTAssertEqual(direction.vector.dx, 0, accuracy: 0.01)
        XCTAssertLessThan(direction.vector.dy, -0.99)
    }

    func testFieldMagnificationUsesOpticalFOVAndScreenScale() throws {
        let size = CGSize(width: 390, height: 844)
        let pointing = Pointing(azimuth: 0, elevation: 0, roll: 0)
        let base = Projection(pointing: pointing, screenSize: size)
        let tele = Projection(
            pointing: pointing,
            screenSize: size,
            verticalFOV: Projection.verticalFOV(forMagnification: 2)
        )
        let basePoint = try XCTUnwrap(base.project(azimuth: 5 * .pi / 180, elevation: 0)).point
        let telePoint = try XCTUnwrap(tele.project(azimuth: 5 * .pi / 180, elevation: 0)).point
        let centerX = size.width / 2
        XCTAssertEqual(
            telePoint.x - centerX,
            2 * (basePoint.x - centerX),
            accuracy: 0.01
        )
        XCTAssertLessThan(tele.verticalFOV, base.verticalFOV)
    }

    func testLongFocusTightensCaptureAngle() {
        let angle = 2 * Double.pi / 180
        XCTAssertGreaterThan(
            Projection.captureAngle(for: angle, magnification: 4),
            angle * 3.9
        )
    }

    func testLockedMarkerCrossesScreenEdgeContinuously() throws {
        let bounds = CGRect(x: 22, y: 72, width: 346, height: 660)
        let justInside = try XCTUnwrap(TargetRelationshipGeometry.marker(
            projectedPoint: CGPoint(x: 367, y: 360),
            direction: CGVector(dx: 1, dy: 0),
            inside: bounds
        ))
        let justOutside = try XCTUnwrap(TargetRelationshipGeometry.marker(
            projectedPoint: CGPoint(x: 369, y: 360),
            direction: CGVector(dx: 1, dy: 0),
            inside: bounds
        ))

        XCTAssertEqual(justInside.point.x, 367, accuracy: 0.001)
        XCTAssertEqual(justOutside.point.x, bounds.maxX, accuracy: 0.001)
        XCTAssertLessThanOrEqual(abs(justOutside.point.x - justInside.point.x), 1.01)
        XCTAssertTrue(justOutside.isOffscreen)
        XCTAssertEqual(justOutside.edgeProgress, 1, accuracy: 0.001)
    }

    func testLockedMarkerUsesIncompleteEdgeStructureForOffscreenDirection() throws {
        let bounds = CGRect(x: 22, y: 72, width: 346, height: 660)
        let marker = try XCTUnwrap(TargetRelationshipGeometry.marker(
            projectedPoint: nil,
            direction: CGVector(dx: -1, dy: 0.25),
            inside: bounds
        ))

        XCTAssertTrue(marker.isOffscreen)
        XCTAssertEqual(marker.edgeProgress, 1, accuracy: 0.001)
        XCTAssertEqual(marker.point.x, bounds.minX, accuracy: 0.001)
        XCTAssertGreaterThan(marker.inward.dx, 0)
    }

    func testSignalConnectionStopsAtArchiveWithoutCrossingText() throws {
        let archive = CGRect(x: 20, y: 200, width: 160, height: 350)
        let target = CGPoint(x: 350, y: 430)
        let connection = try XCTUnwrap(
            TargetRelationshipGeometry.connection(from: target, to: archive)
        )

        XCTAssertEqual(connection.archiveAnchor.x, archive.maxX, accuracy: 0.001)
        XCTAssertEqual(connection.archiveAnchor.y, target.y, accuracy: 0.001)
        for step in 0 ..< 10 {
            let progress = CGFloat(step) / 10
            let sample = CGPoint(
                x: connection.start.x
                    + (connection.archiveAnchor.x - connection.start.x) * progress,
                y: connection.start.y
                    + (connection.archiveAnchor.y - connection.start.y) * progress
            )
            XCTAssertFalse(archive.contains(sample))
        }
    }

    func testTargetBehindArchiveBecomesShortOuterNotch() throws {
        let archive = CGRect(x: 20, y: 200, width: 160, height: 350)
        let connection = try XCTUnwrap(TargetRelationshipGeometry.connection(
            from: CGPoint(x: 100, y: 300),
            to: archive
        ))

        XCTAssertTrue(connection.targetOccludedByArchive)
        XCTAssertEqual(connection.length, 11, accuracy: 0.001)
        XCTAssertFalse(archive.contains(connection.start))
        XCTAssertTrue(archive.contains(CGPoint(
            x: connection.archiveAnchor.x + 0.01,
            y: connection.archiveAnchor.y
        )))
    }

    func testMotionConfidenceRequiresCalibratedTrueNorth() {
        XCTAssertEqual(
            MotionPointingProvider.confidence(usingTrueNorth: true, magneticAccuracy: .high),
            .trueNorth
        )
        XCTAssertEqual(
            MotionPointingProvider.confidence(usingTrueNorth: true, magneticAccuracy: .low),
            .uncalibrated
        )
        XCTAssertEqual(
            MotionPointingProvider.confidence(usingTrueNorth: false, magneticAccuracy: .high),
            .uncalibrated
        )
    }

    func testMotionBackCameraBoreMapsToTrueNorthHorizon() {
        let deviceToWorld = simd_quatd(
            angle: -.pi / 2,
            axis: SIMD3<Double>(0, 1, 0)
        )
        let pointing = MotionPointingProvider.pointing(from: deviceToWorld)
        XCTAssertEqual(pointing.azimuth, 0, accuracy: 0.001)
        XCTAssertEqual(pointing.elevation, 0, accuracy: 0.001)
    }
}

extension OrbitTests {
    /// 辅助：打印当前北京视角所有对象 az/el（供模拟器调试指向）。
    func printCurrentSkyForDebug() throws {
        let store = Self.store
        let beijing = LatLonAlt(39.9042, 116.4074, 0.05)
        let jd = Date().timeIntervalSince1970 / 86400.0 + 2440587.5
        print("=== SKY @ Beijing now ===")
        for obj in store.objects {
            guard let sat = store.satellites[obj.id] else { continue }
            if let topo = try? sat.topPosition(julianDays: jd, observer: beijing) {
                if topo.elev > 0 {
                    print(String(format: "%-16s az %6.1f  el %5.1f", (obj.id as NSString).utf8String!, topo.azim, topo.elev))
                }
            }
        }
    }
}
