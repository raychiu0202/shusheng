import SwiftUI
import UIKit

/// 生词本：列表 + 复习入口。释义走系统词典（公开 API），可查但不入库。
struct VocabView: View {
    @EnvironmentObject private var store: VocabStore
    @Environment(\.dismiss) private var dismiss

    @State private var showReview = false
    @State private var dictionaryTerm: String?
    @State private var didAutoStartReview = false

    var body: some View {
        NavigationStack {
            Group {
                if store.words.isEmpty {
                    ContentUnavailableView(
                        "生词本还是空的",
                        systemImage: "character.book.closed",
                        description: Text("阅读时长按选中单词，点「加入生词本」")
                    )
                } else {
                    List {
                        Section {
                            Button {
                                showReview = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "rectangle.on.rectangle.angled")
                                    Text(store.dueCount > 0 ? "开始复习" : "今天已复习完")
                                    Spacer()
                                    Text(store.dueCount > 0 ? "\(store.dueCount) 个待复习" : "共 \(store.words.count) 词")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            }
                            .disabled(store.dueCount == 0)
                        }

                        Section("全部生词") {
                            ForEach(store.words) { word in
                                Button {
                                    dictionaryTerm = word.word
                                } label: {
                                    row(word)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    store.remove(store.words[index])
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("生词本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showReview = true
                    } label: {
                        Label(
                            store.dueCount > 0 ? "复习 \(store.dueCount)" : "复习",
                            systemImage: "rectangle.on.rectangle.angled"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .disabled(store.words.isEmpty)
                }
            }
            .sheet(isPresented: $showReview) {
                VocabReviewView()
            }
            .sheet(isPresented: Binding(
                get: { dictionaryTerm != nil },
                set: { if !$0 { dictionaryTerm = nil } }
            )) {
                DictionarySheet(word: dictionaryTerm ?? "")
            }
            .onAppear {
                // 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_DICT=<单词>` 直接打开查词面板
                if let term = ProcessInfo.processInfo.environment["AUTO_OPEN_DICT"], !term.isEmpty {
                    dictionaryTerm = term
                }
                // 仅用于开发调试：`SIMCTL_CHILD_AUTO_START_REVIEW=1` 启动时直接进入复习
                if ProcessInfo.processInfo.environment["AUTO_START_REVIEW"] == "1",
                   !didAutoStartReview,
                   store.dueCount > 0 {
                    didAutoStartReview = true
                    showReview = true
                }
            }
        }
    }

    private func row(_ word: VocabWord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(word.word)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if word.isDue {
                    Text("待复习")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: "character.book.closed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let definition = word.definition {
                Text(definition)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Text(word.sentenceText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(word.bookTitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// 系统词典（UIKit 公开组件），展示查词释义
struct SystemDictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {}
}

/// 复习卡：先看单词回忆，点卡片翻面看例句；三档自评决定下次复习时间
struct VocabReviewView: View {
    @EnvironmentObject private var store: VocabStore
    @EnvironmentObject private var statsStore: StudyStatsStore
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [VocabWord] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var finished = false
    @State private var dictionaryTerm: String?
    @State private var cardDefinition: String?
    @State private var definitionLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 1.0, green: 0.96, blue: 0.90).ignoresSafeArea()

                if finished {
                    doneView
                } else if let word = currentWord {
                    VStack(spacing: 20) {
                        ProgressView(
                            value: Double(min(index + 1, queue.count)),
                            total: Double(max(queue.count, 1))
                        )
                        .tint(.orange)
                        .padding(.horizontal, 32)

                        Text("\(min(index + 1, queue.count)) / \(queue.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        card(word)
                            .padding(.horizontal, 24)

                        Spacer(minLength: 0)

                        if revealed {
                            ratingButtons(word)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 24)
                        } else {
                            Text("点卡片查看例句")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 32)
                        }
                    }
                    .padding(.top, 12)
                } else {
                    ContentUnavailableView(
                        "今天没有到期生词",
                        systemImage: "checkmark.circle",
                        description: Text("新加入的生词会立即出现在这里")
                    )
                }
            }
            .navigationTitle("复习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: start)
            .sheet(isPresented: Binding(
                get: { dictionaryTerm != nil },
                set: { if !$0 { dictionaryTerm = nil } }
            )) {
                DictionarySheet(word: dictionaryTerm ?? "")
            }
        }
    }

    private var currentWord: VocabWord? {
        guard index >= 0, index < queue.count else { return nil }
        return queue[index]
    }

    private func card(_ word: VocabWord) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                revealed = true
            }
            loadDefinition(for: word)
        } label: {
            VStack(spacing: 16) {
                Text(word.word)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if revealed {
                    Divider()
                    if definitionLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else if let cardDefinition {
                        Text(cardDefinition)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                    }
                    Text(word.sentenceText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(word.bookTitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button {
                        dictionaryTerm = word.word
                    } label: {
                        Label("查看释义", systemImage: "character.book.closed")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
            .padding(24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func ratingButtons(_ word: VocabWord) -> some View {
        HStack(spacing: 12) {
            ratingButton("不认识", tint: .red) {
                grade(word, .again)
            }
            ratingButton("模糊", tint: .orange) {
                grade(word, .hard)
            }
            ratingButton("认识", tint: .green) {
                grade(word, .good)
            }
        }
    }

    private func ratingButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("本轮复习完成")
                .font(.title3.weight(.semibold))
            Text("生词会按熟悉度自动安排下次复习时间")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                dismiss()
            } label: {
                Text("好")
                    .font(.headline)
                    .frame(maxWidth: 160)
                    .padding(.vertical, 12)
                    .background(Color.orange, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)
        }
    }

    private func start() {
        guard queue.isEmpty, !finished else { return }
        queue = store.dueWords
        index = 0
        revealed = false
        cardDefinition = nil
        // 仅用于开发调试：`SIMCTL_CHILD_AUTO_REVEAL=1` 启动时直接翻面
        if ProcessInfo.processInfo.environment["AUTO_REVEAL"] == "1" {
            revealed = true
            cardDefinition = queue.first?.definition
        }
        if queue.isEmpty {
            finished = false
        }
    }

    private func loadDefinition(for word: VocabWord) {
        if let cached = word.definition {
            cardDefinition = cached
            return
        }
        guard cardDefinition == nil, !definitionLoading else { return }
        definitionLoading = true
        Task {
            let entry = try? await DictionaryService.shared.entry(for: word.word)
            guard let entry else {
                definitionLoading = false
                return
            }
            store.updateDefinition(for: word.word, definition: entry.summary)
            if currentWord?.id == word.id {
                cardDefinition = entry.summary
            }
            definitionLoading = false
        }
    }

    private func grade(_ word: VocabWord, _ rating: ReviewRating) {
        store.grade(id: word.id, rating: rating)
        statsStore.record(.vocabReview)
        if rating == .again {
            queue.append(word)   // 本轮稍后再出现一次
        }
        index += 1
        revealed = false
        definitionLoading = false
        cardDefinition = index < queue.count ? queue[index].definition : nil
        if index >= queue.count {
            finished = true
        }
    }
}
