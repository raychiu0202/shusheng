import Foundation

/// 书签/高亮存储：Documents/marks.json，按书 ID（完整文件名）聚合
@MainActor
final class MarksStore: ObservableObject {
    @Published private var storage: [String: BookMarks] = [:]

    private let fm = FileManager.default

    private var fileURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("marks.json")
    }

    init() {
        load()
    }

    func marks(for bookID: String) -> BookMarks {
        storage[bookID] ?? BookMarks()
    }

    func toggleBookmark(bookID: String, sentenceIndex: Int, paragraphIndex: Int, text: String) {
        var marks = marks(for: bookID)
        if let index = marks.bookmarks.firstIndex(where: { $0.sentenceIndex == sentenceIndex }) {
            marks.bookmarks.remove(at: index)
        } else {
            marks.bookmarks.append(Bookmark(
                id: UUID(),
                sentenceIndex: sentenceIndex,
                paragraphIndex: paragraphIndex,
                text: text,
                createdAt: Date()
            ))
            marks.bookmarks.sort { $0.sentenceIndex < $1.sentenceIndex }
        }
        set(marks, for: bookID)
    }

    func toggleHighlight(bookID: String, paragraphIndex: Int, location: Int, length: Int, text: String) {
        guard length > 0 else { return }
        var marks = marks(for: bookID)
        if let index = marks.highlights.firstIndex(where: {
            $0.paragraphIndex == paragraphIndex && $0.location == location && $0.length == length
        }) {
            marks.highlights.remove(at: index)
        } else {
            marks.highlights.append(Highlight(
                id: UUID(),
                paragraphIndex: paragraphIndex,
                location: location,
                length: length,
                text: text,
                createdAt: Date()
            ))
            marks.highlights.sort {
                ($0.paragraphIndex, $0.location) < ($1.paragraphIndex, $1.location)
            }
        }
        set(marks, for: bookID)
    }

    func remove(bookmark: Bookmark, bookID: String) {
        var marks = marks(for: bookID)
        marks.bookmarks.removeAll { $0.id == bookmark.id }
        set(marks, for: bookID)
    }

    func remove(highlight: Highlight, bookID: String) {
        var marks = marks(for: bookID)
        marks.highlights.removeAll { $0.id == highlight.id }
        set(marks, for: bookID)
    }

    func removeBook(_ bookID: String) {
        storage[bookID] = nil
        persist()
    }

    // MARK: - 持久化

    private func set(_ marks: BookMarks, for bookID: String) {
        storage[bookID] = marks.isEmpty ? nil : marks
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: BookMarks].self, from: data) else {
            return
        }
        storage = decoded
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(storage)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 存储失败不阻塞阅读流程
        }
    }
}
