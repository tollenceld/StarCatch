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

    func testCatalogFiltersAreSelectiveAndCountedFromTheSameSource() {
        let store = Self.store
        XCTAssertEqual(store.objects(matching: .all).count, store.objects.count)
        for filter in CatalogFilter.allCases {
            let objects = store.objects(matching: filter)
            XCTAssertFalse(objects.isEmpty, "\(filter.title) 不应为空")
            if filter != .all {
                XCTAssertLessThan(objects.count, store.objects.count, "\(filter.title) 应真正缩小目录")
            }
            XCTAssertEqual(store.filterCounts[filter], objects.count)
            XCTAssertGreaterThanOrEqual(
                store.filterReadableCounts[filter, default: 0],
                3,
                "\(filter.title) 至少应保留数个有任务资料的可探索目标"
            )
            XCTAssertTrue(
                objects.contains(where: \CatalogObject.hasMeaningfulProfile),
                "\(filter.title) 不应只剩没有可读资料的轨道编号"
            )
        }
        for filter in CatalogFilter.allCases where filter != .all {
            XCTAssertGreaterThanOrEqual(
                store.objects(matching: filter).count,
                80,
                "\(filter.title) 需要足够形成基础观测密度的真实对象"
            )
        }
        XCTAssertGreaterThan(store.objects(matching: .starlink).count, 8_000)
    }

    func testFilterHierarchyCoversEveryConcreteLensExactlyOnce() {
        let groupedFilters = CatalogFilterGroup.allCases.flatMap(\.filters)
        XCTAssertEqual(groupedFilters.count, CatalogFilter.allCases.count)
        XCTAssertEqual(Set(groupedFilters), Set(CatalogFilter.allCases))
        for group in CatalogFilterGroup.allCases {
            XCTAssertFalse(group.filters.isEmpty, "\(group.title) 需要至少一个二级筛选")
            XCTAssertTrue(group.filters.allSatisfy { $0.group == group })
        }
    }

    func testFrequentLensesStaySmallExplicitAndRestorable() {
        let lenses = CatalogFilter.frequentLenses
        XCTAssertEqual(lenses.first, .all)
        XCTAssertLessThanOrEqual(lenses.count, 4)
        XCTAssertEqual(Set(lenses).count, lenses.count)
        XCTAssertTrue(lenses.allSatisfy { CatalogFilter.allCases.contains($0) })
    }

    func testTaskLensesDoNotLeakUnrelatedCuratedObjects() throws {
        let store = Self.store
        let iss = try XCTUnwrap(store.objectsByID["iss"])
        let himawari = try XCTUnwrap(store.objectsByID["himawari9"])
        let tdrs = try XCTUnwrap(store.objectsByID["tdrs3"])
        let lageos = try XCTUnwrap(store.objectsByID["lageos1"])

        XCTAssertTrue(CatalogFilter.humanScience.includes(iss))
        XCTAssertFalse(CatalogFilter.humanScience.includes(himawari))
        XCTAssertFalse(CatalogFilter.humanScience.includes(tdrs))
        XCTAssertTrue(CatalogFilter.orbitalHeritage.includes(tdrs))
        XCTAssertTrue(CatalogFilter.orbitalHeritage.includes(lageos))
        XCTAssertFalse(CatalogFilter.orbitalHeritage.includes(himawari))
    }

    func testMajorConstellationFamiliesAreDistinguished() {
        let store = Self.store
        for family in CatalogFamily.allCases {
            XCTAssertTrue(
                store.objects.contains(where: { $0.family == family }),
                "\(family.title) 应能从离线目录中辨认"
            )
        }
        XCTAssertEqual(store.objectsByID["starlink-32000"]?.family, .starlink)
        XCTAssertEqual(
            store.objects.first(where: { $0.name.uppercased().contains("ONEWEB") })?.family,
                .oneweb
        )
        XCTAssertEqual(
            store.familyCounts[.starlink],
            store.objectsByFamily[.starlink]?.count
        )
    }

    func testMainSkySamplesOnlyRealObjectsAndKeepsSmallFiltersDense() {
        let store = Self.store
        for filter in CatalogFilter.allCases where filter != .all {
            let matching = store.objects(matching: filter)
            let displayed = SkySession.makeDisplaySample(
                from: matching,
                starlinkDivisor: 8
            )
            let matchingIDs = Set(matching.map(\.id))

            XCTAssertTrue(
                displayed.allSatisfy { matchingIDs.contains($0.id) },
                "\(filter.title) 的每个显示点都必须来自真实筛选结果"
            )
            XCTAssertGreaterThanOrEqual(
                displayed.count,
                80,
                "\(filter.title) 不应在显示采样后变成空天空"
            )
            if matching.count <= 1_400 {
                XCTAssertEqual(
                    displayed.map(\.id),
                    matching.map(\.id),
                    "小型筛选结果不应再次抽稀"
                )
            }
        }
    }

    func testFeaturedArchiveUsesRealCatalogObjects() {
        let store = Self.store
        let featured = store.objects.filter(\.isFeatured)
        let individuallyEditable = store.objects.filter { $0.family == nil }

        XCTAssertEqual(featured.count, individuallyEditable.count)
        XCTAssertTrue(featured.allSatisfy { $0.story != nil })
        XCTAssertTrue(featured.allSatisfy { $0.family == nil })
        XCTAssertTrue(featured.contains(where: { $0.noradId == 5 }))
        XCTAssertTrue(featured.contains(where: { $0.noradId == 20_580 }))
        XCTAssertTrue(featured.contains(where: { $0.noradId == 49_260 }))
        XCTAssertTrue(featured.contains(where: { $0.noradId == 54_754 }))
        XCTAssertFalse(featured.contains(where: { $0.noradId == 44_714 }))
        XCTAssertGreaterThan(featured.count, 3_500)
    }

    func testCompiledMarkdownKnowledgeLibraryIsPackagedAndReadable() throws {
        let store = Self.store
        XCTAssertTrue(
            SatelliteStoryCatalog.diagnostics.isEmpty,
            SatelliteStoryCatalog.diagnostics.joined(separator: "\n")
        )
        XCTAssertEqual(
            SatelliteStoryCatalog.storyCount,
            store.objects.filter { $0.family == nil }.count
        )
        XCTAssertEqual(
            SatelliteStoryCatalog.familyStoryCount,
            CatalogFamily.allCases.count
        )
        XCTAssertNil(SatelliteStoryCatalog.story(forNORAD: 44_714))
        XCTAssertTrue(store.objects.allSatisfy { $0.deepArchiveStory != nil })

        let hubble = try XCTUnwrap(SatelliteStoryCatalog.story(forNORAD: 20_580))
        XCTAssertEqual(hubble.program, "HUBBLE SPACE TELESCOPE")
        XCTAssertEqual(hubble.organization, "NASA · ESA")
        XCTAssertTrue(hubble.lead.contains("大气层之外"))
        XCTAssertGreaterThanOrEqual(hubble.chapters.count, 2)
        XCTAssertGreaterThanOrEqual(hubble.milestones.count, 3)
        XCTAssertGreaterThanOrEqual(hubble.facts.count, 3)
        XCTAssertTrue(hubble.sources.contains("NASA Hubble Mission"))

        let generated = try XCTUnwrap(SatelliteStoryCatalog.story(forNORAD: 43_226))
        XCTAssertEqual(generated.program, "GOES 17")
        XCTAssertTrue(generated.lead.contains("地球同步轨道"))
        XCTAssertGreaterThanOrEqual(generated.facts.count, 6)

        let starlink = try XCTUnwrap(store.objects.first(where: { $0.family == .starlink }))
        let starlinkArchive = try XCTUnwrap(starlink.deepArchiveStory)
        XCTAssertEqual(starlink.deepArchiveTitle, "STARLINK")
        XCTAssertEqual(starlinkArchive.program, "STARLINK CONSTELLATION")
        XCTAssertTrue(starlinkArchive.lead.contains("低轨宽带网络"))
        XCTAssertGreaterThanOrEqual(starlinkArchive.chapters.count, 2)

        let qianfan = try XCTUnwrap(store.objects.first(where: { $0.family == .qianfan }))
        XCTAssertEqual(qianfan.deepArchiveStory?.program, "千帆星座")
    }

    func testPackagedCatalogHasPlausiblePublicIdentifiers() {
        let store = Self.store
        XCTAssertTrue(store.source.contains("CelesTrak"))
        let invalid = store.objects.filter { object in
            guard object.noradId > 0, !object.name.isEmpty else { return true }
            let parts = object.cosparId.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].count == 4,
                  parts[0].allSatisfy(\.isNumber),
                  parts[1].count >= 4 else { return true }
            let launchNumber = parts[1].prefix(3)
            let piece = parts[1].dropFirst(3)
            return !launchNumber.allSatisfy(\.isNumber)
                || piece.isEmpty
                || !piece.allSatisfy { $0.isASCII && $0.isLetter }
        }
        XCTAssertTrue(invalid.isEmpty, "存在异常公共标识：\(invalid.prefix(5).map(\.name))")
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

    func testMotionBackCameraBoreMapsToTrueEastHorizon() {
        let deviceToWorld = simd_quatd(
            angle: -.pi / 2,
            axis: SIMD3<Double>(1, 0, 0)
        )
        let pointing = MotionPointingProvider.pointing(from: deviceToWorld)
        XCTAssertEqual(pointing.azimuth, .pi / 2, accuracy: 0.001)
        XCTAssertEqual(pointing.elevation, 0, accuracy: 0.001)
    }

    func testMotionPointingRemainsFiniteAtZenith() {
        let deviceToWorld = simd_quatd(
            angle: .pi,
            axis: SIMD3<Double>(0, 1, 0)
        )
        let pointing = MotionPointingProvider.pointing(from: deviceToWorld)
        XCTAssertTrue(pointing.azimuth.isFinite)
        XCTAssertEqual(pointing.elevation, .pi / 2, accuracy: 0.001)
        XCTAssertTrue(pointing.roll.isFinite)
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
