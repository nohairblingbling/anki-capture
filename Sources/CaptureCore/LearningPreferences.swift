import Foundation

public enum StudyLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en", chinese = "zh", japanese = "ja"
    public var title: String {
        switch self { case .english: "英语"; case .chinese: "中文"; case .japanese: "日语" }
    }
    public var promptName: String {
        switch self { case .english: "English"; case .chinese: "Chinese"; case .japanese: "Japanese" }
    }
}

public enum LearningLevel: String, Codable, CaseIterable, Sendable {
    case automatic, beginner, intermediate, advanced
    public var title: String {
        switch self {
        case .automatic: "自动适配"
        case .beginner: "入门"
        case .intermediate: "中级"
        case .advanced: "进阶"
        }
    }
}

public struct LearningPreferences: Codable, Equatable, Sendable {
    public var languages: Set<StudyLanguage> = []
    public var level: LearningLevel = .automatic
    public init() {}
    public var promptDescription: String {
        let languages = languages.sorted { $0.rawValue < $1.rawValue }.map(\.promptName).joined(separator: ", ")
        return "Commonly studied languages: \(languages.isEmpty ? "unspecified" : languages). "
            + "These are soft hints, never a language whitelist or proof of the source language. "
            + "Learner level: \(level.rawValue). With automatic level, use clear concise explanations without assuming proficiency."
    }
}

public enum CardReviewPolicy {
    /// Language detection is advisory. Keep uncertainty visible even when automatic saving is enabled.
    public static func prepared(_ original: VocabularyCard, input: CaptureInput, explanationLanguage: AppLanguage) -> VocabularyCard {
        var card = original
        let code = card.sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let validCode = code.range(of: #"^[a-z]{2,3}(-[a-z0-9]{2,8})*$"#, options: .regularExpression) != nil
        let noContext = input.context.isEmpty || normalized(input.context) == normalized(input.text)
        if card.reviewReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { card.needsReview = true }
        let hanOnly = !input.text.isEmpty && input.text.unicodeScalars.allSatisfy {
            (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
                || (0x20000...0x323AF).contains($0.value)
        }
        let reason: String?
        if !validCode || code == "und" || code == "mul" {
            reason = "未能确定词条语言，请检查释义和例句。"
        } else if noContext && hanOnly && input.text.count <= 8 {
            reason = "这个汉字词可能属于中文或日文。缺少原句，请检查语言和词义。"
        } else { reason = nil }
        if let reason {
            card.needsReview = true
            if card.reviewReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                card.reviewReason = L10n.text(reason, language: explanationLanguage)
            }
        }
        if card.needsReview && card.reviewReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            card.reviewReason = L10n.text("词义可能存在歧义，请检查。", language: explanationLanguage)
        }
        return card
    }
}
