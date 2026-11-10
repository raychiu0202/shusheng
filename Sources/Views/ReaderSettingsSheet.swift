import SwiftUI
import AVFoundation

/// 阅读设置：字号 / 背景 / 朗读速度 / 朗读声音 / 从头开始
struct ReaderSettingsSheet: View {
    @Binding var fontSize: Double
    @Binding var themeRaw: String
    @Binding var rate: Float
    @Binding var voiceID: String
    @Binding var chineseVoiceID: String
    let onRestart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmRestart = false

    private let fontChoices: [(label: String, value: Double)] = [
        ("小", 17), ("中", 19), ("大", 22), ("特大", 25)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("字号") {
                    HStack(spacing: 8) {
                        ForEach(fontChoices, id: \.value) { choice in
                            chip(choice.label, selected: abs(fontSize - choice.value) < 0.5) {
                                fontSize = choice.value
                            }
                        }
                    }
                }

                Section("背景") {
                    HStack(spacing: 12) {
                        ForEach(ReaderTheme.allCases) { theme in
                            themeSwatch(theme)
                        }
                    }
                }

                Section("朗读速度") {
                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: "tortoise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: rateBinding, in: 0.3...0.8, step: 0.05)
                            Image(systemName: "hare")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(speedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("英文声音", selection: $voiceID) {
                        Text("系统默认（美音）").tag("")
                        ForEach(englishVoices) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("中文声音", selection: $chineseVoiceID) {
                        Text("系统默认（普通话）").tag("")
                        ForEach(chineseVoices) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("朗读声音")
                } footer: {
                    Text("双语书会自动按句子切换中/英文声音。增强/高级音质可在 系统设置 → 辅助功能 → 朗读内容 中下载。声音切换后从下一句开始生效。")
                }

                Section {
                    Button("从本书开头重新开始", role: .destructive) {
                        confirmRestart = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "从本书开头重新开始朗读？",
                isPresented: $confirmRestart,
                titleVisibility: .visible
            ) {
                Button("重新开始", role: .destructive) {
                    dismiss()
                    onRestart()
                }
            }
        }
    }

    // MARK: - 速度

    private var rateBinding: Binding<Double> {
        Binding(
            get: { Double(rate) },
            set: { rate = Float($0) }
        )
    }

    private var speedDescription: String {
        let value = Double(rate)
        let word: String
        switch value {
        case ..<0.45: word = "慢"
        case ..<0.52: word = "中慢"
        case ..<0.62: word = "正常"
        default: word = "快"
        }
        return String(format: "%.2f× · %@", value, word)
    }

    // MARK: - 声音

    private struct VoiceOption: Identifiable {
        let id: String
        let name: String
        let language: String
        let quality: AVSpeechSynthesisVoiceQuality

        var displayName: String {
            var parts = [name, regionLabel(language)]
            if quality != .default {
                parts.append(qualityLabel(quality))
            }
            return parts.joined(separator: " · ")
        }
    }

    private var englishVoices: [VoiceOption] {
        voiceOptions { $0.language.hasPrefix("en") }
    }

    private var chineseVoices: [VoiceOption] {
        voiceOptions { $0.language.hasPrefix("zh") || $0.language.hasPrefix("yue") }
    }

    private func voiceOptions(
        matching filter: (AVSpeechSynthesisVoice) -> Bool
    ) -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter(filter)
            .map {
                VoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    quality: $0.quality
                )
            }
            .sorted {
                if $0.language != $1.language { return $0.language < $1.language }
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private static func regionLabel(_ language: String) -> String {
        switch language {
        case "en-US": return "美音"
        case "en-GB": return "英音"
        case "en-AU": return "澳音"
        case "en-IE": return "爱尔兰音"
        case "en-ZA": return "南非音"
        case "en-IN": return "印度音"
        case "zh-CN": return "普通话"
        case "zh-TW": return "台湾国语"
        case "zh-HK": return "粤语"
        case "yue-CN", "yue-HK": return "粤语"
        default: return language
        }
    }

    private static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "高级"
        case .enhanced: return "增强"
        default: return "标准"
        }
    }

    // MARK: - 通用控件

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    selected ? Color.orange : Color(.secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }

    private func themeSwatch(_ theme: ReaderTheme) -> some View {
        let selected = themeRaw == theme.rawValue
        return Button {
            themeRaw = theme.rawValue
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.background)
                        .frame(width: 44, height: 44)
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                        .frame(width: 44, height: 44)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(theme == .night ? Color.white : Color.black)
                    }
                }
                Text(theme.title)
                    .font(.caption)
                    .foregroundStyle(selected ? Color.orange : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
