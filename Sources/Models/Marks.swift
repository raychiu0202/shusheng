import Foundation

struct Bookmark: Codable, Identifiable, Equatable {
    let id: UUID
    let sentenceIndex: Int      // 全书扁平句子序号
    let paragraphIndex: Int
    let text: String            // 句子快照，书籍变更后仍可展示
    let createdAt: Date
}

struct Highlight: Codable, Identifiable, Equatable {
    let id: UUID
    let paragraphIndex: Int
    let location: Int           // 段落文本中的 UTF-16 起始位置
    let length: Int
    let text: String            // 选中文本快照
    let createdAt: Date
}

struct BookMarks: Codable {
    var bookmarks: [Bookmark] = []
    var highlights: [Highlight] = []

    var isEmpty: Bool {
        bookmarks.isEmpty && highlights.isEmpty
    }
}
