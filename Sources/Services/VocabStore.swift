import Foundation

/// 生词本存储：Documents/vocab.json，全局共享（不随书删除）
@MainActor
final class VocabStore: ObservableObject {
    @Published private(set) var words: [VocabWord] = []

    private let fm = FileManager.default

    /// 各 stage 对应的下次复习间隔
    private static let intervals: [TimeInterval] = [
        12 * 3600,      // 0 → 12 小时
        1 * 86400,      // 1 → 1 天
        2 * 86400,      // 2 → 2 天
        4 * 86400,      // 3 → 4 天
        7 * 86400,      // 4 → 7 天
        15 * 86400,     // 5 → 15 天
        30 * 86400      // 6 → 30 天
    ]

    private var fileURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vocab.json")
    }

    init() {
        load()
    }

    var dueWords: [VocabWord] {
        words.filter(\.isDue).sorted { $0.createdAt < $1.createdAt }
    }

    var dueCount: Int {
        words.reduce(0) { $0 + ($1.isDue ? 1 : 0) }
    }

    /// 加入生词本；已存在（忽略大小写）则返回 false
    @discardableResult
    func add(
        word: String,
        sentenceText: String,
        bookID: String,
        bookTitle: String,
        sentenceIndex: Int,
        paragraphIndex: Int
    ) -> Bool {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        guard !words.contains(where: {
            $0.word.caseInsensitiveCompare(clean) == .orderedSame
        }) else { return false }

        words.append(VocabWord(
            id: UUID(),
            word: String(clean.prefix(60)),
            sentenceText: sentenceText,
            definition: nil,
            bookID: bookID,
            bookTitle: bookTitle,
            paragraphIndex: paragraphIndex,
            sentenceIndex: sentenceIndex,
            createdAt: Date(),
            stage: 0,
            lastReviewed: nil,
            nextReview: Date()
        ))
        sortAndPersist()
        return true
    }

    func grade(id: UUID, rating: ReviewRating) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        var word = words[index]
        let now = Date()
        switch rating {
        case .again:
            word.stage = 0
            word.nextReview = now.addingTimeInterval(10 * 60)
        case .hard:
            word.stage = max(0, word.stage - 1)
            word.nextReview = now.addingTimeInterval(12 * 3600)
        case .good:
            word.stage = min(word.stage + 1, Self.intervals.count - 1)
            word.nextReview = now.addingTimeInterval(Self.intervals[word.stage])
        }
        word.lastReviewed = now
        words[index] = word
        persist()
    }

    /// 联网查到释义后回填（忽略大小写匹配）
    func updateDefinition(for word: String, definition: String) {
        let clean = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var changed = false
        for index in words.indices where words[index].word.caseInsensitiveCompare(word) == .orderedSame {
            if words[index].definition != clean {
                words[index].definition = clean
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    func remove(_ word: VocabWord) {
        words.removeAll { $0.id == word.id }
        persist()
    }

    // MARK: - 持久化

    private func sortAndPersist() {
        words.sort { $0.createdAt < $1.createdAt }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VocabWord].self, from: data) else {
            return
        }
        words = decoded
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(words)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 存储失败不阻塞阅读流程
        }
    }
}
