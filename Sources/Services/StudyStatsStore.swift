import Foundation

/// 一天的学习记录
struct DayStats: Codable {
    var readAloud = 0        // 跟读次数
    var vocabReviewed = 0    // 复习卡片数
    var sentencesListened = 0 // 朗读句数
    var chatRounds = 0       // 对话轮数

    var activity: Int {
        readAloud + vocabReviewed + sentencesListened + chatRounds
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readAloud = try container.decodeIfPresent(Int.self, forKey: .readAloud) ?? 0
        vocabReviewed = try container.decodeIfPresent(Int.self, forKey: .vocabReviewed) ?? 0
        sentencesListened = try container.decodeIfPresent(Int.self, forKey: .sentencesListened) ?? 0
        chatRounds = try container.decodeIfPresent(Int.self, forKey: .chatRounds) ?? 0
    }
}

enum StudyActivity {
    case readAloud
    case vocabReview
    case sentenceListened
    case chatRound
}

/// 学习打卡：按天累计，存 Documents/study_stats.json
@MainActor
final class StudyStatsStore: ObservableObject {
    @Published private(set) var days: [String: DayStats] = [:]

    private let fm = FileManager.default
    private let calendar = Calendar.current
    private var pendingSave: DispatchWorkItem?

    private var fileURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("study_stats.json")
    }

    init() {
        load()
        // 仅用于开发调试：`SIMCTL_CHILD_AUTO_SEED_STATS=1` 填充最近三周示例数据
        if ProcessInfo.processInfo.environment["AUTO_SEED_STATS"] == "1", days.isEmpty {
            seedDebugData()
        }
    }

    func record(_ activity: StudyActivity, amount: Int = 1, date: Date = Date()) {
        guard amount > 0 else { return }
        let key = Self.key(for: date, calendar: calendar)
        var day = days[key] ?? DayStats()
        switch activity {
        case .readAloud: day.readAloud += amount
        case .vocabReview: day.vocabReviewed += amount
        case .sentenceListened: day.sentencesListened += amount
        case .chatRound: day.chatRounds += amount
        }
        days[key] = day
        scheduleSave()
    }

    func stats(on date: Date) -> DayStats {
        days[Self.key(for: date, calendar: calendar)] ?? DayStats()
    }

    var today: DayStats {
        stats(on: Date())
    }

    var todayActivity: Int {
        today.activity
    }

    /// 连续练习天数：今天练过从今天算；今天还没练但昨天练过，连续记录仍算继续
    var currentStreak: Int {
        var date = calendar.startOfDay(for: Date())
        if !hasActivity(on: date) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
                  hasActivity(on: yesterday) else { return 0 }
            date = yesterday
        }
        var streak = 0
        while hasActivity(on: date) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return streak
    }

    var totalActiveDays: Int {
        days.values.filter { $0.activity > 0 }.count
    }

    var totalVocabReviewed: Int {
        days.values.reduce(0) { $0 + $1.vocabReviewed }
    }

    var totalReadAloud: Int {
        days.values.reduce(0) { $0 + $1.readAloud }
    }

    var totalChatRounds: Int {
        days.values.reduce(0) { $0 + $1.chatRounds }
    }

    var totalSentencesListened: Int {
        days.values.reduce(0) { $0 + $1.sentencesListened }
    }

    /// 热力图强度（0–4）
    func level(for day: DayStats) -> Int {
        let points = day.readAloud * 5 + day.vocabReviewed * 3
            + day.chatRounds * 2 + day.sentencesListened
        switch points {
        case 0: return 0
        case 1..<10: return 1
        case 10..<30: return 2
        case 30..<80: return 3
        default: return 4
        }
    }

    private func hasActivity(on date: Date) -> Bool {
        stats(on: date).activity > 0
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    // MARK: - 持久化

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persist()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) else {
            return
        }
        days = decoded
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(days)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 统计失败不影响练习
        }
    }

    private func seedDebugData() {
        let samples = [6, 18, 3, 0, 25, 9, 0, 0, 14, 40, 7, 2, 0, 12, 33, 5, 8, 0, 21, 4]
        for (offset, value) in samples.enumerated() {
            guard let date = calendar.date(
                byAdding: .day,
                value: -(samples.count - offset),
                to: Date()
            ) else { continue }
            let key = Self.key(for: date, calendar: calendar)
            var day = DayStats()
            day.sentencesListened = value
            day.vocabReviewed = value / 6
            day.readAloud = value / 10
            day.chatRounds = value / 15
            days[key] = day
        }
        var today = DayStats()
        today.readAloud = 3
        today.vocabReviewed = 8
        today.sentencesListened = 26
        today.chatRounds = 4
        days[Self.key(for: Date(), calendar: calendar)] = today
        persist()
    }
}
