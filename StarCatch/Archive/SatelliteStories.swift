import Foundation

/// 所有可观测目标的深度档案内容。单体卫星使用逐星资料，大型星座节点
/// 共享项目资料，避免把同一段文字复制成上万份。
///
/// 文本由 `SatelliteKnowledge/Profiles` 与 `Families` 在构建时编译；动态轨道
/// 读数仍来自 `catalog.json` 中的 CelesTrak 元素集。
struct SatelliteStory: Codable, Sendable {
    struct Chapter: Codable, Identifiable, Sendable {
        let id: String
        let title: String
        let body: String
    }

    struct Milestone: Codable, Identifiable, Sendable {
        let id: String
        let time: String
        let event: String
    }

    struct Fact: Codable, Identifiable, Sendable {
        let id: String
        let label: String
        let value: String
    }

    let noradID: Int
    let eyebrow: String
    let organization: String
    let program: String
    let lead: String
    let chapters: [Chapter]
    let milestones: [Milestone]
    let facts: [Fact]
    let sources: [String]

    /// A constellation has a shared program history, but the object the user
    /// actually locked must remain the subject of the archive.  Personalizing
    /// the immutable value keeps the bundled library compact while giving each
    /// real node its own lead, identity chapter and launch marker.
    func personalized(for object: CatalogObject) -> SatelliteStory {
        guard object.family != nil else { return self }
        let identityChapter = Chapter(
            id: "current-node-\(object.noradId)",
            title: "当前节点 · N\(object.noradId)",
            body: "\(object.poetic) 它以国际编号 \(object.cosparId) 登记；这使当前节点与同一星座、甚至同次发射中的其他对象保持明确区分。"
        )
        let launchMarker = Milestone(
            id: "node-launch-\(object.noradId)",
            time: object.launched,
            event: "\(object.name) 以 \(object.cosparId) 进入公开轨道目录"
        )
        return SatelliteStory(
            noradID: object.noradId,
            eyebrow: eyebrow,
            organization: organization,
            program: "\(program) · \(object.name)",
            lead: object.poetic,
            chapters: [identityChapter] + chapters,
            milestones: [launchMarker] + milestones,
            facts: facts,
            sources: sources
        )
    }
}

enum SatelliteStoryCatalog {
    private static let library = SatelliteStoryLibrary.loadFromBundle()

    static func story(for object: CatalogObject) -> SatelliteStory? {
        story(forNORAD: object.noradId)
    }

    static func story(forNORAD noradID: Int) -> SatelliteStory? {
        library.storiesByNORAD[noradID]
    }

    /// 单体目标读取自己的逐星 Markdown；大型星座复用项目背景，再以当前真实
    /// 节点的身份、发射记录与首层轨道摘要生成不可变的个体档案。
    static func deepArchive(for object: CatalogObject) -> SatelliteStory? {
        if let individual = story(for: object) {
            return individual
        }
        guard let family = object.family else { return nil }
        return library.storiesByFamily[family]?.personalized(for: object)
    }

    /// 测试和开发诊断使用。Release 中即使单份笔记损坏，其他档案仍可读取。
    static var diagnostics: [String] { library.diagnostics }
    static var storyCount: Int { library.storiesByNORAD.count }
    static var familyStoryCount: Int { library.storiesByFamily.count }
}

extension CatalogObject {
    var story: SatelliteStory? { SatelliteStoryCatalog.story(for: self) }
    var deepArchiveStory: SatelliteStory? { SatelliteStoryCatalog.deepArchive(for: self) }
    var isFeatured: Bool { story != nil }
    var deepArchiveTitle: String { name }

    /// 逐星 Markdown 优先；大型星座使用当前节点自己的事实摘要，而不是让
    /// 数千颗卫星在第一层重复同一句项目介绍。
    var archiveNarrative: String {
        if let story { return story.lead }
        return poetic
    }
}
