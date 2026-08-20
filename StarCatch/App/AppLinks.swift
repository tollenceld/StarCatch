import Foundation

/// App Store 元数据与应用内入口共用的公开地址。集中维护，避免支持页和隐私页漂移。
enum AppLinks {
    static let project = URL(string: "https://github.com/tollenceld/StarCatch")!
    static let support = URL(string: "https://github.com/tollenceld/StarCatch/issues")!
    static func privacyPolicy(for language: SupportedLanguage = .current) -> URL {
        let file = language == .simplifiedChinese
            ? "PRIVACY_POLICY.md"
            : "PRIVACY_POLICY_EN.md"
        return URL(
            string: "https://github.com/tollenceld/StarCatch/blob/main/\(file)"
        )!
    }
}
