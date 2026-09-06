import Foundation
import simd

struct EarthLandDot: Equatable, Sendable {
    let direction: SIMD3<Float>
    /// 0 = 海岸细点，1 = 近岸中点，2 = 内陆主点。
    let sizeClass: UInt8
}

/// Natural Earth 海岸线与陆地点阵的离线、只读几何缓存。
///
/// 资源在后台只解码一次；Canvas 每帧只读取已经准备好的坐标和单位球方向，不执行
/// 文件 IO、JSON 解析、多边形判断或地图简化。二进制资源由 Scripts 预生成。
@MainActor
final class EarthCoastlineStore: ObservableObject {
    static let shared = EarthCoastlineStore()

    @Published private(set) var coastlines: [[SIMD2<Float>]] = []
    @Published private(set) var landDots: [EarthLandDot] = []

    private var preparationTask: Task<Void, Never>?
    private var prepared = false

    private init() {}

    func prepare() {
        guard !prepared, preparationTask == nil else { return }
        preparationTask = Task {
            let decoded = await Task.detached(priority: .utility) {
                let landDots = Self.loadBundledLandDots()
                return (
                    coastlines: landDots.isEmpty
                        ? Self.loadBundledCoastlines()
                        : [],
                    landDots: landDots
                )
            }.value
            guard !Task.isCancelled else { return }
            coastlines = decoded.coastlines
            landDots = decoded.landDots
            prepared = true
            preparationTask = nil
        }
    }

    nonisolated private static func loadBundledCoastlines() -> [[SIMD2<Float>]] {
        guard let url = Bundle.main.url(
            forResource: "earth_coastlines_50m",
            withExtension: "bin"
        ), let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return []
        }
        return decode(data)
    }

    nonisolated private static func loadBundledLandDots() -> [EarthLandDot] {
        guard let url = Bundle.main.url(
            forResource: "earth_land_dots_50m",
            withExtension: "bin"
        ), let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return []
        }
        return decodeLandDots(data)
    }

    /// 格式：`SCGL` + UInt16 version + UInt32 lineCount，随后每条线为
    /// UInt16 pointCount + pointCount 组 Float32(latitude, longitude)，均为小端。
    nonisolated static func decode(_ data: Data) -> [[SIMD2<Float>]] {
        var cursor = 0

        func readUInt16() -> UInt16? {
            guard cursor + 2 <= data.count else { return nil }
            let low = UInt16(data[cursor])
            let high = UInt16(data[cursor + 1]) << 8
            cursor += 2
            return low | high
        }

        func readUInt32() -> UInt32? {
            guard cursor + 4 <= data.count else { return nil }
            let byte0 = UInt32(data[cursor])
            let byte1 = UInt32(data[cursor + 1]) << 8
            let byte2 = UInt32(data[cursor + 2]) << 16
            let byte3 = UInt32(data[cursor + 3]) << 24
            cursor += 4
            return byte0 | byte1 | byte2 | byte3
        }

        func readFloat() -> Float? {
            guard let bits = readUInt32() else { return nil }
            return Float(bitPattern: bits)
        }

        guard data.count >= 4,
              data.prefix(4) == Data("SCGL".utf8)
        else { return [] }
        cursor = 4
        guard
              readUInt16() == 1,
              let lineCount = readUInt32(),
              lineCount <= 20_000
        else { return [] }

        var result: [[SIMD2<Float>]] = []
        result.reserveCapacity(Int(lineCount))
        for _ in 0 ..< lineCount {
            guard let pointCount = readUInt16(),
                  pointCount >= 2,
                  pointCount <= 20_000
            else { return [] }
            var line: [SIMD2<Float>] = []
            line.reserveCapacity(Int(pointCount))
            for _ in 0 ..< pointCount {
                guard let latitude = readFloat(),
                      let longitude = readFloat(),
                      latitude.isFinite,
                      longitude.isFinite
                else { return [] }
                line.append(SIMD2(latitude, longitude))
            }
            result.append(line)
        }
        return cursor == data.count ? result : []
    }

    /// 格式：`SCLD` + UInt16 version + UInt32 count，随后每个点为
    /// Float32(latitude, longitude) + UInt8 sizeClass，均为小端。
    /// 纬经度只在后台解码时转换为单位球方向，Canvas 不再逐点计算三角函数。
    nonisolated static func decodeLandDots(_ data: Data) -> [EarthLandDot] {
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
              data.prefix(4) == Data("SCLD".utf8)
        else { return [] }
        cursor = 4
        guard readUInt16() == 1,
              let count = readUInt32(),
              count > 0,
              count <= 30_000
        else { return [] }

        var result: [EarthLandDot] = []
        result.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            guard let latitude = readFloat(),
                  let longitude = readFloat(),
                  cursor < data.count
            else { return [] }
            let sizeClass = data[cursor]
            cursor += 1
            guard latitude.isFinite,
                  longitude.isFinite,
                  (-90 ... 90).contains(latitude),
                  (-180 ... 180).contains(longitude),
                  sizeClass <= 2
            else { return [] }

            let latitudeRadians = latitude * .pi / 180
            let longitudeRadians = longitude * .pi / 180
            let latitudeScale = cos(latitudeRadians)
            result.append(
                EarthLandDot(
                    direction: SIMD3(
                        latitudeScale * cos(longitudeRadians),
                        latitudeScale * sin(longitudeRadians),
                        sin(latitudeRadians)
                    ),
                    sizeClass: sizeClass
                )
            )
        }
        return cursor == data.count ? result : []
    }
}
