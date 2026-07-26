import XCTest
@testable import StarCatch
import SatelliteKit

/// 时间维度：观测时钟 + 任意时刻推算 + 过境预报。
@MainActor
final class TimeTests: XCTestCase {
    private static let store = CatalogStore()

    func testObservationLogPersistsRealSnapshotAndClears() throws {
        let suiteName = "StarCatchTests.ObservationLog.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let object = try XCTUnwrap(Self.store.objects.first)
        let observedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshot = Ephemeris(
            objectId: object.id,
            azimuth: 1.2,
            elevation: 0.5,
            rangeKm: 1_230,
            altitudeKm: 550,
            velocityKmS: 7.6,
            orbitalPosition: SIMD3(6_900, 0, 0)
        )

        let first = ObservationLog(defaults: defaults)
        first.record(
            objectId: object.id,
            catalog: Self.store,
            observationTime: observedAt,
            ephemeris: snapshot
        )

        let restored = ObservationLog(defaults: defaults)
        let entry = try XCTUnwrap(restored.entries.first)
        XCTAssertEqual(entry.objectId, object.id)
        XCTAssertEqual(entry.objectName, object.name)
        XCTAssertEqual(entry.observedAt, observedAt)
        XCTAssertEqual(entry.azimuth, snapshot.azimuth)
        XCTAssertEqual(entry.altitudeKm, snapshot.altitudeKm)
        XCTAssertEqual(entry.poetic, object.poetic)

        restored.clear()
        XCTAssertTrue(ObservationLog(defaults: defaults).entries.isEmpty)
    }

    func testArchiveAnimationFitsCaptureLifecycle() {
        let revealTotal = Motion.archiveRevealDuration
            + Double(Motion.archiveLineCount - 1) * Motion.archiveRevealStagger
        let dismissTotal = Motion.archiveDismissDuration
            + Double(Motion.archiveLineCount - 1) * Motion.archiveDismissStagger

        XCTAssertLessThan(revealTotal, 1.75, "档案显影应保持从容但不拖沓")
        XCTAssertLessThan(dismissTotal, Motion.releaseDuration)
        XCTAssertLessThan(Motion.releaseDuration, 1.2, "主动释放应清晰但不拖延")
    }

    func testSessionPublishesLatestManualPointingSample() async throws {
        let session = SkySession()
        let manual = try XCTUnwrap(session.manualProvider)

        manual.drag(translation: CGSize(width: 42, height: -18))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(session.pointing, manual.pointing)
    }

    func testCaptureEnvelopeRemainsNarrowAroundTheReticle() {
        let degrees = 180 / Double.pi
        XCTAssertEqual(CaptureStateMachine.enterAcquiring * degrees, 2.5, accuracy: 0.001)
        XCTAssertEqual(CaptureStateMachine.enterLocked * degrees, 1.25, accuracy: 0.001)
        XCTAssertEqual(CaptureStateMachine.exitAcquiring * degrees, 4, accuracy: 0.001)
    }

    func testAcquisitionProgressSurvivesHandJitterAndWaitsForConfirmation() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 1_000)
        let core = 1.0 * Double.pi / 180
        let jitter = 3.0 * Double.pi / 180

        capture.update(nearest: ("iss", core), now: start)
        for step in 1 ... 6 {
            capture.update(
                nearest: ("iss", core),
                trackedDistance: core,
                now: start.addingTimeInterval(Double(step) * 0.1)
            )
        }
        let established = capture.acquisitionProgress
        XCTAssertGreaterThan(established, 0.45)

        for step in 7 ... 10 {
            capture.update(
                nearest: ("iss", jitter),
                trackedDistance: jitter,
                now: start.addingTimeInterval(Double(step) * 0.1)
            )
        }
        XCTAssertTrue(capture.isAcquiring)
        XCTAssertGreaterThan(capture.acquisitionProgress, established - 0.08)

        for step in 11 ... 17 {
            capture.update(
                nearest: ("iss", core),
                trackedDistance: core,
                now: start.addingTimeInterval(Double(step) * 0.1)
            )
        }
        XCTAssertTrue(capture.isAcquiring)
        XCTAssertEqual(capture.acquisitionProgress, 1, accuracy: 0.001)
        XCTAssertTrue(capture.confirmAcquisition(now: start.addingTimeInterval(1.8)))
        XCTAssertEqual(capture.lockedObjectId, "iss")
    }

    func testAcquisitionNeedsClearSustainedExitBeforeReset() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 2_000)
        let core = 1.0 * Double.pi / 180
        let outside = 5.0 * Double.pi / 180

        capture.update(nearest: ("iss", core), now: start)
        for step in 1 ... 5 {
            capture.update(
                nearest: ("iss", core),
                trackedDistance: core,
                now: start.addingTimeInterval(Double(step) * 0.1)
            )
        }
        for step in 6 ... 12 {
            capture.update(
                nearest: nil,
                trackedDistance: outside,
                now: start.addingTimeInterval(Double(step) * 0.1)
            )
        }
        XCTAssertTrue(capture.isAcquiring, "短暂明显越界仍应保留退出迟滞")

        capture.update(
            nearest: nil,
            trackedDistance: outside,
            now: start.addingTimeInterval(1.4)
        )
        XCTAssertEqual(capture.phase, .exploring)
        XCTAssertEqual(capture.acquisitionProgress, 0)
    }

    func testTransientRecognitionClearsQuicklyWhenCaptureModeIsOff() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 2_100)
        let core = 1.0 * Double.pi / 180
        let outside = 5.0 * Double.pi / 180

        capture.update(
            nearest: ("iss", core),
            captureEnabled: false,
            now: start
        )
        XCTAssertTrue(capture.isAcquiring)
        XCTAssertFalse(capture.recognitionReady)

        capture.update(
            nearest: nil,
            trackedDistance: outside,
            captureEnabled: false,
            now: start.addingTimeInterval(0.1)
        )
        capture.update(
            nearest: nil,
            trackedDistance: outside,
            captureEnabled: false,
            now: start.addingTimeInterval(0.23)
        )

        XCTAssertEqual(capture.phase, .exploring)
        XCTAssertFalse(capture.recognitionReady)
    }

    func testAutomaticRecognitionOpensOnlyAfterRingCompletesAndDoesNotFlicker() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 2_200)
        let core = 1.0 * Double.pi / 180
        let jitter = 3.0 * Double.pi / 180
        let outside = 5.0 * Double.pi / 180

        capture.update(
            nearest: ("iss", core),
            captureEnabled: false,
            now: start
        )
        for step in 1 ... 5 {
            capture.update(
                nearest: ("iss", core),
                trackedDistance: core,
                captureEnabled: false,
                now: start.addingTimeInterval(Double(step) * 0.1)
            )
        }
        XCTAssertFalse(
            capture.recognitionReady,
            "捕获环尚未闭合时不应先插入半张信息面板"
        )

        for step in 6 ... 11 {
            capture.update(
                nearest: ("iss", core),
                trackedDistance: core,
                captureEnabled: false,
                now: start.addingTimeInterval(Double(step) * 0.1)
            )
        }
        XCTAssertEqual(capture.acquisitionProgress, 1, accuracy: 0.001)
        XCTAssertTrue(capture.recognitionReady)

        capture.update(
            nearest: ("iss", jitter),
            trackedDistance: jitter,
            captureEnabled: false,
            now: start.addingTimeInterval(1.2)
        )
        XCTAssertTrue(
            capture.recognitionReady,
            "识别完成后轻微手持抖动不应让完整面板闪烁"
        )

        capture.update(
            nearest: nil,
            trackedDistance: outside,
            captureEnabled: false,
            now: start.addingTimeInterval(1.3)
        )
        capture.update(
            nearest: nil,
            trackedDistance: outside,
            captureEnabled: false,
            now: start.addingTimeInterval(1.43)
        )
        XCTAssertEqual(capture.phase, .exploring)
        XCTAssertFalse(capture.recognitionReady)
    }

    func testManualConfirmationEntersStableReadingState() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 3_000)
        let core = 1.0 * Double.pi / 180

        capture.update(nearest: ("iss", core), now: start)
        XCTAssertTrue(capture.confirmAcquisition(now: start.addingTimeInterval(0.1)))
        XCTAssertEqual(capture.phase, .locked(objectId: "iss"))

        capture.update(
            nearest: nil,
            trackedDistance: nil,
            now: start.addingTimeInterval(30)
        )
        XCTAssertEqual(
            capture.phase,
            .locked(objectId: "iss"),
            "移动手机或放下设备不能自动关闭档案"
        )
        XCTAssertFalse(capture.lockedTargetAligned)
    }

    func testLockedTargetAlignmentUsesNarrowHysteresisWithoutUnlocking() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 3_100)
        let core = 1.0 * Double.pi / 180

        capture.update(nearest: ("iss", core), now: start)
        capture.confirmAcquisition(now: start.addingTimeInterval(0.1))
        XCTAssertTrue(capture.lockedTargetAligned)

        capture.update(
            nearest: nil,
            trackedDistance: 4.1 * Double.pi / 180,
            now: start.addingTimeInterval(0.2)
        )
        XCTAssertFalse(capture.lockedTargetAligned)
        XCTAssertEqual(capture.phase, .locked(objectId: "iss"))

        capture.update(
            nearest: ("iss", 2.4 * Double.pi / 180),
            trackedDistance: 2.4 * Double.pi / 180,
            now: start.addingTimeInterval(0.3)
        )
        XCTAssertTrue(capture.lockedTargetAligned)
    }

    func testExplicitReleaseCannotBeUndoneByStillPointingAtTarget() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 4_000)
        let core = 1.0 * Double.pi / 180

        capture.update(nearest: ("iss", core), now: start)
        capture.confirmAcquisition(now: start.addingTimeInterval(0.1))
        capture.releaseSignal(now: start.addingTimeInterval(0.2))
        XCTAssertTrue(capture.phase.isReleasing)

        capture.update(
            nearest: ("iss", core),
            trackedDistance: core,
            now: start.addingTimeInterval(0.5)
        )
        XCTAssertTrue(capture.phase.isReleasing)
        capture.update(
            nearest: ("iss", core),
            trackedDistance: core,
            now: start.addingTimeInterval(0.2 + Motion.releaseDuration + 0.01)
        )
        XCTAssertEqual(capture.phase, .exploring)

        capture.update(
            nearest: ("iss", core),
            now: start.addingTimeInterval(2)
        )
        XCTAssertEqual(capture.phase, .exploring, "释放后的短暂抑制应避免立即重新捕获")
    }

    func testLockedTargetCanSwitchByExplicitSelection() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 5_000)
        let core = 1.0 * Double.pi / 180

        capture.update(nearest: ("iss", core), now: start)
        capture.confirmAcquisition(now: start.addingTimeInterval(0.1))
        XCTAssertTrue(capture.selectLockedTarget("himawari9", now: start.addingTimeInterval(0.2)))
        XCTAssertEqual(capture.phase, .locked(objectId: "himawari9"))
        XCTAssertFalse(capture.selectLockedTarget("himawari9"))
    }

    func testSustainedFocusOnAnotherTargetWaitsForExplicitConfirmation() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 5_100)
        let core = 1.0 * Double.pi / 180

        capture.update(nearest: ("iss", core), now: start)
        capture.confirmAcquisition(now: start.addingTimeInterval(0.1))

        for step in 1 ... 14 {
            capture.update(
                nearest: ("himawari9", core),
                now: start.addingTimeInterval(0.1 + Double(step) * 0.1)
            )
        }

        XCTAssertEqual(capture.phase, .locked(objectId: "iss"))
        XCTAssertEqual(capture.replacementObjectId, "himawari9")
        XCTAssertEqual(capture.replacementProgress, 1, accuracy: 0.001)

        XCTAssertTrue(capture.confirmReplacement(now: start.addingTimeInterval(1.6)))
        XCTAssertEqual(capture.phase, .locked(objectId: "himawari9"))
        XCTAssertNil(capture.replacementObjectId)
        XCTAssertEqual(capture.replacementProgress, 0)
    }

    func testAbandonedReplacementKeepsExistingArchiveLocked() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 5_200)
        let core = 1.0 * Double.pi / 180

        capture.update(nearest: ("iss", core), now: start)
        capture.confirmAcquisition(now: start.addingTimeInterval(0.1))
        for step in 1 ... 5 {
            capture.update(
                nearest: ("himawari9", core),
                now: start.addingTimeInterval(0.1 + Double(step) * 0.1)
            )
        }
        XCTAssertEqual(capture.replacementObjectId, "himawari9")

        for step in 6 ... 18 {
            capture.update(
                nearest: nil,
                now: start.addingTimeInterval(0.1 + Double(step) * 0.1)
            )
        }

        XCTAssertEqual(capture.phase, .locked(objectId: "iss"))
        XCTAssertNil(capture.replacementObjectId)
    }

    func testSkyOverviewProjectionHasRealDepth() throws {
        let center = CGPoint(x: 100, y: 120)
        let radius: CGFloat = 80
        let front = try XCTUnwrap(SkyOverviewView.project(
            orbitalPosition: SIMD3(0, 0, 6_900),
            center: center,
            radius: radius,
            yaw: 0,
            pitch: 0,
            zoom: 1
        ))
        XCTAssertEqual(front.point.x, center.x, accuracy: 0.001)
        XCTAssertEqual(front.point.y, center.y, accuracy: 0.001)
        XCTAssertGreaterThan(front.depth, 0)

        let back = try XCTUnwrap(SkyOverviewView.project(
            orbitalPosition: SIMD3(0, 0, -6_900),
            center: center,
            radius: radius,
            yaw: 0,
            pitch: 0,
            zoom: 1
        ))
        XCTAssertLessThan(back.depth, 0)
    }

    // MARK: - SkyClock

    func testClockStartsLive() {
        let clock = SkyClock()
        XCTAssertTrue(clock.isLive)
        XCTAssertEqual(clock.offsetLabel, "")
    }

    func testScrubMovesOffsetAndClamps() {
        let clock = SkyClock()
        clock.scrub(by: 3600)
        XCTAssertEqual(clock.offset, 3600, accuracy: 0.001)
        XCTAssertFalse(clock.isLive)

        // 钳制在 ±24h
        clock.scrub(by: 100 * 3600)
        XCTAssertEqual(clock.offset, SkyClock.maxOffset, accuracy: 0.001)
        clock.scrub(by: -300 * 3600)
        XCTAssertEqual(clock.offset, -SkyClock.maxOffset, accuracy: 0.001)
    }

    func testScrubPresentationIsIndependentFromSelectedTime() {
        let clock = SkyClock()
        clock.scrub(by: 3600)

        clock.updateScrubPresentation(translationPoints: 36)
        XCTAssertEqual(clock.scrubPresentationProgress, 0.5, accuracy: 0.001)
        XCTAssertTrue(clock.isScrubbing)

        clock.endScrubPresentation()
        XCTAssertFalse(clock.isScrubbing)
        XCTAssertEqual(clock.offset, 3600, accuracy: 0.001, "松手只回退镜头，不丢失选中时刻")
    }

    func testReturnToLiveAlsoDismissesOverview() {
        let clock = SkyClock()
        clock.scrub(by: -1800)
        clock.updateScrubPresentation(translationPoints: 40)

        clock.returnToLive()

        XCTAssertFalse(clock.isScrubbing)
        XCTAssertEqual(clock.scrubPresentationProgress, 0)
    }

    func testReturnToLiveUsesBoundedLinearTiming() {
        XCTAssertEqual(
            SkyClock.returningOffset(startOffset: 3_600, progress: 0.5),
            1_800,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            SkyClock.returnDuration(forOffset: 3_600),
            SkyClock.returnDuration(forOffset: SkyClock.maxOffset)
        )
        XCTAssertEqual(
            SkyClock.returnDuration(forOffset: SkyClock.maxOffset),
            SkyClock.maximumReturnDuration,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(SkyClock.maximumReturnDuration, 3)
    }

    func testTrailAccumulatesWhileTimeIsMoving() {
        let store = TrailStore()
        store.update(offset: 0, positions: ["iss": .zero], frameTime: 0)
        store.update(offset: 90, positions: ["iss": CGPoint(x: 4, y: 2)], frameTime: 0.05)
        store.update(offset: 180, positions: ["iss": CGPoint(x: 9, y: 5)], frameTime: 0.10)

        XCTAssertEqual(store.trails["iss"]?.count, 2)
        XCTAssertFalse(store.isEmpty)
    }

    func testTrailCanRecordRealTimeMotionWithoutOffsetChange() {
        let store = TrailStore()
        store.update(offset: 0, positions: ["iss": .zero], frameTime: 0, forceRecording: true)
        store.update(
            offset: 0,
            positions: ["iss": CGPoint(x: 2, y: 1)],
            frameTime: 0.1,
            forceRecording: true
        )

        XCTAssertEqual(store.trails["iss"]?.count, 2)
    }

    func testTrailCanSeedHistoricalPathForPersistentOverview() {
        let store = TrailStore(lifetime: 9)
        store.replaceWithPaths(
            ["iss": [.zero, CGPoint(x: 3, y: 2), CGPoint(x: 8, y: 5)]],
            frameTime: 10
        )

        XCTAssertEqual(store.trails["iss"]?.count, 3)
        XCTAssertEqual(store.trails["iss"]?.last?.at, 10)
    }

    func testOverviewYawAndZoomTransformOrbitalPosition() throws {
        let center = CGPoint(x: 100, y: 100)
        let base = try XCTUnwrap(SkyOverviewView.project(
            orbitalPosition: SIMD3(0, 0, 6_900),
            center: center,
            radius: 100,
            yaw: .pi / 2,
            pitch: 0,
            zoom: 1
        ))
        let enlarged = try XCTUnwrap(SkyOverviewView.project(
            orbitalPosition: SIMD3(0, 0, 6_900),
            center: center,
            radius: 100,
            yaw: .pi / 2,
            pitch: 0,
            zoom: 1.5
        ))
        XCTAssertGreaterThan(base.point.x, center.x)
        XCTAssertEqual(
            enlarged.point.x - center.x,
            (base.point.x - center.x) * 1.5,
            accuracy: 0.001
        )
    }

    func testOffsetLabelFormat() {
        let clock = SkyClock()
        clock.scrub(by: 2 * 3600 + 14 * 60 + 36)
        XCTAssertEqual(clock.offsetLabel, "T+02:14:36")
        XCTAssertEqual(clock.relativeOffsetLabel, "未来 2小时 14分")
        clock.scrub(by: -2 * (2 * 3600 + 14 * 60 + 36))
        XCTAssertEqual(clock.offsetLabel, "T−02:14:36")
        XCTAssertEqual(clock.relativeOffsetLabel, "过去 2小时 14分")
    }

    func testObservationTime() {
        let clock = SkyClock()
        clock.scrub(by: 600)
        let now = Date()
        let obs = clock.observationTime(realNow: now)
        XCTAssertEqual(obs.timeIntervalSince(now), 600, accuracy: 0.001)
    }

    // MARK: - 任意时刻推算

    func testSnapshotMatchesDirectPropagation() throws {
        let store = Self.store
        let engine = EphemerisEngine(store: store, observer: ObserverLocation.fallback)
        let t = Date().addingTimeInterval(3600) // 未来 1h

        let snapshot = engine.snapshot(at: t, objectIDs: ["iss"])
        XCTAssertEqual(snapshot.count, 1, "明确请求的目标应有推算结果")

        // 抽查 ISS：与直接调用 SatelliteKit 一致
        guard let sat = store.satellites["iss"], let eph = snapshot["iss"] else {
            return XCTFail("ISS 缺失")
        }
        let geo = LatLonAlt(
            ObserverLocation.fallback.latitude,
            ObserverLocation.fallback.longitude,
            ObserverLocation.fallback.altitudeMeters / 1000.0
        )
        let jd = t.timeIntervalSince1970 / 86400.0 + 2440587.5
        let direct = try sat.topPosition(julianDays: jd, observer: geo)
        XCTAssertEqual(eph.azimuth, direct.azim * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(eph.elevation, direct.elev * .pi / 180, accuracy: 1e-9)
    }

    func testSnapshotIsDeterministicForSameInstant() {
        let store = Self.store
        let engine = EphemerisEngine(store: store, observer: ObserverLocation.fallback)
        let t = Date().addingTimeInterval(-7200)

        let a = engine.snapshot(at: t, objectIDs: ["iss"])
        let b = engine.snapshot(at: t, objectIDs: ["iss"])
        XCTAssertEqual(a["iss"]?.azimuth, b["iss"]?.azimuth)
    }

    func testTimeTravelMovesLEO() {
        let store = Self.store
        let engine = EphemerisEngine(store: store, observer: ObserverLocation.fallback)
        let now = Date()

        // ISS 半个轨道周期（约 46min）后 az/el 应显著不同
        let a = engine.snapshot(at: now, objectIDs: ["iss"])["iss"]
        let b = engine.snapshot(at: now.addingTimeInterval(46 * 60), objectIDs: ["iss"])["iss"]
        guard let a, let b else { return XCTFail("ISS 缺失") }
        let moved = abs(EphemerisEngine.lerpAngle(a.azimuth, b.azimuth, 1) - a.azimuth)
            + abs(b.elevation - a.elevation)
        XCTAssert(moved > 0.1, "LEO 半周期后位置应显著变化，实际变化 \(moved) rad")
    }

    // MARK: - 过境预报

    func testGeoIsStationary() {
        let store = Self.store
        let predictor = PassPredictor(store: store)
        // Himawari-9 从北京看常驻天空
        let p = predictor.nextPass(
            for: "himawari9",
            observer: ObserverLocation.fallback,
            after: Date()
        )
        XCTAssertEqual(p, .stationary)
    }

    func testLEOHasPassWithin24h() {
        let store = Self.store
        let predictor = PassPredictor(store: store)
        // ISS 轨道周期 ~92min，24h 内必有升降
        let p = predictor.nextPass(
            for: "iss",
            observer: ObserverLocation.fallback,
            after: Date()
        )
        switch p {
        case .rises, .sets:
            break // 符合预期
        case .stationary, .none:
            XCTFail("ISS 应在 24h 内有过境事件，得 \(p)")
        }
    }

    func testPassLabelFormat() {
        let inOneHour = Date().addingTimeInterval(3700)
        let label = PassPredictor.label(for: .rises(at: inOneHour))
        XCTAssertEqual(label?.label, "NEXT PASS")
        XCTAssert(label?.value.hasPrefix("T−1H") == true, "1h+ 应显示小时，得 \(label?.value ?? "nil")")
    }
}
