import Combine
import CoreGraphics
import Foundation
import SatelliteKit
import simd

struct BrightStar: Equatable, Sendable {
    let hr: UInt16
    /// J2000 equatorial coordinates, radians.
    let rightAscension: Float
    let declination: Float
    let visualMagnitude: Float
    /// NaN in the binary asset means that B-V was not available.
    let bvColor: Float

    var inertialDirection: SIMD3<Double> {
        let ra = Double(rightAscension)
        let dec = Double(declination)
        let latitudeScale = cos(dec)
        return SIMD3(
            latitudeScale * cos(ra),
            latitudeScale * sin(ra),
            sin(dec)
        )
    }
}

/// Offline, read-only cache for the NASA HEASARC Bright Star Catalog subset.
/// The compact binary is mapped and decoded once outside the 30fps render path.
@MainActor
final class BrightStarStore: ObservableObject {
    static let shared = BrightStarStore()

    @Published private(set) var stars: [BrightStar] = []
    private var preparationTask: Task<Void, Never>?

    private init() {}

    func prepare() {
        guard stars.isEmpty, preparationTask == nil else { return }
        preparationTask = Task {
            let decoded = await Task.detached(priority: .utility) {
                Self.loadBundledStars()
            }.value
            guard !Task.isCancelled else { return }
            stars = decoded
            preparationTask = nil
        }
    }

    nonisolated private static func loadBundledStars() -> [BrightStar] {
        guard let url = Bundle.main.url(
            forResource: "bright_stars_bsc5p",
            withExtension: "bin"
        ), let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return []
        }
        return decode(data)
    }

    /// Format: `SCST` + UInt16 version + UInt32 count, followed by
    /// UInt16 HR + Float32 RA/Dec/Vmag/B-V records, all little-endian.
    nonisolated static func decode(_ data: Data) -> [BrightStar] {
        var cursor = 0

        func readUInt16() -> UInt16? {
            guard cursor + 2 <= data.count else { return nil }
            let value = UInt16(data[cursor]) | UInt16(data[cursor + 1]) << 8
            cursor += 2
            return value
        }

        func readUInt32() -> UInt32? {
            guard cursor + 4 <= data.count else { return nil }
            let value = UInt32(data[cursor])
                | UInt32(data[cursor + 1]) << 8
                | UInt32(data[cursor + 2]) << 16
                | UInt32(data[cursor + 3]) << 24
            cursor += 4
            return value
        }

        func readFloat() -> Float? {
            readUInt32().map(Float.init(bitPattern:))
        }

        guard data.count >= 10,
              data.prefix(4) == Data("SCST".utf8)
        else { return [] }
        cursor = 4
        guard readUInt16() == 1,
              let count = readUInt32(),
              count > 0,
              count <= 20_000
        else { return [] }

        var result: [BrightStar] = []
        result.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            guard let hr = readUInt16(),
                  let rightAscension = readFloat(),
                  let declination = readFloat(),
                  let visualMagnitude = readFloat(),
                  let bvColor = readFloat(),
                  rightAscension.isFinite,
                  declination.isFinite,
                  visualMagnitude.isFinite,
                  visualMagnitude <= 6.5
            else { return [] }
            result.append(
                BrightStar(
                    hr: hr,
                    rightAscension: rightAscension,
                    declination: declination,
                    visualMagnitude: visualMagnitude,
                    bvColor: bvColor
                )
            )
        }
        return cursor == data.count ? result : []
    }
}

/// A fixed inertial camera captured when the user enters the global scene.
/// Globe Arcball orientation and zoom never mutate this frame.
struct CelestialViewFrame: Equatable, Hashable, Sendable {
    let forward: SIMD3<Double>
    let right: SIMD3<Double>
    let up: SIMD3<Double>

    init(forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>) {
        self.forward = simd_normalize(forward)
        self.right = simd_normalize(right)
        self.up = simd_normalize(up)
    }

    init(
        pointing: Pointing,
        observer: ObserverLocation.Coordinates,
        observation: Date
    ) {
        let latitude = observer.latitude * .pi / 180
        let inertialLongitude = observer.longitude * .pi / 180
            + zeroMeanSiderealTime(julianDate: observation.julianDate) * .pi / 180
        let localUp = SIMD3(
            cos(latitude) * cos(inertialLongitude),
            cos(latitude) * sin(inertialLongitude),
            sin(latitude)
        )
        let east = SIMD3(-sin(inertialLongitude), cos(inertialLongitude), 0)
        let north = simd_normalize(simd_cross(localUp, east))
        let enu = pointing.unitVector
        let forward = simd_normalize(east * enu.x + north * enu.y + localUp * enu.z)

        var baseRight = simd_cross(forward, localUp)
        if simd_length(baseRight) < 1e-6 {
            baseRight = east
        } else {
            baseRight = simd_normalize(baseRight)
        }
        let baseUp = simd_normalize(simd_cross(baseRight, forward))
        let rollCos = cos(-pointing.roll)
        let rollSin = sin(-pointing.roll)
        self.init(
            forward: forward,
            right: baseRight * rollCos - baseUp * rollSin,
            up: baseRight * rollSin + baseUp * rollCos
        )
    }
}

struct ProjectedBrightStar: Equatable, Sendable {
    let point: CGPoint
    let radius: CGFloat
    let opacity: Double
    /// -1...1, used only for a restrained warm/cool tint.
    let temperature: Double
}

struct BrightStarProjectionKey: Hashable {
    let frame: CelestialViewFrame
    let width: Int
    let height: Int
    let catalogCount: Int

    init(frame: CelestialViewFrame, size: CGSize, catalogCount: Int) {
        self.frame = frame
        width = Int(size.width.rounded())
        height = Int(size.height.rounded())
        self.catalogCount = catalogCount
    }
}

enum BrightStarProjector {
    nonisolated static let verticalFOV = 104.0 * Double.pi / 180

    nonisolated static func project(
        stars: [BrightStar],
        frame: CelestialViewFrame,
        size: CGSize
    ) -> [ProjectedBrightStar] {
        guard size.width > 0, size.height > 0 else { return [] }
        let pixelScale = Double(size.height) / 2 / tan(verticalFOV / 2)
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -3, dy: -3)
        var result: [ProjectedBrightStar] = []
        result.reserveCapacity(stars.count / 3)

        for star in stars {
            let direction = star.inertialDirection
            let depth = simd_dot(direction, frame.forward)
            guard depth > 0.08 else { continue }
            let x = simd_dot(direction, frame.right) / depth
            let y = simd_dot(direction, frame.up) / depth
            let point = CGPoint(
                x: Double(size.width) / 2 + x * pixelScale,
                y: Double(size.height) / 2 - y * pixelScale
            )
            guard bounds.contains(point) else { continue }

            let magnitude = Double(star.visualMagnitude)
            let brightness = min(1, max(0, (6.6 - magnitude) / 7.8))
            let bv = star.bvColor.isFinite ? Double(star.bvColor) : 0.65
            result.append(
                ProjectedBrightStar(
                    point: point,
                    radius: 0.34 + 0.98 * pow(brightness, 1.45),
                    opacity: 0.16 + 0.64 * pow(brightness, 1.2),
                    temperature: min(1, max(-1, (0.65 - bv) / 1.15))
                )
            )
        }
        return result
    }
}
