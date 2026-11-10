import SwiftUI

struct TOCSheet: View {
    let chapters: [Chapter]
    let currentChapterID: Int?
    let onSelect: (Chapter) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView(
                        "没有识别到章节",
                        systemImage: "list.bullet.indent",
                        description: Text("这本书没有目录信息，按普通文本阅读即可")
                    )
                } else {
                    List(chapters) { chapter in
                        Button {
                            onSelect(chapter)
                        } label: {
                            HStack(spacing: 10) {
                                Text(chapter.title)
                                    .fontWeight(chapter.id == currentChapterID ? .semibold : .regular)
                                    .foregroundStyle(chapter.id == currentChapterID ? Color.orange : Color.primary)
                                    .lineLimit(2)
                                    .padding(.leading, CGFloat(min(chapter.level, 3) - 1) * 16)
                                Spacer()
                                if chapter.id == currentChapterID {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
