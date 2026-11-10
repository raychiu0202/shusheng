import Foundation

/// 支持切换的在线模型服务商（均为 OpenAI 兼容接口）
enum AIProvider: String, CaseIterable, Identifiable {
    case deepseek
    case glm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .glm: return "GLM"
        }
    }

    var subtitle: String {
        switch self {
        case .deepseek: return "深度求索"
        case .glm: return "智谱"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .glm: return "glm-4-flash"
        }
    }
}

/// 在线情景对话：调用 OpenAI 兼容接口（DeepSeek / GLM 等）。
/// 每个服务商各自保存 API Key，只存在本机 UserDefaults。
final class RemoteTutorService: SpeakingTutoring {
    struct Config {
        var provider: AIProvider
        var baseURL: String
        var apiKey: String
        var model: String

        var isConfigured: Bool {
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        static var current: Config {
            migrateLegacyIfNeeded()
            let defaults = UserDefaults.standard
            let provider = AIProvider(rawValue: defaults.string(forKey: "ai.provider") ?? "") ?? .deepseek
            let suffix = provider.rawValue
            let base = (defaults.string(forKey: "ai.baseURL.\(suffix)") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (defaults.string(forKey: "ai.model.\(suffix)") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Config(
                provider: provider,
                baseURL: base.isEmpty ? provider.defaultBaseURL : base,
                apiKey: defaults.string(forKey: "ai.apiKey.\(suffix)") ?? "",
                model: model.isEmpty ? provider.defaultModel : model
            )
        }

        /// 旧版本只有一套 ai.apiKey/ai.baseURL/ai.model，迁移为 DeepSeek 的配置
        private static func migrateLegacyIfNeeded() {
            let defaults = UserDefaults.standard
            let legacyKey = (defaults.string(forKey: "ai.apiKey") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !legacyKey.isEmpty else { return }
            if (defaults.string(forKey: "ai.apiKey.deepseek") ?? "").isEmpty {
                defaults.set(legacyKey, forKey: "ai.apiKey.deepseek")
            }
            let legacyBase = defaults.string(forKey: "ai.baseURL") ?? ""
            if !legacyBase.isEmpty,
               (defaults.string(forKey: "ai.baseURL.deepseek") ?? "").isEmpty {
                defaults.set(legacyBase, forKey: "ai.baseURL.deepseek")
            }
            let legacyModel = defaults.string(forKey: "ai.model") ?? ""
            if !legacyModel.isEmpty,
               (defaults.string(forKey: "ai.model.deepseek") ?? "").isEmpty {
                defaults.set(legacyModel, forKey: "ai.model.deepseek")
            }
        }
    }

    private let config: Config
    private var systemPrompt = ""
    private var history: [[String: String]] = []

    init(config: Config = .current) {
        self.config = config
    }

    func reset(for scenario: SpeakingScenario) {
        systemPrompt = scenario.tutorInstructions
        history = []
    }

    func reply(to userText: String) async throws -> String {
        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        messages.append(contentsOf: history.suffix(20))
        messages.append(["role": "user", "content": userText])

        let reply = try await complete(messages: messages)
        history.append(["role": "user", "content": userText])
        history.append(["role": "assistant", "content": reply])
        if history.count > 40 {
            history.removeFirst(history.count - 40)
        }
        return reply
    }

    func correction(for userText: String) async throws -> String {
        let prompt = """
        The user just said: "\(userText)". As their English tutor, point out the most important grammar or word-choice issue in Chinese in at most two short lines, then give one more natural English version. Be encouraging and concise.
        """
        return try await complete(messages: [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt]
        ])
    }

    // MARK: - 请求

    private func complete(messages: [[String: String]]) async throws -> String {
        guard config.isConfigured else { throw TutorError.notConfigured }

        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        let endpoint = base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
        guard let url = URL(string: endpoint) else { throw TutorError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": 0.8,
            "max_tokens": 300,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TutorError.network
        }

        guard let http = response as? HTTPURLResponse else { throw TutorError.network }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw TutorError.server(code: http.statusCode, detail: String(raw.prefix(160)))
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw TutorError.emptyReply
        }

        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TutorError.emptyReply }
        return text
    }
}
