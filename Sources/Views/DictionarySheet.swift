import SwiftUI
import UIKit

/// 联网查词面板：先看本地缓存，没有就联网（有道 → dictionaryapi.dev）。
/// 查到后回填到生词本条目，并保留「系统词典」兜底入口。
struct DictionarySheet: View {
    let word: String

    @EnvironmentObject private var vocabStore: VocabStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = DictionaryService.shared

    @State private var entry: DictEntry?
    @State private var errorText: String?
    @State private var loading = true
    @State private var showSystemDictionary = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("查询中…")
                } else if let entry {
                    content(entry)
                } else {
                    errorView
                }
            }
            .navigationTitle("查词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSystemDictionary = true
                    } label: {
                        Image(systemName: "character.book.closed")
                    }
                    .accessibilityLabel("系统词典")
                }
            }
            .task { await load() }
            .sheet(isPresented: $showSystemDictionary) {
                SystemDictionaryView(term: word)
                    .ignoresSafeArea()
            }
        }
    }

    private func content(_ entry: DictEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.word)
                        .font(.largeTitle.bold())
                    if let phonetic = entry.phonetic {
                        Text("/\(phonetic)/")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !entry.translations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entry.translations, id: \.self) { line in
                            Text(line)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                }

                if !entry.definitions.isEmpty {
                    section("英文释义", lines: entry.definitions)
                }

                if !entry.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("例句")
                            .font(.headline)
                        ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(example.en)
                                    .foregroundStyle(.primary)
                                if let zh = example.zh {
                                    Text(zh)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                            .textSelection(.enabled)
                        }
                    }
                }

                Text("释义来源：\(entry.source)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(errorText ?? "查询失败")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("重试") {
                    Task { await load() }
                }
                Button("用系统词典") {
                    showSystemDictionary = true
                }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
    }

    private func load() async {
        if let cached = service.cachedEntry(for: word) {
            entry = cached
            errorText = nil
            loading = false
            return
        }

        loading = true
        errorText = nil
        do {
            let result = try await service.entry(for: word)
            entry = result
            vocabStore.updateDefinition(for: word, definition: result.summary)
        } catch {
            entry = nil
            errorText = error.localizedDescription
        }
        loading = false
    }
}
