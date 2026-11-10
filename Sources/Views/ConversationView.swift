import SwiftUI
import UIKit

struct ConversationView: View {
    let scenario: SpeakingScenario

    @EnvironmentObject private var speakingStore: SpeakingStore
    @EnvironmentObject private var statsStore: StudyStatsStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recognizer = SpeechRecognizerService()
    @StateObject private var player = ChatSpeechPlayer()
    @AppStorage("speaking.autoSpeak") private var autoSpeak = true

    @State private var tutor: (any SpeakingTutoring)?
    @State private var messages: [ChatMessage] = []
    @State private var isThinking = false
    @State private var correctionLoading = false
    @State private var errorText: String?
    @State private var permissionDenied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            bubble(message)
                        }
                        if isThinking {
                            thinkingBubble
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isThinking) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            inputBar
        }
        .background(Color(red: 1.0, green: 0.97, blue: 0.93).ignoresSafeArea())
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("朗读 AI 回复", isOn: $autoSpeak)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear(perform: startConversation)
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
            Text("请在系统设置中允许书声使用麦克风和语音识别，才能和 AI 对话。")
        }
    }

    // MARK: - 气泡

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .tutor:
            HStack(alignment: .top, spacing: 8) {
                avatar
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onTapGesture {
                        player.speak(message.text)
                    }
                Spacer(minLength: 40)
            }
        case .tip:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.top, 3)
                Text(message.text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var avatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.title2)
            .foregroundStyle(.orange)
            .padding(.top, 2)
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            avatar
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Alex 正在想…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 40)
        }
    }

    // MARK: - 底部操作

    private var inputBar: some View {
        VStack(spacing: 10) {
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if lastUserMessage != nil, !isThinking {
                Button {
                    requestCorrection()
                } label: {
                    Label(correctionLoading ? "纠错中…" : "纠错", systemImage: "checkmark.bubble")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .disabled(correctionLoading || recognizer.isRecording)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(recognizer.isRecording ? .red : .secondary)
                    if recognizer.isRecording, !recognizer.transcript.isEmpty {
                        Text(recognizer.transcript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("说英文，AI 会接着聊")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    toggleMic()
                } label: {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(buttonColor, in: Circle())
                        .shadow(color: buttonColor.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(isThinking || correctionLoading)
                .accessibilityLabel(recognizer.isRecording ? "停止录音" : "开始说话")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var buttonIcon: String {
        if recognizer.isRecording { return "stop.fill" }
        if player.isSpeaking { return "stop.fill" }
        return "mic.fill"
    }

    private var buttonColor: Color {
        recognizer.isRecording || player.isSpeaking ? .red : .orange
    }

    private var statusText: String {
        if recognizer.isRecording { return "正在听…" }
        if player.isSpeaking { return "Alex 正在说话，点一下插话" }
        if isThinking { return "Alex 正在想…" }
        return "点麦克风说话"
    }

    private var lastUserMessage: String? {
        messages.last(where: { $0.role == .user })?.text
    }

    // MARK: - 流程

    private func startConversation() {
        guard messages.isEmpty else { return }
        speakingStore.rememberScenario(scenario.id)

        switch TutorAvailability.current.engine {
        case .online:
            let service = RemoteTutorService()
            service.reset(for: scenario)
            tutor = service
        case .onDevice:
            if #available(iOS 26.0, *) {
                let service = SpeakingTutorService()
                service.reset(for: scenario)
                tutor = service
            }
        case .none:
            break
        }

        messages.append(ChatMessage(role: .tutor, text: scenario.opener))
        speakIfEnabled(scenario.opener)

        // 仅用于开发调试：`SIMCTL_CHILD_AUTO_MOCK_TUTOR_REPLY=...` 画一个完整对话
        if let mock = ProcessInfo.processInfo.environment["AUTO_MOCK_TUTOR_REPLY"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                messages.append(ChatMessage(role: .user, text: "I'd like a latte, please."))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                messages.append(ChatMessage(role: .tutor, text: mock))
            }
        }
    }

    private func toggleMic() {
        if recognizer.isRecording {
            recognizer.stop()
            return
        }
        if player.isSpeaking {
            player.stop()   // 插话：先停掉 AI 的朗读
        }
        errorText = nil

        Task {
            let granted = await SpeechRecognizerService.requestPermission()
            guard granted else {
                permissionDenied = true
                return
            }
            do {
                try recognizer.start { text in
                    handleUserSpeech(text)
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func handleUserSpeech(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            errorText = "没有听清，再说一次。"
            return
        }
        errorText = nil
        messages.append(ChatMessage(role: .user, text: clean))
        Task {
            await generateReply(to: clean)
        }
    }

    private func generateReply(to userText: String) async {
        isThinking = true
        defer { isThinking = false }

        if let mock = ProcessInfo.processInfo.environment["AUTO_MOCK_TUTOR_REPLY"],
           !messages.contains(where: { $0.role == .tutor && $0.text == mock }) {
            messages.append(ChatMessage(role: .tutor, text: mock))
            speakIfEnabled(mock)
            statsStore.record(.chatRound)
            return
        }

        guard let tutor else {
            errorText = TutorError.notReady.localizedDescription
            return
        }
        do {
            let reply = try await tutor.reply(to: userText)
            messages.append(ChatMessage(role: .tutor, text: reply))
            speakIfEnabled(reply)
            statsStore.record(.chatRound)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func requestCorrection() {
        guard let lastUserMessage, let tutor, !correctionLoading else { return }
        correctionLoading = true
        Task {
            defer { correctionLoading = false }
            do {
                let tip = try await tutor.correction(for: lastUserMessage)
                messages.append(ChatMessage(role: .tip, text: tip))
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func speakIfEnabled(_ text: String) {
        guard autoSpeak else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            player.speak(text)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
