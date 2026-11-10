import Foundation

struct DictExample: Codable, Equatable {
    let en: String
    let zh: String?
}

struct DictEntry: Codable, Equatable {
    let word: String
    let phonetic: String?
    var translations: [String]   // 中文释义
    var definitions: [String]    // 英文释义
    var examples: [DictExample]
    var source: String

    /// 存进生词本的一行释义
    var summary: String {
        if !translations.isEmpty {
            return translations.prefix(2).joined(separator: "；")
        }
        return definitions.prefix(2).joined(separator: "；")
    }
}

enum DictError: LocalizedError {
    case notFound
    case network

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "没有查到这个词，换个写法试试，或打开系统词典查看"
        case .network:
            return "网络不太好，稍后重试，或打开系统词典查看"
        }
    }
}

/// 联网词典：有道 jsonapi（中英释义、音标、双语例句）+ dictionaryapi.dev 兜底。
/// 查询结果缓存在 Documents/dict_cache.json，重复查词不再走网络。
@MainActor
final class DictionaryService: ObservableObject {
    static let shared = DictionaryService()

    private let fm = FileManager.default
    private var cache: [String: DictEntry] = [:]
    private var loaded = false

    private var cacheURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dict_cache.json")
    }

    private init() {}

    func cachedEntry(for word: String) -> DictEntry? {
        loadCacheIfNeeded()
        return cache[Self.normalize(word)]
    }

    func entry(for word: String) async throws -> DictEntry {
        let key = Self.normalize(word)
        guard !key.isEmpty else { throw DictError.notFound }
        loadCacheIfNeeded()
        if let hit = cache[key] {
            return hit
        }

        if let youdao = try? await fetchYoudao(key), !youdao.translations.isEmpty || !youdao.definitions.isEmpty {
            store(youdao, key: key)
            return youdao
        }
        if let free = try? await fetchDictionaryAPI(key), !free.definitions.isEmpty {
            store(free, key: key)
            return free
        }
        throw DictError.notFound
    }

    // MARK: - 有道

    private func fetchYoudao(_ word: String) async throws -> DictEntry {
        var components = URLComponents(string: "https://dict.youdao.com/jsonapi")!
        components.queryItems = [URLQueryItem(name: "q", value: word)]
        let data = try await request(components.url!)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DictError.notFound
        }

        var phonetic: String?
        var translations: [String] = []
        var definitions: [String] = []
        var examples: [DictExample] = []

        if let ec = root["ec"] as? [String: Any],
           let words = ec["word"] as? [[String: Any]],
           let primary = words.first {
            phonetic = Self.clean(primary["usphone"] as? String)
                ?? Self.clean(primary["ukphone"] as? String)
            for group in primary["trs"] as? [[String: Any]] ?? [] {
                for tr in group["tr"] as? [[String: Any]] ?? [] {
                    if let l = tr["l"] as? [String: Any] {
                        translations += Self.strings(from: l["i"])
                    }
                }
            }
        }

        if let ee = root["ee"] as? [String: Any],
           let wordInfo = ee["word"] as? [String: Any] {
            for group in wordInfo["trs"] as? [[String: Any]] ?? [] {
                let pos = group["pos"] as? String
                for tr in group["tr"] as? [[String: Any]] ?? [] {
                    if let l = tr["l"] as? [String: Any] {
                        for text in Self.strings(from: l["i"]) {
                            definitions.append(pos.map { "\($0) \(text)" } ?? text)
                        }
                    }
                }
            }
        }

        if let part = root["blng_sents_part"] as? [String: Any],
           let pairs = part["sentence-pair"] as? [[String: Any]] {
            for pair in pairs.prefix(3) {
                let en = Self.stripHTML(pair["sentence-eng"] as? String
                    ?? pair["sentence"] as? String ?? "")
                guard !en.isEmpty else { continue }
                examples.append(DictExample(
                    en: en,
                    zh: Self.clean(pair["sentence-translation"] as? String)
                ))
            }
        }

        return DictEntry(
            word: word,
            phonetic: phonetic,
            translations: Array(translations.prefix(6)),
            definitions: Array(definitions.prefix(6)),
            examples: examples,
            source: "有道词典"
        )
    }

    // MARK: - dictionaryapi.dev（英文释义兜底）

    private struct APIEntry: Decodable {
        struct Meaning: Decodable {
            struct Definition: Decodable {
                let definition: String
                let example: String?
            }
            let partOfSpeech: String?
            let definitions: [Definition]
        }
        let word: String
        let phonetic: String?
        let meanings: [Meaning]
    }

    private func fetchDictionaryAPI(_ word: String) async throws -> DictEntry {
        let escaped = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(escaped)")!
        let data = try await request(url)
        let entries = try JSONDecoder().decode([APIEntry].self, from: data)
        guard let first = entries.first else { throw DictError.notFound }

        var definitions: [String] = []
        var examples: [DictExample] = []
        for meaning in first.meanings {
            for definition in meaning.definitions {
                let prefix = meaning.partOfSpeech.map { "\($0) " } ?? ""
                definitions.append(prefix + definition.definition)
                if let example = definition.example, examples.count < 3 {
                    examples.append(DictExample(en: example, zh: nil))
                }
            }
        }
        return DictEntry(
            word: first.word,
            phonetic: Self.clean(first.phonetic),
            translations: [],
            definitions: Array(definitions.prefix(6)),
            examples: examples,
            source: "dictionaryapi.dev"
        )
    }

    // MARK: - 网络 / 缓存

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw DictError.network
            }
            return data
        } catch let error as DictError {
            throw error
        } catch {
            throw DictError.network
        }
    }

    private func store(_ entry: DictEntry, key: String) {
        loadCacheIfNeeded()
        cache[key] = entry
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func loadCacheIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: DictEntry].self, from: data) else {
            return
        }
        cache = decoded
    }

    // MARK: - 工具

    private static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
            .lowercased()
    }

    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strings(from value: Any?) -> [String] {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        if let list = value as? [Any] {
            return list.flatMap { strings(from: $0) }
        }
        return []
    }
}
