import Foundation

struct StorySource: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL?
    let provenance: InformationProvenance
    let scope: InformationScope
    let retrievedAt: String?
    let verifiedAt: String?
}

/// 所有可观测目标的深度档案内容。单体卫星使用逐星资料，大型星座节点
/// 共享项目资料，避免把同一段文字复制成上万份。
///
/// 文本由 `SatelliteKnowledge/Profiles` 与 `Families` 在构建时编译；动态轨道
/// 读数仍来自 `catalog.json` 中的 CelesTrak 元素集。
struct SatelliteStory: Codable, Sendable {
    struct OfficialReference: Identifiable, Sendable {
        let title: String
        let url: URL

        var id: String { url.absoluteString }
    }

    struct Chapter: Codable, Identifiable, Sendable {
        let id: String
        let title: String
        let body: String
        let sourceIDs: [String]
    }

    struct Milestone: Codable, Identifiable, Sendable {
        let id: String
        let time: String
        let event: String
        let sourceIDs: [String]
    }

    struct Fact: Codable, Identifiable, Sendable {
        let id: String
        let label: String
        let value: String
        let sourceIDs: [String]
    }

    let noradID: Int
    let eyebrow: String
    let organization: String
    let program: String
    let lead: String
    let leadSourceIDs: [String]
    let scope: InformationScope
    let reviewStatus: String
    let chapters: [Chapter]
    let milestones: [Milestone]
    let facts: [Fact]
    let sources: [StorySource]

    /// 资料源仍以可审阅的纯文本保存在离线档案中；界面只把其中第一个非
    /// CelesTrak 的 HTTPS 官方页面提升为明确操作，避免把轨道数据源误称为官网。
    var officialReference: OfficialReference? {
        for source in sources {
            guard let url = source.url,
                  source.provenance == .verifiedObject
                    || source.provenance == .verifiedFamily,
                  url.host?.localizedCaseInsensitiveContains("celestrak") != true
            else { continue }
            return OfficialReference(title: source.title, url: url)
        }
        return nil
    }

    /// A constellation has a shared program history, but the object the user
    /// actually locked must remain the subject of the archive.  Personalizing
    /// the immutable value keeps the bundled library compact while giving each
    /// real node its own lead, identity chapter and launch marker.
    func personalized(for object: CatalogObject) -> SatelliteStory {
        guard object.family != nil else { return self }
        let identityChapter = Chapter(
            id: "current-node-\(object.noradId)",
            title: "当前节点 · N\(object.noradId)",
            body: "它以国际编号 \(object.cosparId) 和 NORAD N\(object.noradId) 进入公开轨道目录；这些身份字段只描述当前节点，不代表整个系列。",
            sourceIDs: sources.filter { $0.provenance == .catalog }.map(\.id)
        )
        let launchMarker = Milestone(
            id: "node-launch-\(object.noradId)",
            time: object.launched,
            event: "\(object.name) 以 \(object.cosparId) 进入公开轨道目录",
            sourceIDs: sources.filter { $0.provenance == .catalog }.map(\.id)
        )
        return SatelliteStory(
            noradID: object.noradId,
            eyebrow: eyebrow,
            organization: organization,
            program: "\(program) · \(object.name)",
            lead: "当前节点 \(object.name) 以 \(object.cosparId) / N\(object.noradId) 收录；身份与轨道由本地 GP/OMM 快照计算，以下任务说明属于 \(program) 系列。",
            leadSourceIDs: sources.map(\.id),
            scope: .family,
            reviewStatus: reviewStatus,
            chapters: [identityChapter] + chapters,
            milestones: [launchMarker] + milestones,
            facts: facts,
            sources: sources
        )
    }
}

/// A language-specific, immutable archive assembled from the factual story
/// resource and the current catalog object. The domain resource remains a
/// source record; views consume this presentation instead of guessing which
/// pieces of a mixed-language paragraph should be translated.
struct SatelliteStoryPresentation: Sendable {
    let language: SupportedLanguage
    let story: SatelliteStory

    init(
        source: SatelliteStory,
        object: CatalogObject,
        language: SupportedLanguage
    ) {
        self.language = language
        switch language {
        case .simplifiedChinese:
            story = Self.chineseStory(source: source, object: object)
        case .english:
            story = Self.englishStory(source: source, object: object)
        }
    }

    private static func chineseStory(
        source: SatelliteStory,
        object: CatalogObject
    ) -> SatelliteStory {
        let table = "SatelliteText"
        return SatelliteStory(
            noradID: source.noradID,
            eyebrow: L10n.text(
                source.scope == .family ? "archive.curated.family" : "archive.curated.object",
                table: table,
                language: .simplifiedChinese
            ),
            organization: L10n.text(
                "archive.generated.organization",
                table: table,
                language: .simplifiedChinese
            ),
            program: object.family?.title(language: .simplifiedChinese) ?? source.program,
            lead: source.lead,
            leadSourceIDs: source.leadSourceIDs,
            scope: source.scope,
            reviewStatus: source.reviewStatus,
            chapters: source.chapters,
            milestones: source.milestones,
            facts: source.facts,
            sources: source.sources
        )
    }

    init(generatedFor object: CatalogObject, language: SupportedLanguage) {
        self.language = language
        story = Self.generatedStory(object: object, language: language)
    }

    private static func generatedStory(
        object: CatalogObject,
        language: SupportedLanguage
    ) -> SatelliteStory {
        let table = "SatelliteText"
        let sourceID = "catalog-celestrak"
        let fingerprint = object.orbitFingerprint
        let category = object.category.title(language: language)
        let source = StorySource(
            id: sourceID,
            title: L10n.text(
                "archive.generated.source",
                table: table,
                language: language
            ),
            url: URL(string: "https://celestrak.org/NORAD/elements/"),
            provenance: .catalog,
            scope: .object,
            retrievedAt: nil,
            verifiedAt: nil
        )
        return SatelliteStory(
            noradID: object.noradId,
            eyebrow: L10n.text(
                "archive.generated.eyebrow",
                table: table,
                language: language
            ),
            organization: L10n.text(
                "archive.generated.organization",
                table: table,
                language: language
            ),
            program: object.name,
            lead: L10n.format(
                "archive.generated.lead",
                table: table,
                language: language,
                object.name,
                object.cosparId,
                object.noradId,
                object.orbitClass
            ),
            leadSourceIDs: [sourceID],
            scope: .object,
            reviewStatus: L10n.text(
                "archive.generated.review",
                table: table,
                language: language
            ),
            chapters: [
                SatelliteStory.Chapter(
                    id: "generated-identity-\(object.noradId)",
                    title: L10n.text(
                        "archive.generated.identity.title",
                        table: table,
                        language: language
                    ),
                    body: L10n.format(
                        "archive.generated.identity.body",
                        table: table,
                        language: language,
                        object.cosparId,
                        object.noradId
                    ),
                    sourceIDs: [sourceID]
                ),
                SatelliteStory.Chapter(
                    id: "generated-orbit-\(object.noradId)",
                    title: L10n.text(
                        "archive.generated.orbit.title",
                        table: table,
                        language: language
                    ),
                    body: L10n.format(
                        "archive.generated.orbit.body",
                        table: table,
                        language: language,
                        fingerprint.periodMinutes,
                        fingerprint.inclinationDegrees,
                        fingerprint.perigeeKm,
                        fingerprint.apogeeKm
                    ),
                    sourceIDs: [sourceID]
                ),
            ],
            milestones: [
                SatelliteStory.Milestone(
                    id: "generated-launch-\(object.noradId)",
                    time: object.launched,
                    event: L10n.format(
                        "archive.generated.milestone",
                        table: table,
                        language: language,
                        object.cosparId
                    ),
                    sourceIDs: [sourceID]
                ),
            ],
            facts: [
                localizedFact("type", key: "archive.generated.fact.type", value: category, sourceID: sourceID, language: language),
                localizedFact("orbit", key: "archive.generated.fact.orbit", value: object.orbitClass, sourceID: sourceID, language: language),
                localizedFact("period", key: "archive.generated.fact.period", value: String(format: "%.1f MIN", fingerprint.periodMinutes), sourceID: sourceID, language: language),
                localizedFact("inclination", key: "archive.generated.fact.inclination", value: String(format: "%.2f°", fingerprint.inclinationDegrees), sourceID: sourceID, language: language),
                localizedFact("apsides", key: "archive.generated.fact.apsides", value: String(format: "%.0f / %.0f KM", fingerprint.perigeeKm, fingerprint.apogeeKm), sourceID: sourceID, language: language),
            ],
            sources: [source]
        )
    }

    private static func localizedFact(
        _ id: String,
        key: String,
        value: String,
        sourceID: String,
        language: SupportedLanguage
    ) -> SatelliteStory.Fact {
        SatelliteStory.Fact(
            id: "generated-\(id)",
            label: L10n.text(key, table: "SatelliteText", language: language),
            value: value,
            sourceIDs: [sourceID]
        )
    }

    private static func englishStory(
        source: SatelliteStory,
        object: CatalogObject
    ) -> SatelliteStory {
        let fingerprint = object.orbitFingerprint
        let catalogSourceIDs = source.sources
            .filter { $0.provenance == .catalog }
            .map(\.id)
        let sourceIDs = catalogSourceIDs.isEmpty ? source.sources.map(\.id) : catalogSourceIDs
        let category = object.category.title(language: .english)
        let program = object.family?.title(language: .english) ?? category
        let table = "SatelliteText"
        let lead = L10n.format(
            "archive.generated.lead",
            table: table,
            language: .english,
            object.name,
            object.cosparId,
            object.noradId,
            object.orbitClass
        )
        let identityChapter = SatelliteStory.Chapter(
            id: "en-identity-\(object.noradId)",
            title: L10n.text("archive.generated.identity.title", table: table, language: .english),
            body: L10n.format(
                "archive.generated.identity.body",
                table: table,
                language: .english,
                object.cosparId,
                object.noradId
            ),
            sourceIDs: sourceIDs
        )
        let orbitChapter = SatelliteStory.Chapter(
            id: "en-orbit-\(object.noradId)",
            title: L10n.text("archive.generated.orbit.title", table: table, language: .english),
            body: L10n.format(
                "archive.generated.orbit.body",
                table: table,
                language: .english,
                fingerprint.periodMinutes,
                fingerprint.inclinationDegrees,
                fingerprint.perigeeKm,
                fingerprint.apogeeKm
            ),
            sourceIDs: sourceIDs
        )
        let facts = [
            SatelliteStory.Fact(id: "en-type", label: L10n.text("archive.generated.fact.type", table: table, language: .english), value: category, sourceIDs: sourceIDs),
            SatelliteStory.Fact(id: "en-orbit", label: L10n.text("archive.generated.fact.orbit", table: table, language: .english), value: object.orbitClass, sourceIDs: sourceIDs),
            SatelliteStory.Fact(id: "en-period", label: L10n.text("archive.generated.fact.period", table: table, language: .english), value: String(format: "%.1f MIN", fingerprint.periodMinutes), sourceIDs: sourceIDs),
            SatelliteStory.Fact(id: "en-inclination", label: L10n.text("archive.generated.fact.inclination", table: table, language: .english), value: String(format: "%.2f°", fingerprint.inclinationDegrees), sourceIDs: sourceIDs),
            SatelliteStory.Fact(id: "en-apsides", label: L10n.text("archive.generated.fact.apsides", table: table, language: .english), value: String(format: "%.0f / %.0f KM", fingerprint.perigeeKm, fingerprint.apogeeKm), sourceIDs: sourceIDs),
        ]
        let launch = SatelliteStory.Milestone(
            id: "en-launch-\(object.noradId)",
            time: object.launched,
            event: L10n.format(
                "archive.generated.milestone",
                table: table,
                language: .english,
                object.cosparId
            ),
            sourceIDs: sourceIDs
        )
        let sources = source.sources.map { source in
            StorySource(
                id: source.id,
                title: englishSourceTitle(source),
                url: source.url,
                provenance: source.provenance,
                scope: source.scope,
                retrievedAt: source.retrievedAt,
                verifiedAt: source.verifiedAt
            )
        }
        return SatelliteStory(
            noradID: object.noradId,
            eyebrow: L10n.text(
                source.scope == .family ? "archive.curated.family" : "archive.curated.object",
                table: table,
                language: .english
            ),
            organization: L10n.text("archive.generated.organization", table: table, language: .english),
            program: program,
            lead: lead,
            leadSourceIDs: sourceIDs,
            scope: source.scope,
            reviewStatus: L10n.text("archive.generated.review", table: table, language: .english),
            chapters: [identityChapter, orbitChapter],
            milestones: [launch],
            facts: facts,
            sources: sources
        )
    }

    private static func englishSourceTitle(_ source: StorySource) -> String {
        if source.title.unicodeScalars.allSatisfy({ !$0.properties.isIdeographic }) {
            return source.title
        }
        if let host = source.url?.host {
            return "\(source.provenance.title(language: .english)) · \(host)"
        }
        return source.provenance.title(language: .english)
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

    static func deepArchive(
        for object: CatalogObject,
        language: SupportedLanguage
    ) -> SatelliteStoryPresentation? {
        if let source = deepArchive(for: object) {
            return SatelliteStoryPresentation(
                source: source,
                object: object,
                language: language
            )
        }
        return SatelliteStoryPresentation(generatedFor: object, language: language)
    }

    /// 捕获摘要每帧只需要知道入口是否存在，不应为大型星座节点反复构造个性化章节。
    static func hasDeepArchive(for object: CatalogObject) -> Bool {
        true
    }

    static func officialReference(
        for object: CatalogObject
    ) -> SatelliteStory.OfficialReference? {
        if let family = object.family {
            return library.storiesByFamily[family]?.officialReference
        }
        return library.storiesByNORAD[object.noradId]?.officialReference
    }

    /// 测试和开发诊断使用。Release 中即使单份笔记损坏，其他档案仍可读取。
    static var diagnostics: [String] { library.diagnostics }
    static var storyCount: Int { library.storiesByNORAD.count }
    static var familyStoryCount: Int { library.storiesByFamily.count }
}

extension CatalogObject {
    var story: SatelliteStory? { SatelliteStoryCatalog.story(for: self) }
    var deepArchiveStory: SatelliteStory? { SatelliteStoryCatalog.deepArchive(for: self) }
    func deepArchivePresentation(
        language: SupportedLanguage = .current
    ) -> SatelliteStoryPresentation? {
        SatelliteStoryCatalog.deepArchive(for: self, language: language)
    }
    var hasDeepArchive: Bool { SatelliteStoryCatalog.hasDeepArchive(for: self) }
    var officialReference: SatelliteStory.OfficialReference? {
        SatelliteStoryCatalog.officialReference(for: self)
    }
    var isFeatured: Bool { story != nil }
    var deepArchiveTitle: String { name }

    /// 逐星 Markdown 优先；大型星座使用当前节点自己的事实摘要，而不是让
    /// 数千颗卫星在第一层重复同一句项目介绍。
    var archiveNarrative: String {
        deepArchivePresentation()?.story.lead ?? name
    }
}
