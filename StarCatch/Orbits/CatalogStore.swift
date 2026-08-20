import Foundation
import SatelliteKit

private struct CatalogDocument: Decodable {
    let schemaVersion: Int
    let snapshotEpoch: Date
    let generatedAt: Date
    let source: String
    let objects: [CatalogRecord]
}

/// `Scripts/update_catalog.py` 生成的 schema v2 记录。绝大多数对象是扁平 OMM；
/// 不在 active GP 分组中的少量历史目标以策展 TLE 记录保留。这里支持的是当前
/// 发布格式中的两种明确载荷，不再兼容旧版整份目录文档。
private struct CatalogRecord: Decodable {
    let object: CatalogObject
    let elements: Elements

    private enum CodingKeys: String, CodingKey {
        case objectName = "OBJECT_NAME"
        case epoch = "EPOCH"

        case generatedID = "STARCATCH_ID"
        case generatedCategory = "STARCATCH_CATEGORY"
        case generatedKind = "STARCATCH_KIND"
        case generatedStatus = "STARCATCH_STATUS"
        case generatedOrbitClass = "STARCATCH_ORBIT_CLASS"
        case generatedLaunched = "STARCATCH_LAUNCHED"
        case generatedFamily = "STARCATCH_FAMILY"
        case generatedCurated = "STARCATCH_CURATED"

        // Curated TLE fallback fields emitted inside the schema v2 document.
        case authoredID = "id"
        case authoredName = "name"
        case authoredNORADID = "noradId"
        case authoredCosparID = "cosparId"
        case tle1
        case tle2
        case authoredOrbitClass = "orbitClass"
        case authoredLaunched = "launched"
        case authoredStatus = "status"
        case authoredKind = "kind"
        case authoredCategory = "category"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isAuthoredTLE = container.contains(.tle1)
        if isAuthoredTLE {
            let name = try container.decode(String.self, forKey: .authoredName)
            let line1 = try container.decode(String.self, forKey: .tle1)
            let line2 = try container.decode(String.self, forKey: .tle2)
            elements = try Elements(name, line1, line2)
        } else {
            _ = try container.decode(String.self, forKey: .objectName)
            elements = try Elements(from: decoder)
        }

        let status = try container.decodeIfPresent(
            CatalogObject.Status.self,
            forKey: isAuthoredTLE ? .authoredStatus : .generatedStatus
        ) ?? .active
        let kind = try container.decodeIfPresent(
            String.self,
            forKey: isAuthoredTLE ? .authoredKind : .generatedKind
        ) ?? "science"
        let category = try container.decodeIfPresent(
            CatalogCategory.self,
            forKey: isAuthoredTLE ? .authoredCategory : .generatedCategory
        ) ?? Self.fallbackCategory(status: status, kind: kind)

        let name = try container.decodeIfPresent(String.self, forKey: .authoredName)
            ?? elements.commonName
        let identifier = Int(elements.noradIndex)
        let earthRadiusKm = 6_378.137
        let semimajorAxisKm = elements.a₀ * earthRadiusKm
        let eccentricity = elements.e₀
        let fingerprint = OrbitFingerprint(
            periodMinutes: 2 * .pi / elements.n₀,
            inclinationDegrees: elements.i₀ * 180 / .pi,
            eccentricity: eccentricity,
            perigeeKm: semimajorAxisKm * (1 - eccentricity) - earthRadiusKm,
            apogeeKm: semimajorAxisKm * (1 + eccentricity) - earthRadiusKm
        )
        object = CatalogObject(
            id: try container.decodeIfPresent(
                String.self,
                forKey: isAuthoredTLE ? .authoredID : .generatedID
            ) ?? "norad-\(identifier)",
            name: name,
            noradId: try container.decodeIfPresent(Int.self, forKey: .authoredNORADID)
                ?? identifier,
            cosparId: try container.decodeIfPresent(String.self, forKey: .authoredCosparID)
                ?? elements.launchName,
            orbitClass: try container.decodeIfPresent(
                String.self,
                forKey: isAuthoredTLE ? .authoredOrbitClass : .generatedOrbitClass
            ) ?? "—",
            launched: try container.decodeIfPresent(
                String.self,
                forKey: isAuthoredTLE ? .authoredLaunched : .generatedLaunched
            ) ?? "—",
            status: status,
            kind: kind,
            category: category,
            family: try container.decodeIfPresent(
                CatalogFamily.self,
                forKey: .generatedFamily
            ) ?? CatalogFamily.infer(from: name),
            elementEpoch: try container.decodeIfPresent(Date.self, forKey: .epoch)
                ?? .distantPast,
            isCurated: try container.decodeIfPresent(Bool.self, forKey: .generatedCurated)
                ?? isAuthoredTLE,
            orbitFingerprint: fingerprint
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
    let objectsByFamily: [CatalogFamily: [CatalogObject]]
    let satellites: [String: Satellite]
    let snapshotEpoch: Date
    let generatedAt: Date?
    let source: String
    /// 仅在随包资源损坏或 schema 不兼容时存在，供用户可见的恢复页使用。
    let loadFailureDescription: String?
    let categoryCounts: [CatalogCategory: Int]
    let familyCounts: [CatalogFamily: Int]
    let filterCounts: [CatalogFilter: Int]
    let filterReadableCounts: [CatalogFilter: Int]
    let insightIndex: CatalogInsightIndex

    init() {
        let catalog: CatalogDocument
        do {
            catalog = try Self.loadCatalog()
        } catch {
            objects = []
            objectsByID = [:]
            objectsByCategory = [:]
            objectsByFamily = [:]
            satellites = [:]
            snapshotEpoch = .distantPast
            generatedAt = nil
            source = "—"
            loadFailureDescription = Self.describe(error)
            categoryCounts = [:]
            familyCounts = [:]
            filterCounts = [:]
            filterReadableCounts = [:]
            insightIndex = CatalogInsightIndex(objects: [])
            assertionFailure("catalog.json 加载失败：\(Self.describe(error))")
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
        objectsByFamily = Dictionary(grouping: valid.compactMap { object in
            object.family.map { ($0, object) }
        }, by: \.0).mapValues { pairs in pairs.map(\.1) }
        satellites = sats
        snapshotEpoch = catalog.snapshotEpoch
        generatedAt = catalog.generatedAt
        source = catalog.source
        loadFailureDescription = nil
        categoryCounts = objectsByCategory.mapValues(\.count)
        familyCounts = objectsByFamily.mapValues(\.count)
        filterCounts = Dictionary(
            uniqueKeysWithValues: CatalogFilter.allCases.map { filter in
                (filter, valid.lazy.filter(filter.includes).count)
            }
        )
        filterReadableCounts = Dictionary(
            uniqueKeysWithValues: CatalogFilter.allCases.map { filter in
                (
                    filter,
                    valid.lazy.filter { filter.includes($0) && $0.hasMeaningfulProfile }.count
                )
            }
        )
        insightIndex = CatalogInsightIndex(objects: valid)
    }

    private enum LoadError: LocalizedError {
        case missingResource
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
            case .missingResource:
                "App 包内缺少 catalog.json"
            case .unsupportedSchema(let version):
                "catalog.json schemaVersion \(version) 不受支持"
            }
        }
    }

    private static func loadCatalog() throws -> CatalogDocument {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw LoadError.missingResource
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = Self.parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "无效 ISO-8601 日期：\(value)"
                )
            }
            return date
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let document = try decoder.decode(CatalogDocument.self, from: data)
        guard document.schemaVersion == 2 else {
            throw LoadError.unsupportedSchema(document.schemaVersion)
        }
        return document
    }

    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        let context: DecodingError.Context
        switch decodingError {
        case .keyNotFound(let key, let value):
            return "缺少 \(value.codingPath.map(\.stringValue).joined(separator: "."))"
                + "\(value.codingPath.isEmpty ? "" : ".")\(key.stringValue)：\(value.debugDescription)"
        case .typeMismatch(_, let value),
             .valueNotFound(_, let value),
             .dataCorrupted(let value):
            context = value
        default:
            return error.localizedDescription
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return "\(path.isEmpty ? "根节点" : path)：\(context.debugDescription)"
    }

    func objects(matching filter: CatalogFilter) -> [CatalogObject] {
        guard filter != .all else { return objects }
        return objects.filter(filter.includes)
    }

    private static func parseISO8601(_ rawValue: String) -> Date? {
        var value = rawValue
        if !value.hasSuffix("Z"), !value.contains("+") { value += "Z" }

        if let date = fractionalISO8601.date(from: value) { return date }

        return standardISO8601.date(from: value)
    }

    /// 目录含一万六千余个历元；格式器必须复用，不能为每条记录各创建两次。
    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
