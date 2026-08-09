import Foundation
import simd

/// Natural Earth 海岸线的离线、只读几何缓存。
///
/// 资源在后台只解码一次；Canvas 每帧只读取已经准备好的坐标，不执行文件 IO、
/// JSON 解析或地图简化。二进制资源由 `Scripts/compile_coastlines.py` 预生成。
@MainActor
final class EarthCoastlineStore: ObservableObject {
    static let shared = EarthCoastlineStore()

    @Published private(set) var coastlines: [[SIMD2<Float>]] = []

    private var preparationTask: Task<Void, Never>?

    private init() {}

    func prepare() {
        guard coastlines.isEmpty, preparationTask == nil else { return }
        preparationTask = Task {
            let decoded = await Task.detached(priority: .utility) {
                Self.loadBundledCoastlines()
            }.value
            guard !Task.isCancelled else { return }
            coastlines = decoded
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
}
