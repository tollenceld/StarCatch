import Foundation
import SatelliteKit

private struct CatalogDocument: Decodable {
    let schemaVersion: Int?
    let snapshotEpoch: Date
    let generatedAt: Date?
    let source: String
    let objects: [CatalogRecord]
}

/// 同时兼容旧的 27 条 TLE 文档和生成器输出的扁平 OMM 文档。
private struct CatalogRecord: Decodable {
    let object: CatalogObject
    let elements: Elements

    private enum CodingKeys: String, CodingKey {
        // OMM fields
        case objectName = "OBJECT_NAME"
        case epoch = "EPOCH"

        // Generated StarCatch metadata
        case generatedID = "STARCATCH_ID"
        case generatedCategory = "STARCATCH_CATEGORY"
        case generatedKind = "STARCATCH_KIND"
        case generatedStatus = "STARCATCH_STATUS"
        case generatedOrbitClass = "STARCATCH_ORBIT_CLASS"
        case generatedLaunched = "STARCATCH_LAUNCHED"
        case generatedPoetic = "STARCATCH_POETIC"
        case generatedFamily = "STARCATCH_FAMILY"
        case generatedCurated = "STARCATCH_CURATED"

        // Legacy authored catalog fields
        case legacyID = "id"
        case legacyName = "name"
        case legacyNoradID = "noradId"
        case legacyCosparID = "cosparId"
        case tle1
        case tle2
        case legacyOrbitClass = "orbitClass"
        case legacyLaunched = "launched"
        case legacyStatus = "status"
        case legacyKind = "kind"
        case legacyPoetic = "poetic"
        case legacyCategory = "category"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isOMM = container.contains(.objectName)

        if isOMM {
            elements = try Elements(from: decoder)
        } else {
            let name = try container.decode(String.self, forKey: .legacyName)
            let line1 = try container.decode(String.self, forKey: .tle1)
            let line2 = try container.decode(String.self, forKey: .tle2)
            elements = try Elements(name, line1, line2)
        }

        let status = try container.decodeIfPresent(
            CatalogObject.Status.self,
            forKey: isOMM ? .generatedStatus : .legacyStatus
        ) ?? .active
        let kind = try container.decodeIfPresent(
            String.self,
            forKey: isOMM ? .generatedKind : .legacyKind
        ) ?? "science"
        let category = try container.decodeIfPresent(
            CatalogCategory.self,
            forKey: isOMM ? .generatedCategory : .legacyCategory
        ) ?? Self.fallbackCategory(status: status, kind: kind)

        let name = try container.decodeIfPresent(String.self, forKey: .legacyName)
            ?? elements.commonName
        let identifier = Int(elements.noradIndex)
        object = CatalogObject(
            id: try container.decodeIfPresent(
                String.self,
                forKey: isOMM ? .generatedID : .legacyID
            ) ?? "norad-\(identifier)",
            name: name,
            noradId: try container.decodeIfPresent(Int.self, forKey: .legacyNoradID)
                ?? identifier,
            cosparId: try container.decodeIfPresent(String.self, forKey: .legacyCosparID)
                ?? elements.launchName,
            orbitClass: try container.decodeIfPresent(
                String.self,
                forKey: isOMM ? .generatedOrbitClass : .legacyOrbitClass
            ) ?? "—",
            launched: try container.decodeIfPresent(
                String.self,
                forKey: isOMM ? .generatedLaunched : .legacyLaunched
            ) ?? "—",
            status: status,
            kind: kind,
            poetic: try container.decodeIfPresent(
                String.self,
                forKey: isOMM ? .generatedPoetic : .legacyPoetic
            ) ?? "它仍在轨道上，以自己的速度穿过观察者此刻的天空。",
            category: category,
            family: try container.decodeIfPresent(
                CatalogFamily.self,
                forKey: .generatedFamily
            ) ?? (name.uppercased().hasPrefix("STARLINK") ? .starlink : nil),
            elementEpoch: try container.decodeIfPresent(Date.self, forKey: .epoch)
                ?? .distantPast,
            isCurated: try container.decodeIfPresent(Bool.self, forKey: .generatedCurated)
                ?? !isOMM
        )
    }

    private static func fallbackCategory(
        status: CatalogObject.Status,
        kind: String
    ) -> CatalogCategory {
        if status != .active { return .legacy }
        switch kind {
        case "weather": return .observation
        case "comms", "nav": return .network
        default: return .exploration
        }
    }
}

/// 加载构建时生成的本地轨道快照并构建 SatelliteKit Satellite。
final class CatalogStore: @unchecked Sendable {
    let objects: [CatalogObject]
    let objectsByID: [String: CatalogObject]
    let objectsByCategory: [CatalogCategory: [CatalogObject]]
    let satellites: [String: Satellite]
    let snapshotEpoch: Date
    let generatedAt: Date?
    let source: String
    let categoryCounts: [CatalogCategory: Int]

    init() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            objects = []
            objectsByID = [:]
            objectsByCategory = [:]
            satellites = [:]
            snapshotEpoch = .distantPast
            generatedAt = nil
            source = "—"
            categoryCounts = [:]
            assertionFailure("catalog.json 缺失")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "无效 ISO-8601 日期：\(value)"
                )
            }
            return date
        }

        guard let catalog = try? decoder.decode(CatalogDocument.self, from: data) else {
            objects = []
            objectsByID = [:]
            objectsByCategory = [:]
            satellites = [:]
            snapshotEpoch = .distantPast
            generatedAt = nil
            source = "—"
            categoryCounts = [:]
            assertionFailure("catalog.json 无法解析")
            return
        }

        var sats: [String: Satellite] = [:]
        var valid: [CatalogObject] = []
        sats.reserveCapacity(catalog.objects.count)
        valid.reserveCapacity(catalog.objects.count)
        for record in catalog.objects where sats[record.object.id] == nil {
            sats[record.object.id] = Satellite(withTLE: record.elements)
            valid.append(record.object)
        }

        objects = valid
        objectsByID = Dictionary(uniqueKeysWithValues: valid.map { ($0.id, $0) })
        objectsByCategory = Dictionary(grouping: valid, by: \CatalogObject.category)
        satellites = sats
        snapshotEpoch = catalog.snapshotEpoch
        generatedAt = catalog.generatedAt
        source = catalog.source
        categoryCounts = Dictionary(grouping: valid, by: \CatalogObject.category)
            .mapValues(\.count)
    }

    func objects(matching filter: CatalogFilter) -> [CatalogObject] {
        guard let category = filter.category else { return objects }
        return objectsByCategory[category] ?? []
    }

    private static func parseISO8601(_ rawValue: String) -> Date? {
        var value = rawValue
        if !value.hasSuffix("Z"), !value.contains("+") { value += "Z" }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
