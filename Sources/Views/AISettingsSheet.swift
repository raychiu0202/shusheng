import SwiftUI

struct AISettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("ai.provider") private var providerRaw = AIProvider.deepseek.rawValue

    @AppStorage("ai.apiKey.deepseek") private var deepseekKey = ""
    @AppStorage("ai.baseURL.deepseek") private var deepseekBase = "https://api.deepseek.com/v1"
    @AppStorage("ai.model.deepseek") private var deepseekModel = "deepseek-chat"

    @AppStorage("ai.apiKey.glm") private var glmKey = ""
    @AppStorage("ai.baseURL.glm") private var glmBase = "https://open.bigmodel.cn/api/paas/v4"
    @AppStorage("ai.model.glm") private var glmModel = "glm-4-flash"

    @State private var showKey = false

    private var provider: AIProvider {
        AIProvider(rawValue: providerRaw) ?? .deepseek
    }

    private var key: Binding<String> {
        provider == .deepseek ? $deepseekKey : $glmKey
    }

    private var baseURL: Binding<String> {
        provider == .deepseek ? $deepseekBase : $glmBase
    }

    private var model: Binding<String> {
        provider == .deepseek ? $deepseekModel : $glmModel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("服务商", selection: $providerRaw) {
                        ForEach(AIProvider.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("两个服务商各自保存 API Key，切换互不影响。")
                }

                Section {
                    if showKey {
                        TextField("sk-...", text: key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("sk-...", text: key)
                    }
                    Toggle("显示 API Key", isOn: $showKey)

                    TextField("接口地址", text: baseURL, prompt: Text(provider.defaultBaseURL))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("模型名称", text: model, prompt: Text(provider.defaultModel))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("\(provider.title) · \(provider.subtitle)")
                } footer: {
                    Text(provider == .deepseek
                         ? "在 platform.deepseek.com 创建 API Key。"
                         : "在 open.bigmodel.cn 创建 API Key，glm-4-flash 有免费额度。")
                }

                Section {
                    Button("恢复 \(provider.title) 默认地址和模型") {
                        baseURL.wrappedValue = provider.defaultBaseURL
                        model.wrappedValue = provider.defaultModel
                    }
                }

                Section {
                    Text("""
                    · 语音识别仍在本机运行；对话文字会发送给所选服务商
                    · API Key 只保存在这台手机上
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
