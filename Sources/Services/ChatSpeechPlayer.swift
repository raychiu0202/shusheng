import AVFoundation
import Foundation

/// 口语页的单句 TTS：读参考句、读 AI 回复，可被打断。
@MainActor
final class ChatSpeechPlayer: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        AudioSessionCoordinator.shared.activateSpeaking()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = currentVoice()
        utterance.rate = currentRate()
        currentUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    private func currentVoice() -> AVSpeechSynthesisVoice? {
        let stored = UserDefaults.standard.string(forKey: "reader.voiceID") ?? ""
        if !stored.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: stored) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func currentRate() -> Float {
        if let stored = UserDefaults.standard.object(forKey: "reader.rate") as? Double {
            return Float(stored)
        }
        return 0.55
    }
}

extension ChatSpeechPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            self.isSpeaking = false
        }
    }
}
