import AVFoundation
import Foundation
import Speech

enum SpeechRecognizerError: LocalizedError {
    case notAvailable
    case onDeviceUnsupported
    case audioFormat
    case engineFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "语音识别暂不可用，请稍后重试"
        case .onDeviceUnsupported:
            return "此设备暂不支持离线语音识别"
        case .audioFormat:
            return "麦克风没有准备好，请重试"
        case .engineFailed:
            return "录音启动失败，请重试"
        }
    }
}

/// 端侧语音识别（en-US）：开始/停止录音，实时返回字幕，静音自动结束。
@MainActor
final class SpeechRecognizerService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var tapInstalled = false
    private var onFinish: ((String) -> Void)?

    private var startedAt = Date()
    private var lastHeardAt = Date()
    private var heardSpeech = false

    var isAvailable: Bool {
        recognizer?.isAvailable == true
    }

    var supportsOnDevice: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func start(onFinish: @escaping (String) -> Void) throws {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognizerError.notAvailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechRecognizerError.onDeviceUnsupported
        }

        self.onFinish = onFinish
        transcript = ""
        heardSpeech = false
        startedAt = Date()
        lastHeardAt = startedAt

        AudioSessionCoordinator.shared.activateSpeaking()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            AudioSessionCoordinator.shared.restoreReaderPlayback()
            throw SpeechRecognizerError.audioFormat
        }
        if tapInstalled {
            input.removeTap(onBus: 0)
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cleanUpAudio()
            AudioSessionCoordinator.shared.restoreReaderPlayback()
            throw SpeechRecognizerError.engineFailed
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error)
            }
        }

        isRecording = true
        startSilenceTimer()
    }

    /// 用户手动停止：把已识别的内容交回去
    func stop() {
        guard isRecording else { return }
        complete(with: transcript)
    }

    /// 页面消失：丢弃本次识别
    func cancel() {
        onFinish = nil
        cleanUpAudio()
        isRecording = false
        transcript = ""
        AudioSessionCoordinator.shared.restoreReaderPlayback()
    }

    // MARK: - 内部

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        guard isRecording else { return }
        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            transcript = text
            if !text.isEmpty {
                heardSpeech = true
                lastHeardAt = Date()
            }
            if result.isFinal {
                complete(with: text)
                return
            }
        }
        if error != nil {
            complete(with: heardSpeech ? transcript : "")
        }
    }

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                let now = Date()
                if self.heardSpeech {
                    if now.timeIntervalSince(self.lastHeardAt) > 1.8 {
                        self.complete(with: self.transcript)
                    }
                } else if now.timeIntervalSince(self.startedAt) > 8 {
                    self.complete(with: "")
                }
            }
        }
    }

    private func complete(with text: String) {
        guard isRecording || task != nil else { return }
        let callback = onFinish
        onFinish = nil
        isRecording = false
        cleanUpAudio()
        AudioSessionCoordinator.shared.restoreReaderPlayback()
        callback?(text)
    }

    private func cleanUpAudio() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}
