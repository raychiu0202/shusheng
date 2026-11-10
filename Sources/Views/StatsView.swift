import SwiftUI

/// 学习统计：连续打卡、今日/累计数据、近 16 周热力图
struct StatsView: View {
    @EnvironmentObject private var store: StudyStatsStore
    @Environment(\.dismiss) private var dismiss

    private struct DayCell {
        let date: Date
        let stats: DayStats
        let isFuture: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    streakCard
                    summaryGrid
                    heatmapCard
                }
                .padding(20)
            }
            .background(Color(red: 1.0, green: 0.96, blue: 0.90).ignoresSafeArea())
            .navigationTitle("学习统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 打卡

    private var streakCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("连续 \(store.currentStreak) 天")
                    .font(.title2.weight(.bold))
                Text(store.todayActivity > 0
                     ? "今天已完成 \(store.todayActivity) 次练习，继续保持"
                     : "今天还没练习，开始第一项吧")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            statTile("今日练习", value: "\(store.todayActivity) 次", icon: "sun.max.fill")
            statTile("累计学习", value: "\(store.totalActiveDays) 天", icon: "calendar")
            statTile("跟读", value: "\(store.totalReadAloud) 次", icon: "waveform")
            statTile("对话", value: "\(store.totalChatRounds) 轮", icon: "bubble.left.and.bubble.right.fill")
            statTile("复习生词", value: "\(store.totalVocabReviewed) 次", icon: "rectangle.on.rectangle.angled")
            statTile("朗读", value: "\(store.totalSentencesListened) 句", icon: "book.fill")
        }
    }

    private func statTile(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 热力图

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近 16 周")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(store.totalActiveDays) 天有练习")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(heatmapWeeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 3) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(cell.isFuture ? Color.clear : color(store.level(for: cell.stats)))
                                    .frame(width: 13, height: 13)
                                    .accessibilityLabel(accessibilityText(cell))
                            }
                        }
                    }
                }
            }

            HStack(spacing: 5) {
                Text("少")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(level))
                        .frame(width: 11, height: 11)
                }
                Text("多")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private var heatmapWeeks: [[DayCell]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // weekday: 1=周日 … 7=周六；换算成周一开头
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today),
              let firstMonday = calendar.date(byAdding: .day, value: -7 * 15, to: monday) else {
            return []
        }
        return (0..<16).map { week in
            (0..<7).map { day in
                let date = calendar.date(
                    byAdding: .day,
                    value: week * 7 + day,
                    to: firstMonday
                ) ?? firstMonday
                return DayCell(
                    date: date,
                    stats: store.stats(on: date),
                    isFuture: date > today
                )
            }
        }
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case 0: return Color.black.opacity(0.06)
        case 1: return Color.orange.opacity(0.22)
        case 2: return Color.orange.opacity(0.42)
        case 3: return Color.orange.opacity(0.68)
        default: return .orange
        }
    }

    private func accessibilityText(_ cell: DayCell) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let dateText = formatter.string(from: cell.date)
        if cell.isFuture { return dateText }
        let activity = cell.stats.activity
        return activity == 0 ? "\(dateText) 没有练习" : "\(dateText) 练习 \(activity) 次"
    }
}
