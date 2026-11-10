import Foundation

struct SpeakingRecords: Codable {
    var bestScores: [String: Int] = [:]
    var lastScenarioID: String?
}

/// 口语练习记录：每句最好成绩、上次场景，存 Documents/speaking.json
@MainActor
final class SpeakingStore: ObservableObject {
    @Published private(set) var records = SpeakingRecords()

    private let fm = FileManager.default

    private var fileURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("speaking.json")
    }

    init() {
        load()
    }

    func bestScore(for sentence: String) -> Int? {
        records.bestScores[Self.key(for: sentence)]
    }

    func record(score: Int, for sentence: String) {
        let key = Self.key(for: sentence)
        if score > (records.bestScores[key] ?? 0) {
            records.bestScores[key] = score
            persist()
        }
    }

    func rememberScenario(_ id: String) {
        guard records.lastScenarioID != id else { return }
        records.lastScenarioID = id
        persist()
    }

    var lastScenario: SpeakingScenario? {
        SpeakingScenario.scenario(id: records.lastScenarioID)
    }

    private static func key(for sentence: String) -> String {
        String(sentence.prefix(120))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SpeakingRecords.self, from: data) else {
            return
        }
        records = decoded
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 记录失败不影响练习
        }
    }
}
