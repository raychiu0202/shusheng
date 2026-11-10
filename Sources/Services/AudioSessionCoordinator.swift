import AVFoundation

/// 统一管理音频会话：阅读 TTS 用 .playback，口语练习（录音 + 对话 TTS）用 .playAndRecord。
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private let session = AVAudioSession.sharedInstance()

    private init() {}

    /// 阅读朗读：纯播放
    func activateReaderPlayback() {
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    /// 口语练习：录音 + 外放（对话回复）
    func activateSpeaking() {
        try? session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try? session.setActive(true)
    }

    /// 离开口语练习，恢复阅读播放
    func restoreReaderPlayback() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        activateReaderPlayback()
    }
}
