import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 对话引擎：优先在线模型（用户配置），否则端侧 Apple Intelligence
enum TutorEngine {
    case online
    case onDevice
}

/// AI 对话可用性
enum TutorAvailability {
    case available(TutorEngine)
    case unavailable(String)

    static var current: TutorAvailability {
        // 仅用于开发调试：`SIMCTL_CHILD_AUTO_FORCE_ONLINE=1` 强制在线引擎
        if ProcessInfo.processInfo.environment["AUTO_FORCE_ONLINE"] == "1" {
            return .available(.online)
        }
        if RemoteTutorService.Config.current.isConfigured {
            return .available(.online)
        }
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available(.onDevice)
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("当前地区暂不支持苹果端侧 AI，可配置在线模型（右上角「AI 设置」）")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("请先在「设置 → Apple Intelligence 与 Siri」中开启，或配置在线模型")
                case .modelNotReady:
                    return .unavailable("端侧模型正在准备，请稍后再试，或配置在线模型")
                @unknown default:
                    return .unavailable("端侧 AI 暂时不可用，可配置在线模型")
                }
            }
        }
        return .unavailable("可配置在线模型开始 AI 对话（右上角「AI 设置」）")
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var engine: TutorEngine? {
        if case .available(let engine) = self { return engine }
        return nil
    }

    var message: String? {
        if case .unavailable(let message) = self { return message }
        return nil
    }
}

enum TutorError: LocalizedError {
    case notReady
    case emptyReply
    case notConfigured
    case network
    case server(code: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "AI 还没准备好"
        case .emptyReply:
            return "AI 没有给出回复，请再说一次"
        case .notConfigured:
            return "请先在「AI 设置」里填写在线模型的 API Key"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .server(let code, let detail):
            if code == 401 {
                return "API Key 无效或已过期，请检查「AI 设置」"
            }
            if code == 429 {
                return "请求太频繁或额度不足，请稍后再试"
            }
            return "AI 服务出错（\(code)）\(detail.isEmpty ? "" : "：\(detail)")"
        }
    }
}

/// 对话引擎统一接口（在线 / 端侧）
protocol SpeakingTutoring: AnyObject {
    func reset(for scenario: SpeakingScenario)
    func reply(to userText: String) async throws -> String
    func correction(for userText: String) async throws -> String
}

/// 端侧情景对话：每个场景一个 LanguageModelSession，负责回复和纠错。
@available(iOS 26.0, *)
@MainActor
final class SpeakingTutorService: SpeakingTutoring {
    private var session: LanguageModelSession?

    func reset(for scenario: SpeakingScenario) {
        session = LanguageModelSession(instructions: scenario.tutorInstructions)
    }

    func reply(to userText: String) async throws -> String {
        guard let session else { throw TutorError.notReady }
        let response = try await session.respond(to: userText)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TutorError.emptyReply }
        return text
    }

    func correction(for userText: String) async throws -> String {
        guard let session else { throw TutorError.notReady }
        let prompt = """
        The user just said: "\(userText)". As their English tutor, point out the most important grammar or word-choice issue in Chinese in at most two short lines, then give one more natural English version. Be encouraging and concise.
        """
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TutorError.emptyReply }
        return text
    }
}
