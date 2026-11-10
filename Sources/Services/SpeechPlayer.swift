import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class SpeechPlayer: NSObject, ObservableObject {
    @Published private(set) var currentSentenceIndex: Int?
    @Published private(set) var isPlaying = false
    @Published var rate: Float = 0.55
    /// 用户选择的英文语音标识；空字符串表示系统默认美音
    var voiceIdentifier: String = ""
    /// 用户选择的中文语音标识；空字符串表示系统默认普通话
    var chineseVoiceIdentifier: String = ""
    /// 单句循环：读完当前句后重复本句
    var isLoopingCurrentSentence = false
    /// 锁屏「正在播放」显示的书名
    var nowPlayingTitle = ""
    /// 根据句子序号取章节标题，用于锁屏副标题
    var chapterTitleProvider: ((Int) -> String)?

    private let synthesizer = AVSpeechSynthesizer()
    private var sentences: [Sentence] = []
    private var index = 0
    /// 当前正在朗读的语音对象；stopSpeaking 触发的 didFinish 会因身份不匹配被忽略
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureRemoteCommands()
    }

    /// 开始 / 暂停 / 继续 的统一入口
    func togglePlayback(sentences: [Sentence], startAt: Int = 0) {
        if synthesizer.isPaused {
            ensurePlaybackSession()
            synthesizer.continueSpeaking()
            isPlaying = true
            updateNowPlaying()
        } else if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
            isPlaying = false
            updateNowPlaying()
        } else {
            play(from: startAt, in: sentences)
        }
    }

    func play(from sentenceIndex: Int, in sentences: [Sentence]) {
        guard !sentences.isEmpty else { return }
        self.sentences = sentences
        index = min(max(0, sentenceIndex), sentences.count - 1)
        ensurePlaybackSession()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakCurrent()
    }

    func stop() {
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlaying = false
        currentSentenceIndex = nil
        index = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func speakCurrent() {
        ensurePlaybackSession()
        guard index < sentences.count else {
            isPlaying = false
            currentSentenceIndex = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let sentence = sentences[index]
        let utterance = AVSpeechUtterance(string: sentence.text)
        utterance.voice = resolvedVoice(for: sentence.text)
        utterance.rate = rate
        currentUtterance = utterance
        currentSentenceIndex = index
        isPlaying = true
        synthesizer.speak(utterance)
        updateNowPlaying()
    }

    // MARK: - 锁屏 / 控制中心 / 耳机

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remotePlay() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remotePause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remoteToggle() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remoteStep(forward: true) }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.remoteStep(forward: false) }
            return .success
        }
    }

    private func remotePlay() {
        guard !sentences.isEmpty else { return }
        if synthesizer.isPaused {
            ensurePlaybackSession()
            synthesizer.continueSpeaking()
            isPlaying = true
            updateNowPlaying()
        } else if !synthesizer.isSpeaking {
            play(from: currentSentenceIndex ?? index, in: sentences)
        }
    }

    private func remotePause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        isPlaying = false
        updateNowPlaying()
    }

    private func remoteToggle() {
        if isPlaying {
            remotePause()
        } else {
            remotePlay()
        }
    }

    private func remoteStep(forward: Bool) {
        guard !sentences.isEmpty else { return }
        let base = currentSentenceIndex ?? index
        let target = min(max(0, base + (forward ? 1 : -1)), sentences.count - 1)
        play(from: target, in: sentences)
    }

    private func updateNowPlaying() {
        guard let index = currentSentenceIndex, !sentences.isEmpty else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle.isEmpty ? "书声" : nowPlayingTitle,
            MPMediaItemPropertyAlbumTitle: "第 \(index + 1) / \(sentences.count) 句",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let chapter = chapterTitleProvider?(index), !chapter.isEmpty {
            info[MPMediaItemPropertyArtist] = chapter
        }
        if let icon = UIImage(named: "AppIcon") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// 双语书按句子内容切换中文/英文声音
    private func resolvedVoice(for text: String) -> AVSpeechSynthesisVoice? {
        if isMostlyChinese(text) {
            if !chineseVoiceIdentifier.isEmpty,
               let voice = AVSpeechSynthesisVoice(identifier: chineseVoiceIdentifier) {
                return voice
            }
            return AVSpeechSynthesisVoice(language: "zh-CN")
        }
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func isMostlyChinese(_ text: String) -> Bool {
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF:
                cjk += 1
            case 0x41...0x5A, 0x61...0x7A:
                latin += 1
            default:
                break
            }
        }
        return cjk > 0 && (cjk >= 2 || cjk > latin)
    }

    private func ensurePlaybackSession() {
        AudioSessionCoordinator.shared.activateReaderPlayback()
    }
}

extension SpeechPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // 只处理自然读完的当前句；被 stop/切句打断的旧语音一律忽略
            guard utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            if self.isLoopingCurrentSentence {
                self.speakCurrent()
                return
            }
            self.index += 1
            if self.index < self.sentences.count {
                self.speakCurrent()
            } else {
                self.isPlaying = false
                self.currentSentenceIndex = nil
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
        }
    }
}
