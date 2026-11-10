import SwiftUI

struct MarksSheet: View {
    let marks: BookMarks
    let chapters: [Chapter]
    let onSelectBookmark: (Bookmark) -> Void
    let onSelectHighlight: (Highlight) -> Void
    let onDeleteBookmark: (Bookmark) -> Void
    let onDeleteHighlight: (Highlight) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if marks.isEmpty {
                    ContentUnavailableView(
                        "还没有标记",
                        systemImage: "bookmark",
                        description: Text("播放时点底部书签按钮收藏好句；长按正文选中文字可以高亮")
                    )
                } else {
                    List {
                        if !marks.bookmarks.isEmpty {
                            Section("书签") {
                                ForEach(marks.bookmarks) { bookmark in
                                    Button {
                                        onSelectBookmark(bookmark)
                                    } label: {
                                        row(
                                            icon: "bookmark.fill",
                                            tint: .orange,
                                            text: bookmark.text,
                                            caption: chapterTitle(for: bookmark.paragraphIndex)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        onDeleteBookmark(marks.bookmarks[index])
                                    }
                                }
                            }
                        }
                        if !marks.highlights.isEmpty {
                            Section("高亮") {
                                ForEach(marks.highlights) { highlight in
                                    Button {
                                        onSelectHighlight(highlight)
                                    } label: {
                                        row(
                                            icon: "highlighter",
                                            tint: .yellow,
                                            text: highlight.text,
                                            caption: chapterTitle(for: highlight.paragraphIndex)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        onDeleteHighlight(marks.highlights[index])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("我的标记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(icon: String, tint: Color, text: String, caption: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(tint)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func chapterTitle(for paragraphIndex: Int) -> String? {
        chapters.last(where: { $0.paragraphIndex <= paragraphIndex })?.title
    }
}
