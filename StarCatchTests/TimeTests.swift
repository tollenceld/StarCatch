import XCTest
@testable import StarCatch
import SatelliteKit
import simd

/// 时间维度：观测时钟 + 任意时刻推算 + 过境预报。
@MainActor
final class TimeTests: XCTestCase {
    private static let store = CatalogStore()

    func testObservationLogPersistsRealSnapshotRemovesAndClears() throws {
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
        XCTAssertFalse(entry.objectName.isEmpty)

        restored.remove(objectId: object.id)
        XCTAssertTrue(ObservationLog(defaults: defaults).entries.isEmpty)

        restored.record(objectId: object.id, catalog: Self.store)
        restored.clear()
        XCTAssertTrue(ObservationLog(defaults: defaults).entries.isEmpty)
    }

    func testReleaseAnimationFitsCaptureLifecycle() {
        XCTAssertLessThan(Motion.releaseDuration, 1.2, "主动释放应清晰但不拖延")
    }

    func testBootTimelineWakesLettersAndReportsRealSystemState() {
        let silent = BootVisualTimeline(
            elapsed: 0,
            isReady: false,
            handoffProgress: 0
        )
        XCTAssertEqual(silent.scanProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(silent.systemPhase, .initializing)
        XCTAssertLessThan(silent.letterActivation(at: 8), 0.25)
        XCTAssertLessThan(silent.moduleActivation(at: 2), 0.05)

        let syncing = BootVisualTimeline(
            elapsed: 1.6,
            isReady: false,
            handoffProgress: 0
        )
        XCTAssertEqual(syncing.systemPhase, .catalogSync)
        XCTAssertGreaterThan(syncing.signalProgress, 0)
        XCTAssertGreaterThan(
            syncing.letterActivation(at: 0),
            syncing.letterActivation(at: 8)
        )
        XCTAssertGreaterThan(
            syncing.moduleActivation(at: 0),
            syncing.moduleActivation(at: 2)
        )

        let fastReady = BootVisualTimeline(
            elapsed: 1.6,
            isReady: true,
            handoffProgress: 0
        )
        XCTAssertEqual(fastReady.systemPhase, .ready)

        let calibrating = BootVisualTimeline(
            elapsed: 2.5,
            isReady: false,
            handoffProgress: 0
        )
        XCTAssertEqual(calibrating.systemPhase, .calibrating)

        let ready = BootVisualTimeline(
            elapsed: 3.2,
            isReady: true,
            handoffProgress: 0
        )
        XCTAssertEqual(ready.systemPhase, .ready)
        XCTAssertGreaterThan(ready.readyEmphasis, 0.7)
        XCTAssertEqual(ready.moduleActivation(at: 2), 1, accuracy: 0.0001)

        let final = BootVisualTimeline(
            elapsed: 3.5,
            isReady: true,
            handoffProgress: 1
        )
        XCTAssertEqual(final.finalFrame, 1, accuracy: 0.0001)
        XCTAssertEqual(final.wordmarkOpacity, 0, accuracy: 0.0001)
    }

    func testSupportedLanguageUsesEnglishFallbackAndSimplifiedChinese() {
        XCTAssertEqual(SupportedLanguage(locale: Locale(identifier: "en-US")), .english)
        XCTAssertEqual(SupportedLanguage(locale: Locale(identifier: "fr-FR")), .english)
        XCTAssertEqual(
            SupportedLanguage(locale: Locale(identifier: "zh-Hans-CN")),
            .simplifiedChinese
        )
        XCTAssertEqual(SupportedLanguage(locale: Locale(identifier: "zh-Hant-TW")), .english)
    }

    func testOrbitMotionIsDeterministicDirectionalAndGeostationaryStable() {
        let reference = Date(timeIntervalSince1970: 1_750_000_000)
        let prograde = SatelliteMotionSignature(
            referenceDate: reference,
            phaseRadians: 0.4,
            angularDirection: 1,
            periodSeconds: 5_400,
            inclinationDegrees: 51.6,
            eccentricity: 0.001,
            rangeRateKmS: -1.2,
            presentation: .lowOrbit
        )
        let later = reference.addingTimeInterval(120)
        XCTAssertEqual(
            OrbitMotionModel.phase(for: prograde, at: later),
            OrbitMotionModel.phase(for: prograde, at: later),
            accuracy: 0.000_001
        )
        XCTAssertGreaterThan(
            OrbitMotionModel.phase(for: prograde, at: later),
            OrbitMotionModel.phase(for: prograde, at: reference)
        )

        let retrograde = SatelliteMotionSignature(
            referenceDate: reference,
            phaseRadians: 2.4,
            angularDirection: -1,
            periodSeconds: 5_400,
            inclinationDegrees: 101,
            eccentricity: 0.001,
            rangeRateKmS: 0.8,
            presentation: .lowOrbit
        )
        XCTAssertLessThan(
            OrbitMotionModel.phase(for: retrograde, at: later),
            OrbitMotionModel.phase(for: retrograde, at: reference)
        )

        let geostationary = SatelliteMotionSignature(
            referenceDate: reference,
            phaseRadians: 1.2,
            angularDirection: 1,
            periodSeconds: 86_164,
            inclinationDegrees: 0.1,
            eccentricity: 0.0001,
            rangeRateKmS: 0,
            presentation: .geostationary
        )
        XCTAssertEqual(
            OrbitMotionModel.phase(for: geostationary, at: reference),
            OrbitMotionModel.phase(for: geostationary, at: reference.addingTimeInterval(21_600)),
            accuracy: 0.000_001
        )
    }

    func testHighlyEllipticalMotionUsesNonUniformPhaseMapping() {
        let reference = Date(timeIntervalSince1970: 1_750_000_000)
        let signature = SatelliteMotionSignature(
            referenceDate: reference,
            phaseRadians: 0,
            angularDirection: 1,
            periodSeconds: 43_200,
            inclinationDegrees: 63.4,
            eccentricity: 0.7,
            rangeRateKmS: nil,
            presentation: .highElliptical
        )
        let quarter = OrbitMotionModel.phase(
            for: signature,
            at: reference.addingTimeInterval(signature.periodSeconds / 4)
        )
        XCTAssertNotEqual(quarter, .pi / 2, accuracy: 0.05)
    }

    func testBootTimelineLoopsWithoutReturningToBlack() {
        let waiting = BootVisualTimeline(
            elapsed: 6.95,
            isReady: false,
            handoffProgress: 0
        )
        XCTAssertGreaterThanOrEqual(waiting.phaseTime, BootVisualTimeline.loopStart)
        XCTAssertLessThan(waiting.phaseTime, BootVisualTimeline.loopEnd)
        XCTAssertEqual(waiting.loopStrength, 0.38, accuracy: 0.0001)
        XCTAssertGreaterThan(waiting.wordmarkOpacity, 0.99)
    }

    func testSatelliteVisualTreatmentIsStableForTargetID() {
        XCTAssertEqual(
            SkyRenderer.satelliteSignatureAngle(seed: 25_544),
            SkyRenderer.satelliteSignatureAngle(seed: 25_544),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SkyRenderer.keepsFullDensityOpacity(seed: 25_544, cellCount: 7),
            SkyRenderer.keepsFullDensityOpacity(seed: 25_544, cellCount: 7)
        )
        XCTAssertTrue(SkyRenderer.keepsFullDensityOpacity(seed: 25_544, cellCount: 3))
    }

    func testDynamicIslandWingProfilesFollowIPhone17DisplayFamilies() {
        let regular = DynamicIslandWingMetrics(
            viewportSize: CGSize(width: 402, height: 874),
            nativePixelSize: CGSize(width: 1_206, height: 2_622)
        )
        XCTAssertEqual(regular.family, .regular)
        XCTAssertEqual(regular.topPadding, 9)
        XCTAssertEqual(regular.wingHeight, 30)
        XCTAssertEqual(regular.directionWingWidth, regular.statusWingWidth)
        XCTAssertEqual(regular.islandCenterY, 31)

        let air = DynamicIslandWingMetrics(
            viewportSize: CGSize(width: 420, height: 912),
            nativePixelSize: CGSize(width: 1_260, height: 2_736)
        )
        XCTAssertEqual(air.family, .air)
        XCTAssertGreaterThan(air.wingWidth, regular.wingWidth)
        XCTAssertEqual(air.directionWingWidth, air.statusWingWidth)
        XCTAssertEqual(air.islandCenterY, 32)

        let proMax = DynamicIslandWingMetrics(
            viewportSize: CGSize(width: 440, height: 956),
            nativePixelSize: CGSize(width: 1_320, height: 2_868)
        )
        XCTAssertEqual(proMax.family, .proMax)
        XCTAssertGreaterThan(proMax.topPadding, air.topPadding)
        XCTAssertEqual(proMax.directionWingWidth, proMax.statusWingWidth)
        XCTAssertEqual(proMax.islandCenterY, 33)

        let unsupported = DynamicIslandWingMetrics(
            viewportSize: CGSize(width: 375, height: 812),
            nativePixelSize: CGSize(width: 1_125, height: 2_436)
        )
        XCTAssertFalse(unsupported.usesIslandLayout)
        XCTAssertEqual(unsupported.directionWingWidth, unsupported.statusWingWidth)
    }

    func testObservationScaleSeparatesWideFieldFromOverviewThreshold() {
        let wideField = ObservationScale.localMagnification(
            settled: 1,
            gestureScale: 0.7
        )
        XCTAssertEqual(wideField, 0.7, accuracy: 0.0001)
        XCTAssertEqual(
            ObservationScale.overviewProgress(settled: 1, gestureScale: 0.7),
            0,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(
            Projection.verticalFOV(forMagnification: wideField),
            Projection.verticalFOV(forMagnification: 1)
        )

        let threshold = ObservationScale.overviewProgress(
            settled: ObservationScale.minimumLocalMagnification,
            gestureScale: 0.56
        )
        XCTAssertTrue(ObservationScale.shouldCommit(threshold))
    }

    func testObservationScaleRequiresOverviewZoomOvershootToReturn() {
        XCTAssertEqual(
            ObservationScale.overviewReturnProgress(
                rawZoom: ObservationScale.maximumOverviewZoom
            ),
            0,
            accuracy: 0.0001
        )
        let returnProgress = ObservationScale.overviewReturnProgress(
            rawZoom: ObservationScale.maximumOverviewZoom
                + ObservationScale.overviewReturnTravel
        )
        XCTAssertEqual(returnProgress, 1, accuracy: 0.0001)
        XCTAssertTrue(ObservationScale.shouldCommit(returnProgress))
    }

    func testObservationScaleCrossfadeHandsVisualPriorityToGlobe() {
        XCTAssertEqual(
            ObservationScale.localSkyPresence(progress: 0),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ObservationScale.globePresence(progress: 0),
            0,
            accuracy: 0.0001
        )

        let samples = stride(from: 0.0, through: 1.0, by: 0.1)
            .map { (
                ObservationScale.localSkyPresence(progress: $0),
                ObservationScale.globePresence(progress: $0)
            ) }
        for pair in zip(samples, samples.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.0, pair.1.0)
            XCTAssertLessThanOrEqual(pair.0.1, pair.1.1)
        }

        XCTAssertGreaterThan(
            ObservationScale.globePresence(progress: 0.58),
            ObservationScale.localSkyPresence(progress: 0.58)
        )
        XCTAssertEqual(
            ObservationScale.localSkyPresence(progress: 1),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ObservationScale.globePresence(progress: 1),
            1,
            accuracy: 0.0001
        )
    }

    func testLeftEdgeBackGestureRequiresDecisiveRightwardMotion() {
        XCTAssertTrue(
            AppEdgeBackGestureModifier.shouldNavigateBack(
                translation: CGSize(width: 72, height: 8),
                predictedEndTranslation: CGSize(width: 104, height: 10)
            )
        )
        XCTAssertFalse(
            AppEdgeBackGestureModifier.shouldNavigateBack(
                translation: CGSize(width: 24, height: -90),
                predictedEndTranslation: CGSize(width: 38, height: -124)
            )
        )
        XCTAssertFalse(
            AppEdgeBackGestureModifier.shouldNavigateBack(
                translation: CGSize(width: -84, height: 3),
                predictedEndTranslation: CGSize(width: -120, height: 4)
            )
        )
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

    func testAutomaticRecognitionUsesTheSameExplicitReleasePath() {
        let capture = CaptureStateMachine()
        let start = Date(timeIntervalSince1970: 4_100)
        let core = 1.0 * Double.pi / 180

        capture.update(
            nearest: ("iss", core),
            captureEnabled: false,
            now: start
        )
        for step in 1 ... 11 {
            capture.update(
                nearest: ("iss", core),
                trackedDistance: core,
                captureEnabled: false,
                now: start.addingTimeInterval(Double(step) * 0.1)
            )
        }
        XCTAssertTrue(capture.recognitionReady)

        capture.releaseSignal(now: start.addingTimeInterval(1.2))
        XCTAssertTrue(capture.phase.isReleasing)
        XCTAssertFalse(capture.recognitionReady)

        capture.update(
            nearest: ("iss", core),
            trackedDistance: core,
            captureEnabled: false,
            now: start.addingTimeInterval(1.2 + Motion.releaseDuration + 0.01)
        )
        XCTAssertEqual(capture.phase, .exploring)
        capture.update(
            nearest: ("iss", core),
            captureEnabled: false,
            now: start.addingTimeInterval(2)
        )
        XCTAssertEqual(capture.phase, .exploring)
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

    func testOverviewTwoFingerRollRotatesAroundScreenCenterWithoutChangingDepth() throws {
        let center = CGPoint(x: 100, y: 100)
        let level = try XCTUnwrap(SkyOverviewView.project(
            orbitalPosition: SIMD3(0, 0, 6_900),
            center: center,
            radius: 100,
            yaw: .pi / 2,
            pitch: 0,
            roll: 0,
            zoom: 1
        ))
        let rolled = try XCTUnwrap(SkyOverviewView.project(
            orbitalPosition: SIMD3(0, 0, 6_900),
            center: center,
            radius: 100,
            yaw: .pi / 2,
            pitch: 0,
            roll: .pi / 2,
            zoom: 1
        ))

        XCTAssertGreaterThan(level.point.x, center.x)
        XCTAssertEqual(rolled.point.x, center.x, accuracy: 0.001)
        XCTAssertGreaterThan(rolled.point.y, center.y)
        XCTAssertEqual(rolled.depth, level.depth, accuracy: 0.000_001)
    }

    func testOverviewArcballCanRotateFreelyPastEitherPole() {
        let center = CGPoint(x: 120, y: 160)
        let quarterTurn = SkyOverviewView.arcballRotation(
            from: center,
            to: CGPoint(x: center.x, y: center.y - 100),
            center: center,
            radius: 100
        )
        let halfTurn = simd_normalize(quarterTurn * quarterTurn)
        let rotatedFront = halfTurn.act(SIMD3<Double>(0, 0, 1))

        XCTAssertEqual(simd_length(rotatedFront), 1, accuracy: 0.000_001)
        XCTAssertLessThan(rotatedFront.z, -0.999)
    }

    func testOverviewKeepsTheSameSatelliteSetDuringInteraction() {
        XCTAssertEqual(
            SkyOverviewView.renderSampleDivisor(zoom: 1.4, interactionActive: true),
            1
        )
        XCTAssertEqual(
            SkyOverviewView.renderSampleDivisor(zoom: 0.8, interactionActive: true),
            1
        )
        XCTAssertEqual(
            SkyOverviewView.renderSampleDivisor(zoom: 1, interactionActive: false),
            1
        )
        XCTAssertEqual(
            SkyOverviewView.renderSampleDivisor(zoom: 1.2, interactionActive: false),
            1
        )
    }

    func testOverviewDragTreatsTheGlobeAsDirectlyManipulatedContent() {
        let rightward = SkyOverviewView.dragRotationDelta(
            translation: CGSize(width: 20, height: 0)
        )
        let downward = SkyOverviewView.dragRotationDelta(
            translation: CGSize(width: 0, height: 20)
        )

        XCTAssertGreaterThan(rightward.yaw, 0)
        XCTAssertEqual(rightward.pitch, 0, accuracy: 0.000_001)
        XCTAssertEqual(downward.yaw, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(downward.pitch, 0)
    }

    func testSatelliteSignaturesSeparateArtificialTargetRoles() throws {
        let store = CatalogStore()
        let starlink = try XCTUnwrap(store.objects.first { $0.family == .starlink })
        let navigation = try XCTUnwrap(store.objects.first { $0.kind == "nav" })
        let observation = try XCTUnwrap(
            store.objects.first { $0.category == .observation && $0.family == nil }
        )

        XCTAssertEqual(SkyRenderer.satelliteSignature(for: starlink), .network)
        XCTAssertEqual(SkyRenderer.satelliteSignature(for: navigation), .navigation)
        XCTAssertEqual(SkyRenderer.satelliteSignature(for: observation), .observation)
    }

    func testBundledCoastlineBinaryDecoderRejectsTruncationAndPreservesCoordinates() {
        var data = Data("SCGL".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        func append(_ value: Float) {
            append(value.bitPattern)
        }

        append(UInt16(1))
        append(UInt32(1))
        append(UInt16(2))
        append(Float(31.23))
        append(Float(121.47))
        append(Float(39.90))
        append(Float(116.40))

        let decoded = EarthCoastlineStore.decode(data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].count, 2)
        XCTAssertEqual(decoded[0][0].x, 31.23, accuracy: 0.0001)
        XCTAssertEqual(decoded[0][0].y, 121.47, accuracy: 0.0001)
        XCTAssertTrue(EarthCoastlineStore.decode(Data(data.dropLast())).isEmpty)
    }

    func testSpatialMotionUsesFrameRateIndependentDecayAndSoftBoundaries() {
        let oneFrame = SpatialMotion.decayFactor(
            rate: SpatialMotion.rotationDecay,
            deltaTime: 1.0 / 60.0
        )
        let twoFrames = SpatialMotion.decayFactor(
            rate: SpatialMotion.rotationDecay,
            deltaTime: 2.0 / 60.0
        )
        XCTAssertEqual(twoFrames, oneFrame * oneFrame, accuracy: 0.000_001)

        let freeVelocity = SpatialMotion.boundaryVelocityScale(
            value: 0,
            velocity: 1,
            lowerBound: -1,
            upperBound: 1,
            slowZone: 0.25
        )
        let edgeVelocity = SpatialMotion.boundaryVelocityScale(
            value: 0.98,
            velocity: 1,
            lowerBound: -1,
            upperBound: 1,
            slowZone: 0.25
        )
        XCTAssertEqual(freeVelocity, 1, accuracy: 0.000_001)
        XCTAssertLessThan(edgeVelocity, 0.25)
    }

    func testSpatialScaleProjectionRespectsBothViewBoundaries() {
        XCTAssertEqual(
            SpatialMotion.projectedScale(
                current: 1.7,
                logarithmicVelocity: 8,
                lowerBound: 0.78,
                upperBound: 1.72
            ),
            1.72,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            SpatialMotion.projectedScale(
                current: 0.8,
                logarithmicVelocity: -8,
                lowerBound: 0.78,
                upperBound: 1.72
            ),
            0.78,
            accuracy: 0.000_001
        )
    }

    func testEarthSurfaceDirectionUsesSiderealRotation() {
        let primeMeridian = SkyOverviewView.sphericalSurfaceDirection(
            latitude: 0,
            longitude: 0,
            siderealRadians: 0
        )
        XCTAssertEqual(primeMeridian.x, 1, accuracy: 0.000_001)
        XCTAssertEqual(primeMeridian.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(primeMeridian.z, 0, accuracy: 0.000_001)

        let quarterTurn = SkyOverviewView.sphericalSurfaceDirection(
            latitude: 0,
            longitude: 0,
            siderealRadians: .pi / 2
        )
        XCTAssertEqual(quarterTurn.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(quarterTurn.y, 1, accuracy: 0.000_001)
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
        let geodetic = try sat.geoPosition(julianDays: jd)
        XCTAssertEqual(eph.altitudeKm, geodetic.alt, accuracy: 1e-9)
    }

    func testLocalSkyAvoidsFullCatalogPropagationUntilOverviewNeedsIt() {
        let session = SkySession(catalog: Self.store)
        XCTAssertEqual(
            session.ephemeris.activePropagationObjectCount,
            session.displayObjects.count
        )
        XCTAssertLessThan(session.displayObjects.count, session.visibleObjects.count)

        session.setOverviewPropagationActive(true)
        XCTAssertEqual(
            session.ephemeris.activePropagationObjectCount,
            session.visibleObjects.count
        )
        session.setOverviewPropagationActive(false)
        XCTAssertEqual(
            session.ephemeris.activePropagationObjectCount,
            session.displayObjects.count
        )
    }

    func testSnapshotIsDeterministicForSameInstant() {
        let store = Self.store
        let engine = EphemerisEngine(store: store, observer: ObserverLocation.fallback)
        let t = Date().addingTimeInterval(-7200)

        let a = engine.snapshot(at: t, objectIDs: ["iss"])
        let b = engine.snapshot(at: t, objectIDs: ["iss"])
        XCTAssertEqual(a["iss"]?.azimuth, b["iss"]?.azimuth)
    }

    func testPreciseEphemerisCanWarmBeforeTheSummaryRenders() async throws {
        let engine = EphemerisEngine(
            store: Self.store,
            observer: ObserverLocation.fallback
        )
        let observation = Date()
        let preparedResult = await engine.preparePreciseEphemeris(
            "iss",
            at: observation,
            live: true
        )
        let prepared = try XCTUnwrap(preparedResult)
        let cached = try XCTUnwrap(
            engine.cachedPreciseEphemeris(
                "iss",
                at: observation,
                live: true
            )
        )
        XCTAssertEqual(cached.objectId, prepared.objectId)
        XCTAssertEqual(cached.velocityKmS, prepared.velocityKmS, accuracy: 1e-12)
        XCTAssertGreaterThan(cached.velocityKmS, 0)
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

    func testInsightSnapshotComputesPassTrendAndSubpointOffTheRenderPath() async throws {
        let store = Self.store
        let engine = SatelliteInsightEngine(store: store)
        let observation = store.generatedAt ?? Date()
        let generated = await engine.insight(
            for: "iss",
            observer: ObserverLocation.fallback,
            at: observation
        )
        let first = try XCTUnwrap(generated)
        XCTAssertEqual(first.objectID, "iss")
        XCTAssertNotNil(first.pass, "ISS 应在 24 小时内形成完整过境窗口")
        XCTAssertNotNil(first.rangeRateKmS)
        let subpoint = try XCTUnwrap(first.subpoint)
        XCTAssertTrue((-90 ... 90).contains(subpoint.latitude))
        XCTAssertTrue((-180 ... 180).contains(subpoint.longitude))
        XCTAssertGreaterThan(first.fingerprint.periodMinutes, 80)
        XCTAssertLessThan(first.fingerprint.periodMinutes, 110)

        let cached = await engine.insight(
            for: "iss",
            observer: ObserverLocation.fallback,
            at: observation
        )
        XCTAssertEqual(first, cached, "相同目标、位置和时间桶应复用完全一致的洞察")
    }

    func testTargetDetailWaitsThreeSecondsAfterFocusLeaves() {
        let focusLeftAt = Date(timeIntervalSince1970: 1_750_000_000)
        let deadline = TargetDetailRetentionPolicy.deadline(after: focusLeftAt)

        XCTAssertEqual(
            deadline.timeIntervalSince(focusLeftAt),
            TargetDetailRetentionPolicy.graceDuration,
            accuracy: 0.0001
        )
        XCTAssertFalse(
            TargetDetailRetentionPolicy.shouldDismiss(
                now: focusLeftAt.addingTimeInterval(2.99),
                deadline: deadline,
                isPinned: false,
                isCaptureActive: false
            )
        )
        XCTAssertTrue(
            TargetDetailRetentionPolicy.shouldDismiss(
                now: focusLeftAt.addingTimeInterval(3),
                deadline: deadline,
                isPinned: false,
                isCaptureActive: false
            )
        )
    }

    func testTargetDetailDoesNotExpireWhileTappedOrRecaptured() {
        let deadline = Date(timeIntervalSince1970: 1_750_000_000)
        let afterDeadline = deadline.addingTimeInterval(10)

        XCTAssertFalse(
            TargetDetailRetentionPolicy.shouldDismiss(
                now: afterDeadline,
                deadline: deadline,
                isPinned: true,
                isCaptureActive: false
            )
        )
        XCTAssertFalse(
            TargetDetailRetentionPolicy.shouldDismiss(
                now: afterDeadline,
                deadline: deadline,
                isPinned: false,
                isCaptureActive: true
            )
        )
    }

    func testUnpinningDetailRestoresGraceOnlyAfterFocusLeaves() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertNil(
            TargetDetailRetentionPolicy.deadlineAfterUnpin(
                now: now,
                isCaptureActive: true
            )
        )
        let deadline = try XCTUnwrap(TargetDetailRetentionPolicy.deadlineAfterUnpin(
            now: now,
            isCaptureActive: false
        ))
        XCTAssertEqual(
            deadline.timeIntervalSince(now),
            TargetDetailRetentionPolicy.graceDuration,
            accuracy: 0.0001
        )
    }
}
