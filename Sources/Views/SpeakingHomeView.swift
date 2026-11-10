import SwiftUI

struct SpeakingHomeView: View {
    @EnvironmentObject private var speakingStore: SpeakingStore
    @EnvironmentObject private var statsStore: StudyStatsStore

    @State private var path = NavigationPath()
    @State private var practice: PracticeSentence?
    @State private var source = PracticeSentence.fallback[0]
    @State private var fallbackIndex = 0
    @State private var loadedLastRead = false
    @State private var showStats = false

    private let warmBackground = LinearGradient(
        colors: [Color(red: 1.0, green: 0.96, blue: 0.90), .white],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                warmBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        statsCard
                        readAloudCard
                        ScenarioPickerView()
                        Text("语音识别在本机运行；配置在线模型后，对话文字会发送给所选服务商。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("口语")
            .navigationDestination(for: SpeakingScenario.self) { scenario in
                ConversationView(scenario: scenario)
            }
            .sheet(item: $practice) { sentence in
                ReadAloudPracticeView(sentence: sentence)
            }
            .sheet(isPresented: $showStats) {
                StatsView()
            }
        }
        .onAppear {
            loadLastReadIfNeeded()
            openDebugScenarioIfNeeded()
            openDebugPracticeIfNeeded()
            openDebugStatsIfNeeded()
        }
    }

    private var statsCard: some View {
        Button {
            showStats = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("连续 \(statsStore.currentStreak) 天")
                            .font(.body.weight(.semibold))
                        if statsStore.todayActivity > 0 {
                            Text("今日已打卡")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(todaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var todaySummary: String {
        let today = statsStore.today
        var parts: [String] = []
        if today.readAloud > 0 { parts.append("跟读 \(today.readAloud)") }
        if today.vocabReviewed > 0 { parts.append("复习 \(today.vocabReviewed) 词") }
        if today.sentencesListened > 0 { parts.append("朗读 \(today.sentencesListened) 句") }
        if today.chatRounds > 0 { parts.append("对话 \(today.chatRounds) 轮") }
        return parts.isEmpty ? "今天还没练习，开始第一项吧" : "今天：" + parts.joined(separator: " · ")
    }

    private var readAloudCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("跟读练习", systemImage: "waveform.badge.mic")
                    .font(.headline)
                Spacer()
                if let best = speakingStore.bestScore(for: source.text) {
                    Text("最好 \(best) 分")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Text(source.text)
                .font(.title3)
                .lineSpacing(4)
                .lineLimit(4)
                .foregroundStyle(.primary)

            if let book = source.bookTitle {
                Label("来自《\(book)》", systemImage: "book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    practice = source
                } label: {
                    Label("开始跟读", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Color.orange, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                if source.bookTitle == nil {
                    Button {
                        fallbackIndex = (fallbackIndex + 1) % PracticeSentence.fallback.count
                        source = PracticeSentence.fallback[fallbackIndex]
                    } label: {
                        Label("换一句", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }

    private func loadLastReadIfNeeded() {
        guard !loadedLastRead else { return }
        loadedLastRead = true
        if let text = ReadingProgress.lastSentenceText, ReadingProgress.isEnglishSentence(text) {
            source = PracticeSentence(text: text, bookTitle: ReadingProgress.lastBookTitle)
        } else {
            source = PracticeSentence.fallback[fallbackIndex]
        }
    }

    /// 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_STATS=1` 直接打开学习统计
    private func openDebugStatsIfNeeded() {
        guard ProcessInfo.processInfo.environment["AUTO_OPEN_STATS"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showStats = true
        }
    }

    /// 仅用于开发调试：`SIMCTL_CHILD_AUTO_MOCK_TRANSCRIPT="..."` 直接打开跟读页并套用识别结果
    private func openDebugPracticeIfNeeded() {
        guard practice == nil,
              ProcessInfo.processInfo.environment["AUTO_MOCK_TRANSCRIPT"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            practice = source
        }
    }

    /// 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_SCENARIO=<id>` 直接进入对话
    private func openDebugScenarioIfNeeded() {
        guard path.isEmpty,
              let id = ProcessInfo.processInfo.environment["AUTO_OPEN_SCENARIO"],
              let scenario = SpeakingScenario.scenario(id: id) else { return }
        path.append(scenario)
    }
}
