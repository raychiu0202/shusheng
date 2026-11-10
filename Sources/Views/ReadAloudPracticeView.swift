import SwiftUI
import UIKit

struct ReadAloudPracticeView: View {
    let sentence: PracticeSentence

    @EnvironmentObject private var speakingStore: SpeakingStore
    @EnvironmentObject private var statsStore: StudyStatsStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recognizer = SpeechRecognizerService()
    @StateObject private var player = ChatSpeechPlayer()

    @State private var result: ReadAloudResult?
    @State private var errorText: String?
    @State private var permissionDenied = false
    @State private var mockMode = false

    private var targetWords: [String] {
        sentence.text.split(whereSeparator: { $0.isWhitespace }).compactMap {
            let word = String($0).trimmingCharacters(in: .punctuationCharacters)
            return word.isEmpty ? nil : word
        }
    }

    private var scoreColor: Color {
        guard let score = result?.score else { return .orange }
        switch score {
        case 90...: return .green
        case 75..<90: return .orange
        case 60..<75: return .orange
        default: return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    targetCard
                    statusSection
                    if let result {
                        scoreSection(result)
                    }
                    controls
                    if let transcript = result?.transcript, !transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("你说的")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(transcript)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let best = speakingStore.bestScore(for: sentence.text) {
                        Text("本句最好成绩：\(best) 分")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
            }
            .background(Color(red: 1.0, green: 0.96, blue: 0.90).ignoresSafeArea())
            .navigationTitle("跟读练习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: startMockIfNeeded)
            .onDisappear {
                recognizer.cancel()
                player.stop()
                AudioSessionCoordinator.shared.restoreReaderPlayback()
            }
            .alert("需要麦克风和语音识别权限", isPresented: $permissionDenied) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在系统设置中允许书声使用麦克风和语音识别，才能给你打分。")
            }
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let book = sentence.bookTitle {
                Label("来自《\(book)》", systemImage: "book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let result {
                TokenFlow(spacing: 6, lineSpacing: 8) {
                    ForEach(result.tokens) { token in
                        tokenText(token)
                    }
                }
            } else {
                TokenFlow(spacing: 6, lineSpacing: 8) {
                    ForEach(Array(targetWords.enumerated()), id: \.offset) { _, word in
                        Text(word)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private func tokenText(_ token: ReadAloudToken) -> some View {
        let color: Color
        switch token.status {
        case .correct: color = .green
        case .misrecognized: color = .orange
        case .missing: color = .red
        }
        return Text(token.word)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(color)
            .underline(token.status == .misrecognized)
            .strikethrough(token.status == .missing)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if recognizer.isRecording {
                Label("正在听…请读出上面的句子", systemImage: "waveform")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                if !recognizer.transcript.isEmpty {
                    Text(recognizer.transcript)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if result == nil {
                Text("点下面的麦克风，匀速读出整句。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scoreSection(_ result: ReadAloudResult) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(result.score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(result.score)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text("分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 6) {
                Text(result.verdict)
                    .font(.title3.weight(.semibold))
                Text("绿色读对，橙色识别偏差，红色漏读")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            smallButton(
                icon: player.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill",
                title: "参考朗读"
            ) {
                if player.isSpeaking {
                    player.stop()
                } else {
                    player.speak(sentence.text)
                }
            }

            Button {
                toggleRecording()
            } label: {
                Image(systemName: recognizer.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(
                        recognizer.isRecording ? Color.red : Color.orange,
                        in: Circle()
                    )
                    .shadow(color: .orange.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recognizer.isRecording ? "停止录音" : "开始跟读")

            smallButton(icon: "arrow.counterclockwise", title: "重试") {
                result = nil
                errorText = nil
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func smallButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(.orange)
            .frame(width: 64, height: 64)
            .background(Color.orange.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRecording() {
        if recognizer.isRecording {
            recognizer.stop()
            return
        }
        player.stop()
        result = nil
        errorText = nil

        if mockMode {
            if let mock = ProcessInfo.processInfo.environment["AUTO_MOCK_TRANSCRIPT"] {
                apply(mock)
            }
            return
        }

        Task {
            let granted = await SpeechRecognizerService.requestPermission()
            guard granted else {
                permissionDenied = true
                return
            }
            do {
                try recognizer.start { text in
                    apply(text)
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func apply(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            result = nil
            errorText = "没有听清，再说一次。"
            return
        }
        errorText = nil
        let scored = PronunciationScorer.score(target: sentence.text, transcript: clean)
        result = scored
        speakingStore.record(score: scored.score, for: sentence.text)
        statsStore.record(.readAloud)
    }

    private func startMockIfNeeded() {
        guard let mock = ProcessInfo.processInfo.environment["AUTO_MOCK_TRANSCRIPT"] else { return }
        mockMode = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            apply(mock)
        }
    }
}

/// 逐词换行布局
struct TokenFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
