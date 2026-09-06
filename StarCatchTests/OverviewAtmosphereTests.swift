import CoreGraphics
import Foundation
import simd
import XCTest
@testable import StarCatch

@MainActor
final class OverviewAtmosphereTests: XCTestCase {

    func testLandDotBinaryDecodingAndCoastalSizing() throws {
        var data = Data("SCLD".utf8)
        append(UInt16(1), to: &data)
        append(UInt32(3), to: &data)
        append(Float(0), to: &data)
        append(Float(0), to: &data)
        data.append(UInt8(0))
        append(Float(31.23), to: &data)
        append(Float(121.47), to: &data)
        data.append(UInt8(1))
        append(Float(-33.86), to: &data)
        append(Float(151.21), to: &data)
        data.append(UInt8(2))

        let dots = EarthCoastlineStore.decodeLandDots(data)
        XCTAssertEqual(dots.count, 3)
        XCTAssertEqual(dots.map(\.sizeClass), [0, 1, 2])
        XCTAssertEqual(simd_length(dots[0].direction), 1, accuracy: 0.0001)
        XCTAssertTrue(EarthCoastlineStore.decodeLandDots(data.dropLast()).isEmpty)
        XCTAssertTrue(EarthCoastlineStore.decodeLandDots(Data("broken".utf8)).isEmpty)

        let coastal = SkyOverviewView.landDotDiameter(
            sizeClass: 0,
            zoom: 1,
            nearHorizon: false
        )
        let interior = SkyOverviewView.landDotDiameter(
            sizeClass: 2,
            zoom: 1,
            nearHorizon: false
        )
        let horizon = SkyOverviewView.landDotDiameter(
            sizeClass: 2,
            zoom: 1,
            nearHorizon: true
        )
        XCTAssertLessThan(coastal, interior)
        XCTAssertLessThan(horizon, interior)
    }

    func testBundledLandDotAssetHasStableDensityAndUnitDirections() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(
                forResource: "earth_land_dots_50m",
                withExtension: "bin"
            )
        )
        let dots = EarthCoastlineStore.decodeLandDots(try Data(contentsOf: url))
        XCTAssertTrue(5_000 ... 7_000 ~= dots.count)
        XCTAssertGreaterThan(dots.filter { $0.sizeClass == 0 }.count, 1_000)
        XCTAssertGreaterThan(dots.filter { $0.sizeClass == 2 }.count, 3_000)
        XCTAssertTrue(
            dots.allSatisfy {
                abs(simd_length($0.direction) - 1) < 0.0001
            }
        )
    }

    func testSatelliteSignaturesStaySparseStableAndOutsideTheGlobe() {
        XCTAssertTrue(SkyOverviewView.showsSatelliteSignature(
            isCurated: true,
            noradId: 1,
            distanceSquared: 20 * 20,
            earthRadiusSquared: 100 * 100
        ))
        XCTAssertTrue(SkyOverviewView.showsSatelliteSignature(
            isCurated: false,
            noradId: 89 * 7,
            distanceSquared: 110 * 110,
            earthRadiusSquared: 100 * 100
        ))
        XCTAssertFalse(SkyOverviewView.showsSatelliteSignature(
            isCurated: false,
            noradId: 89 * 7,
            distanceSquared: 95 * 95,
            earthRadiusSquared: 100 * 100
        ))
        XCTAssertFalse(SkyOverviewView.showsSatelliteSignature(
            isCurated: false,
            noradId: 90,
            distanceSquared: 110 * 110,
            earthRadiusSquared: 100 * 100
        ))
    }

    func testBrightStarBinaryDecodingAndInvalidFallback() throws {
        var data = Data("SCST".utf8)
        append(UInt16(1), to: &data)
        append(UInt32(1), to: &data)
        append(UInt16(7001), to: &data)
        append(Float(0.25).bitPattern, to: &data)
        append(Float(-0.4).bitPattern, to: &data)
        append(Float(1.2).bitPattern, to: &data)
        append(Float(0.65).bitPattern, to: &data)

        let stars = BrightStarStore.decode(data)
        let star = try XCTUnwrap(stars.first)
        XCTAssertEqual(stars.count, 1)
        XCTAssertEqual(star.hr, 7001)
        XCTAssertEqual(star.rightAscension, 0.25, accuracy: 0.0001)
        XCTAssertEqual(star.declination, -0.4, accuracy: 0.0001)
        XCTAssertTrue(BrightStarStore.decode(Data("broken".utf8)).isEmpty)
        XCTAssertTrue(BrightStarStore.decode(data.dropLast()).isEmpty)
    }

    func testJ2000ProjectionAndCelestialFrameAreOrthogonal() throws {
        let frame = CelestialViewFrame(
            forward: SIMD3(1, 0, 0),
            right: SIMD3(0, 1, 0),
            up: SIMD3(0, 0, 1)
        )
        XCTAssertEqual(simd_dot(frame.forward, frame.right), 0, accuracy: 1e-12)
        XCTAssertEqual(simd_dot(frame.forward, frame.up), 0, accuracy: 1e-12)
        XCTAssertEqual(simd_dot(frame.right, frame.up), 0, accuracy: 1e-12)

        let star = BrightStar(
            hr: 1,
            rightAscension: 0,
            declination: 0,
            visualMagnitude: 0,
            bvColor: 0.65
        )
        let size = CGSize(width: 420, height: 912)
        let first = try XCTUnwrap(
            BrightStarProjector.project(stars: [star], frame: frame, size: size).first
        )
        let second = try XCTUnwrap(
            BrightStarProjector.project(stars: [star], frame: frame, size: size).first
        )
        XCTAssertEqual(first.point.x, size.width / 2, accuracy: 0.0001)
        XCTAssertEqual(first.point.y, size.height / 2, accuracy: 0.0001)
        // The projector has no globe orientation or zoom input: Arcball changes cannot move stars.
        XCTAssertEqual(first.point, second.point)
    }

    func testAmbientTrailSelectionAndGatingAreBoundedAndStable() {
        let objects = CatalogStore().objects
        let first = OverviewAmbientTrailPolicy.select(from: objects)
        let second = OverviewAmbientTrailPolicy.select(from: objects)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.count, OverviewAmbientTrailPolicy.maximumObjectCount)
        XCTAssertGreaterThan(Set(first.map(\.category)).count, 1)
        XCTAssertGreaterThan(Set(first.map(\.orbitClass)).count, 1)

        XCTAssertTrue(OverviewAmbientTrailPolicy.shouldRender(
            isLive: true,
            isScrubbing: false,
            interactionActive: false,
            isTransitioning: false,
            suppressMotion: false
        ))
        XCTAssertFalse(OverviewAmbientTrailPolicy.shouldRender(
            isLive: true,
            isScrubbing: false,
            interactionActive: true,
            isTransitioning: false,
            suppressMotion: false
        ))
        XCTAssertFalse(OverviewAmbientTrailPolicy.shouldRender(
            isLive: false,
            isScrubbing: false,
            interactionActive: false,
            isTransitioning: false,
            suppressMotion: false
        ))
    }

    func testAmbientTrailAmplificationPreservesEndpointDirectionAndLengthCap() throws {
        let source = [
            CGPoint(x: 99, y: 100),
            CGPoint(x: 99.5, y: 100),
            CGPoint(x: 100, y: 100),
        ]
        let amplified = OverviewAmbientTrailPolicy.amplifiedScreenPoints(source)
        XCTAssertEqual(amplified.last, source.last)
        XCTAssertLessThan(amplified[0].x, amplified[1].x)
        let endpoint = try XCTUnwrap(amplified.last)
        let maximumLength = amplified.dropLast().map {
            hypot($0.x - endpoint.x, $0.y - endpoint.y)
        }.max() ?? 0
        XCTAssertLessThanOrEqual(
            maximumLength,
            OverviewAmbientTrailPolicy.maximumScreenLength + 0.001
        )
        XCTAssertEqual(maximumLength, 7, accuracy: 0.001)
    }

    private func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private func append(_ value: Float, to data: inout Data) {
        append(value.bitPattern, to: &data)
    }
}
