import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var store = BookStore()
    @EnvironmentObject private var marksStore: MarksStore
    @State private var showImporter = false
    @State private var importError: String?
    @State private var showImportHelp = false
    @State private var showVocab = false
    @State private var path: [Book] = []

    private let warmBackground = LinearGradient(
        colors: [Color(red: 1.0, green: 0.96, blue: 0.90), .white],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                warmBackground.ignoresSafeArea()

                if store.books.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book)
            }
            .navigationTitle("书库")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showVocab = true
                    } label: {
                        Image(systemName: "character.book.closed")
                    }
                    .accessibilityLabel("生词本")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("从「文件」App 导入", systemImage: "folder")
                        }
                        Button {
                            showImportHelp = true
                        } label: {
                            Label("如何导入书籍？", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                    .accessibilityLabel("导入书籍")
                    .alert("如何导入书籍", isPresented: $showImportHelp) {
                        Button("好", role: .cancel) {}
                    } message: {
                        Text("1. 微信 / QQ 等：打开文件 → 右上角「…」→ 用其他应用打开 → 书声\n2. 「文件」App：把书存到 iCloud 云盘或「我的 iPhone」，再点 + 导入\n3. 也可以直接用数据线或隔空投送传到「文件」App\n\n支持格式：TXT / EPUB / MOBI")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importableTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try store.importBook(from: url)
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(isPresented: $showVocab) {
                VocabView()
            }
        }
        .onOpenURL { url in
            importIncoming(url)
        }
        .onAppear {
            openBookFromLaunchEnvironmentIfNeeded()
        }
    }

    /// 从微信等 App「用其他应用打开」进来的文件
    private func importIncoming(_ url: URL) {
        do {
            let book = try store.importBook(from: url)
            path = [book]
            // 系统 Inbox 里的临时副本已拷贝进 Books，删掉避免重复占空间
            if url.path.contains("/Documents/Inbox/") {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    private var importableTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        for ext in ["epub", "mobi", "prc"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    /// 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_BOOK=<书名>` 启动时直接打开对应书籍
    private func openBookFromLaunchEnvironmentIfNeeded() {
        // 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_VOCAB=1` 启动时直接弹出生词本
        if ProcessInfo.processInfo.environment["AUTO_OPEN_VOCAB"] == "1" {
            showVocab = true
            return
        }
        guard path.isEmpty,
              let title = ProcessInfo.processInfo.environment["AUTO_OPEN_BOOK"],
              let book = store.books.first(where: { $0.title == title }) else { return }
        path = [book]
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.pages")
                .font(.system(size: 56))
                .foregroundStyle(.orange.opacity(0.7))
            Text("还没有书")
                .font(.title3.weight(.semibold))
            Text("点右上角 + 从「文件」导入，\n或在微信里用其他应用打开 TXT / EPUB / MOBI")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var bookList: some View {
        List {
            ForEach(store.books) { book in
                NavigationLink(value: book) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [.orange, .orange.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 40, height: 52)
                            .overlay {
                                Image(systemName: "text.book.closed.fill")
                                    .foregroundStyle(.white)
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(.body.weight(.medium))
                                .lineLimit(2)
                            Text(book.formatLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteBook(book)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    deleteBook(store.books[index])
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// 删除书籍及其进度、书签、高亮
    private func deleteBook(_ book: Book) {
        store.delete(book)
        marksStore.removeBook(book.id)
        ReadingProgress.clear(for: book.id)
    }
}

#Preview {
    LibraryView()
        .environmentObject(MarksStore())
        .environmentObject(VocabStore())
}
