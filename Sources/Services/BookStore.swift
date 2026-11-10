import Foundation

enum BookStoreError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        "不支持的文件类型，仅支持 TXT / EPUB / MOBI"
    }
}

@MainActor
final class BookStore: ObservableObject {
    @Published private(set) var books: [Book] = []

    private let fm = FileManager.default

    var booksDirectory: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Books", isDirectory: true)
    }

    init() {
        refresh()
    }

    static let supportedExtensions: Set<String> = ["txt", "epub", "mobi", "prc"]

    func refresh() {
        ensureDirectory()
        ingestLooseFiles()
        let urls = (try? fm.contentsOfDirectory(at: booksDirectory, includingPropertiesForKeys: nil)) ?? []
        books = urls
            .filter {
                Self.supportedExtensions.contains($0.pathExtension.lowercased())
                    && !$0.lastPathComponent.hasPrefix(".")
            }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return Book(id: url.lastPathComponent, url: url, title: name)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    @discardableResult
    func importBook(from url: URL) throws -> Book {
        ensureDirectory()
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let title = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased().isEmpty ? "txt" : url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw BookStoreError.unsupportedFormat
        }
        let destination = uniqueURL(for: title, ext: ext)
        try fm.copyItem(at: url, to: destination)
        refresh()
        return Book(id: destination.lastPathComponent, url: destination, title: title)
    }

    func delete(_ book: Book) {
        try? fm.removeItem(at: book.url)
        refresh()
    }

    /// 用户在「文件」App 里直接把电子书拖进书声的 Documents 根目录时，自动收进 Books
    private func ingestLooseFiles() {
        let documents = booksDirectory.deletingLastPathComponent()
        let urls = (try? fm.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                continue
            }
            let title = url.deletingPathExtension().lastPathComponent
            let destination = uniqueURL(for: title, ext: ext)
            try? fm.moveItem(at: url, to: destination)
        }
    }

    private func ensureDirectory() {
        try? fm.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
    }

    private func uniqueURL(for title: String, ext: String) -> URL {
        var candidate = booksDirectory.appendingPathComponent("\(title).\(ext)")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = booksDirectory.appendingPathComponent("\(title) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
