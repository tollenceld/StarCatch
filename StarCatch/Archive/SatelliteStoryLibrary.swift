import Foundation

/// Markdown 在构建阶段经过完整覆盖与格式校验后，编译为一个紧凑 JSON。
/// APP 只解码这一份资源，避免在启动时遍历数千个文件。
struct SatelliteStoryLibrary: Sendable {
    private struct FamilyStory: Decodable {
        let family: CatalogFamily
        let story: SatelliteStory
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let presentationMode: String
        let stories: [SatelliteStory]
        let familyStories: [FamilyStory]
    }

    let storiesByNORAD: [Int: SatelliteStory]
    let storiesByFamily: [CatalogFamily: SatelliteStory]
    let diagnostics: [String]

    static func loadFromBundle(_ bundle: Bundle = .main) -> Self {
        guard let url = bundle.url(forResource: "satellite_profiles", withExtension: "json") else {
            return .init(
                storiesByNORAD: [:],
                storiesByFamily: [:],
                diagnostics: ["App 包内缺少 satellite_profiles.json"]
            )
        }

        do {
            let document = try JSONDecoder().decode(
                Document.self,
                from: Data(contentsOf: url, options: .mappedIfSafe)
            )
            guard document.schemaVersion == 4,
                  document.presentationMode == "structured-localized" else {
                return .init(
                    storiesByNORAD: [:],
                    storiesByFamily: [:],
                    diagnostics: ["satellite_profiles.json schemaVersion 不受支持"]
                )
            }

            var stories: [Int: SatelliteStory] = [:]
            var diagnostics: [String] = []
            stories.reserveCapacity(document.stories.count)
            for story in document.stories {
                guard stories[story.noradID] == nil else {
                    diagnostics.append("NORAD \(story.noradID) 的编译档案重复，已忽略")
                    continue
                }
                stories[story.noradID] = story
            }

            var familyStories: [CatalogFamily: SatelliteStory] = [:]
            familyStories.reserveCapacity(document.familyStories.count)
            for record in document.familyStories {
                guard familyStories[record.family] == nil else {
                    diagnostics.append("\(record.family.title) 的星座共享档案重复，已忽略")
                    continue
                }
                familyStories[record.family] = record.story
            }
            return .init(
                storiesByNORAD: stories,
                storiesByFamily: familyStories,
                diagnostics: diagnostics
            )
        } catch {
            return .init(
                storiesByNORAD: [:],
                storiesByFamily: [:],
                diagnostics: ["satellite_profiles.json 无法解析：\(error.localizedDescription)"]
            )
        }
    }
}
