import SwiftUI

struct ScenarioPickerView: View {
    // 这些值只用于在设置变化时刷新页面
    @AppStorage("ai.provider") private var providerRaw = AIProvider.deepseek.rawValue
    @AppStorage("ai.apiKey.deepseek") private var deepseekKey = ""
    @AppStorage("ai.apiKey.glm") private var glmKey = ""

    @State private var showAISettings = false

    private var availability: TutorAvailability { TutorAvailability.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 情景对话", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showAISettings = true
                } label: {
                    Label("AI 设置", systemImage: "gearshape")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }

            if let message = availability.message {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI 对话暂不可用")
                        .font(.footnote.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        showAISettings = true
                    } label: {
                        Label("配置在线模型", systemImage: "key.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            } else if availability.engine == .online {
                let config = RemoteTutorService.Config.current
                Text("使用在线模型：\(config.provider.title) · \(config.model)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(SpeakingScenario.all) { scenario in
                if availability.isAvailable {
                    NavigationLink(value: scenario) {
                        row(scenario)
                    }
                    .buttonStyle(.plain)
                } else {
                    row(scenario)
                        .opacity(0.45)
                }
            }
        }
        .sheet(isPresented: $showAISettings) {
            AISettingsSheet()
        }
        .onAppear {
            // 仅用于开发调试：`SIMCTL_CHILD_AUTO_OPEN_AI_SETTINGS=1` 启动时打开 AI 设置
            if ProcessInfo.processInfo.environment["AUTO_OPEN_AI_SETTINGS"] == "1" {
                showAISettings = true
            }
        }
    }

    private func row(_ scenario: SpeakingScenario) -> some View {
        HStack(spacing: 14) {
            Image(systemName: scenario.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [.orange, .orange.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(scenario.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(scenario.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .contentShape(Rectangle())
    }
}
