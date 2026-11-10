import Foundation

/// 生词本条目：单词 + 原文例句 + 出处，复习进度按 stage 递进
struct VocabWord: Codable, Identifiable, Equatable {
    let id: UUID
    let word: String
    let sentenceText: String    // 收藏时的原句，作为复习语境
    var definition: String?     // 联网查到的一行释义（可缺省，旧数据兼容）
    let bookID: String
    let bookTitle: String
    let paragraphIndex: Int
    let sentenceIndex: Int
    let createdAt: Date
    var stage: Int              // 熟悉度 0–6，越大复习间隔越长
    var lastReviewed: Date?
    var nextReview: Date?

    var isDue: Bool {
        guard let nextReview else { return true }
        return nextReview <= Date()
    }
}

enum ReviewRating {
    case again   // 不认识
    case hard    // 模糊
    case good    // 认识
}
