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
}

enum SatelliteStoryCatalog {
    private static let library = SatelliteStoryLibrary.loadFromBundle()

    static func story(for object: CatalogObject) -> SatelliteStory? {
        story(forNORAD: object.noradId)
    }

    static func story(forNORAD noradID: Int) -> SatelliteStory? {
        library.storiesByNORAD[noradID]
    }

    /// 单体目标读取自己的逐星 Markdown；大型星座的任意真实节点共同读取一份
    /// 项目级 Markdown。轨道读数仍来自当前节点，不会因此合并。
    static func deepArchive(for object: CatalogObject) -> SatelliteStory? {
        if let individual = story(for: object) {
            return individual
        }
        guard let family = object.family else { return nil }
        return library.storiesByFamily[family]
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
    var deepArchiveTitle: String { family?.title ?? name }

    /// 档案优先显示 Markdown 中的人工资料；大型星座显示共同任务，
    /// 公开机构对象显示可辨认的具体功能，最后才回退到生成目录的通用句。
    var archiveNarrative: String {
        if let story { return story.lead }
        if let family { return family.narrative }
        return poetic
    }
}
