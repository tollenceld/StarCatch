import CoreGraphics
import Foundation

/// Bounded, deterministic policy for the small set of ambient motion trails in
/// the global scene. Selection changes only when the filtered overview sample changes.
enum OverviewAmbientTrailPolicy {
    nonisolated static let maximumObjectCount = 24
    nonisolated static let idleDelay: TimeInterval = 0.35
    nonisolated static let lifetime: TimeInterval = 3.2
    nonisolated static let maximumPointCount = 32
    nonisolated static let maximumScreenLength: CGFloat = 22
    nonisolated static let maximumVisualAmplification: CGFloat = 7

    nonisolated static func select(
        from objects: [CatalogObject],
        limit: Int = maximumObjectCount
    ) -> [CatalogObject] {
        guard limit > 0, !objects.isEmpty else { return [] }

        let categories = CatalogCategory.allCases
        var buckets: [CatalogCategory: [CatalogObject]] = [:]
        for category in categories {
            var orbitBuckets = Dictionary(
                grouping: objects.filter { $0.category == category },
                by: \.orbitClass
            )
            let orbitClasses = orbitBuckets.keys.sorted()
            for orbitClass in orbitClasses {
                orbitBuckets[orbitClass]?.sort { lhs, rhs in
                    let left = stableRank(lhs)
                    let right = stableRank(rhs)
                    return left == right ? lhs.id < rhs.id : left < right
                }
            }

            var ordered: [CatalogObject] = []
            var orbitOffsets = Dictionary(
                uniqueKeysWithValues: orbitClasses.map { ($0, 0) }
            )
            while true {
                var appended = false
                for orbitClass in orbitClasses {
                    let offset = orbitOffsets[orbitClass, default: 0]
                    guard let bucket = orbitBuckets[orbitClass], offset < bucket.count else {
                        continue
                    }
                    ordered.append(bucket[offset])
                    orbitOffsets[orbitClass] = offset + 1
                    appended = true
                }
                if !appended { break }
            }
            buckets[category] = ordered
        }

        var result: [CatalogObject] = []
        result.reserveCapacity(min(limit, objects.count))
        var offsets = Dictionary(uniqueKeysWithValues: categories.map { ($0, 0) })
        while result.count < limit {
            var appended = false
            for category in categories where result.count < limit {
                let offset = offsets[category, default: 0]
                guard let bucket = buckets[category], offset < bucket.count else { continue }
                result.append(bucket[offset])
                offsets[category] = offset + 1
                appended = true
            }
            if !appended { break }
        }
        return result
    }

    nonisolated static func shouldRender(
        isLive: Bool,
        isScrubbing: Bool,
        interactionActive: Bool,
        isTransitioning: Bool,
        suppressMotion: Bool
    ) -> Bool {
        isLive
            && !isScrubbing
            && !interactionActive
            && !isTransitioning
            && !suppressMotion
    }

    /// Magnifies only screen-space displacement from the current real endpoint.
    /// Stored ECI history remains untouched, motion direction is preserved, and the
    /// farthest old point is clamped to a restrained meteor-like 22pt tail.
    nonisolated static func amplifiedScreenPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 1, let endpoint = points.last else { return points }
        let maximumDistance = points.dropLast().reduce(CGFloat.zero) { partial, point in
            max(partial, hypot(point.x - endpoint.x, point.y - endpoint.y))
        }
        guard maximumDistance > 0.001 else { return points }
        let factor = min(
            maximumVisualAmplification,
            maximumScreenLength / maximumDistance
        )
        return points.map { point in
            CGPoint(
                x: endpoint.x + (point.x - endpoint.x) * factor,
                y: endpoint.y + (point.y - endpoint.y) * factor
            )
        }
    }

    nonisolated private static func stableRank(_ object: CatalogObject) -> UInt64 {
        // FNV-1a is deliberately stable across launches, unlike Swift's Hasher.
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(object.orbitClass)|\(object.noradId)|\(object.id)".utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return value
    }
}
