import Foundation

/// 观测日志 —— 仪器记录的锁定档案。
///
/// 每次成功锁定一个对象即落一条记录（同一对象只保留最近一次）。
/// 存 UserDefaults：这不是社交功能，只是仪器自己的记录纸。
@MainActor
final class ObservationLog: ObservableObject {

    struct Entry: Codable, Identifiable {
        let objectId: String
        let objectName: String
        let firstSeen: Date
        var lastSeen: Date
        var count: Int
        var observedAt: Date?
        var azimuth: Double?
        var elevation: Double?
        var altitudeKm: Double?
        var rangeKm: Double?
        var velocityKmS: Double?
        /// 目录升级后目标可能退役或离轨；这些可选字段保存锁定当时的档案快照。
        var category: CatalogCategory?
        var cosparId: String?
        var noradId: Int?
        var orbitClass: String?
        var launched: String?
        var status: CatalogObject.Status?
        var kind: String?
        var poetic: String?
        var family: CatalogFamily?

        var id: String { objectId }
    }

    @Published private(set) var entries: [Entry] = []

    private static let storageKey = "observationLog.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// 记录一次锁定。
    func record(
        objectId: String?,
        catalog: CatalogStore,
        observationTime: Date? = nil,
        ephemeris: Ephemeris? = nil
    ) {
        guard let objectId,
              let object = catalog.objectsByID[objectId]
        else { return }
        let now = Date()
        if let idx = entries.firstIndex(where: { $0.objectId == objectId }) {
            entries[idx].lastSeen = now
            entries[idx].count += 1
            entries[idx].observedAt = observationTime
            entries[idx].azimuth = ephemeris?.azimuth
            entries[idx].elevation = ephemeris?.elevation
            entries[idx].altitudeKm = ephemeris?.altitudeKm
            entries[idx].rangeKm = ephemeris?.rangeKm
            entries[idx].velocityKmS = ephemeris?.velocityKmS
            entries[idx].category = object.category
            entries[idx].cosparId = object.cosparId
            entries[idx].noradId = object.noradId
            entries[idx].orbitClass = object.orbitClass
            entries[idx].launched = object.launched
            entries[idx].status = object.status
            entries[idx].kind = object.kind
            entries[idx].poetic = object.poetic
            entries[idx].family = object.family
        } else {
            entries.append(Entry(
                objectId: objectId,
                objectName: object.name,
                firstSeen: now,
                lastSeen: now,
                count: 1,
                observedAt: observationTime,
                azimuth: ephemeris?.azimuth,
                elevation: ephemeris?.elevation,
                altitudeKm: ephemeris?.altitudeKm,
                rangeKm: ephemeris?.rangeKm,
                velocityKmS: ephemeris?.velocityKmS,
                category: object.category,
                cosparId: object.cosparId,
                noradId: object.noradId,
                orbitClass: object.orbitClass,
                launched: object.launched,
                status: object.status,
                kind: object.kind,
                poetic: object.poetic,
                family: object.family
            ))
        }
        // 最近观测在前
        entries.sort { $0.lastSeen > $1.lastSeen }
        save()
    }

    var totalObjects: Int { entries.count }

    func clear() {
        entries = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
