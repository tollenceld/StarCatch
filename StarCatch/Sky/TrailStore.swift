import Combine
import CoreGraphics
import Foundation

/// 拖影记录 —— 拨动时间时，每个对象在屏幕上留下的运动痕迹。
///
/// 不是装饰线条：只在观测时刻变化时记录，是"时间方向"的视觉证据。
/// 环形缓冲按各视图配置的龄期修剪，拨动或实时观测时持续形成可见光轨。
@MainActor
final class TrailStore: ObservableObject {

    struct TrailPoint {
        let point: CGPoint
        let at: TimeInterval
    }

    struct SpatialTrailPoint {
        let position: SIMD3<Double>
        let at: TimeInterval
    }

    private(set) var trails: [String: [TrailPoint]] = [:]
    private(set) var spatialTrails: [String: [SpatialTrailPoint]] = [:]
    private var lastOffset: TimeInterval = 0
    private var lastFrameTime: TimeInterval?

    /// 主视野拖影的默认存活时长。
    nonisolated static let lifetime: TimeInterval = 2.2
    let trailLifetime: TimeInterval
    private let maximumPointsPerObject: Int
    private let minimumPointDistance: CGFloat

    init(
        lifetime: TimeInterval = TrailStore.lifetime,
        maximumPointsPerObject: Int = 54,
        minimumPointDistance: CGFloat = 0.35
    ) {
        self.trailLifetime = lifetime
        self.maximumPointsPerObject = maximumPointsPerObject
        self.minimumPointDistance = minimumPointDistance
    }

    /// 每帧调用：offset 变化超过阈值（0.5s）才视为"时间在流动"并记录。
    func update(
        offset: TimeInterval,
        positions: [String: CGPoint],
        frameTime: TimeInterval,
        forceRecording: Bool = false
    ) {
        if let lastFrameTime, frameTime - lastFrameTime > trailLifetime {
            trails = [:]
        }
        lastFrameTime = frameTime
        let moving = forceRecording || abs(offset - lastOffset) > 0.5
        lastOffset = offset

        if moving {
            for (id, p) in positions {
                if let previous = trails[id]?.last?.point,
                   hypot(p.x - previous.x, p.y - previous.y) < minimumPointDistance {
                    continue
                }
                trails[id, default: []].append(TrailPoint(point: p, at: frameTime))
                if let count = trails[id]?.count, count > maximumPointsPerObject {
                    trails[id]?.removeFirst(count - maximumPointsPerObject)
                }
            }
        }

        // 修剪过期点
        for (id, arr) in trails {
            let pruned = arr.filter { frameTime - $0.at < trailLifetime }
            trails[id] = pruned.isEmpty ? nil : pruned
        }
    }

    /// 保留 ECI 真值，把屏幕投影延迟到绘制时；旋转星图时拖尾会留在同一空间。
    func updateSpatial(
        offset: TimeInterval,
        positions: [String: SIMD3<Double>],
        frameTime: TimeInterval,
        forceRecording: Bool = false
    ) {
        if let lastFrameTime, frameTime - lastFrameTime > trailLifetime {
            spatialTrails = [:]
        }
        lastFrameTime = frameTime
        let moving = forceRecording || abs(offset - lastOffset) > 0.5
        lastOffset = offset

        if moving {
            for (id, position) in positions {
                if let previous = spatialTrails[id]?.last?.position {
                    let delta = position - previous
                    let distance = sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
                    if distance < 0.8 { continue }
                }
                spatialTrails[id, default: []].append(
                    SpatialTrailPoint(position: position, at: frameTime)
                )
                if let count = spatialTrails[id]?.count, count > maximumPointsPerObject {
                    spatialTrails[id]?.removeFirst(count - maximumPointsPerObject)
                }
            }
        }

        for (id, points) in spatialTrails {
            let pruned = points.filter { frameTime - $0.at < trailLifetime }
            spatialTrails[id] = pruned.isEmpty ? nil : pruned
        }
    }

    /// 用一组真实历史采样重建轨迹主体；最新端点随后仍可由 `update` 实时接续。
    /// 轨迹年龄映射到视觉寿命，而不是要求用户真的等待数分钟才看见路径。
    func replaceWithPaths(
        _ paths: [String: [CGPoint]],
        frameTime: TimeInterval
    ) {
        var rebuilt: [String: [TrailPoint]] = [:]
        rebuilt.reserveCapacity(paths.count)

        for (id, points) in paths where !points.isEmpty {
            let lastIndex = max(1, points.count - 1)
            rebuilt[id] = points.enumerated().map { index, point in
                let progress = Double(index) / Double(lastIndex)
                return TrailPoint(
                    point: point,
                    at: frameTime - trailLifetime * 0.9 * (1 - progress)
                )
            }
        }

        trails = rebuilt
        lastFrameTime = frameTime
    }

    func clear() {
        trails = [:]
        spatialTrails = [:]
        lastOffset = 0
        lastFrameTime = nil
    }

    var isEmpty: Bool { trails.isEmpty && spatialTrails.isEmpty }
}
