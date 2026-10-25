import Foundation
import CoreFoundation

// Application identity and quota caches are deliberately separate for each service.
enum UsageProvider: String, CaseIterable {
    case codex, claude

    init?(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.openai.codex": self = .codex
        case "com.anthropic.claudefordesktop": self = .claude
        default: return nil
        }
    }

    var title: String { self == .codex ? "Codex" : "Claude" }
    var cacheKey: String { self == .codex ? "lastUsageSnapshot" : "lastClaudeUsageSnapshot" }
}

struct UsageWindow: Codable {
    let usedPercent: Double
    let resetsAt: TimeInterval?
}

struct UsageSnapshot: Codable {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    let fetchedAt: TimeInterval

    func canUseCache(at now: TimeInterval) -> Bool {
        fetchedAt.isFinite && fetchedAt <= now + 300 && now - fetchedAt < 86_400
    }
}

enum ClaudeUsageError: LocalizedError {
    case notConnected, chooseOrganization, invalidResponse, requestFailed, timeout, unsupportedNavigation
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "请从菜单选择“连接 Claude”，在 Claude 网站登录后读取额度"
        case .chooseOrganization: return "请在 Claude 连接窗口中选择工作区"
        case .invalidResponse: return "Claude 用量格式无法识别；网站接口可能已变化"
        case .requestFailed: return "无法读取 Claude 用量，请在连接窗口重试"
        case .timeout: return "读取 Claude 用量超时，请在连接窗口检查登录和网络"
        case .unsupportedNavigation: return "此登录跳转不受支持，请使用 Claude 页面内提供的其他登录方式"
        case .http(429): return "Claude 用量接口限流，已暂停请求，稍后自动重试"
        case .http(let status): return "Claude 用量读取失败（HTTP \(status)）"
        }
    }
}

enum ClaudeNavigationPolicy {
    static func allowsEmbeddedNavigation(to url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil else { return false }
        return ["claude.ai", "accounts.google.com", "appleid.apple.com",
                "auth.anthropic.com", "auth.claude.com"].contains(url.host?.lowercased() ?? "")
    }
}

enum ClaudeUsageParser {
    static func snapshot(from object: Any, now: TimeInterval = Date().timeIntervalSince1970) throws -> UsageSnapshot {
        guard let usage = object as? [String: Any] else { throw ClaudeUsageError.invalidResponse }
        func window(_ key: String) throws -> UsageWindow? {
            guard let value = usage[key], !(value is NSNull) else { return nil }
            guard let fields = value as? [String: Any],
                  let percentage = fields["utilization"] as? NSNumber,
                  CFGetTypeID(percentage) != CFBooleanGetTypeID() else {
                throw ClaudeUsageError.invalidResponse
            }
            let used = percentage.doubleValue
            guard used.isFinite, (0...100).contains(used) else { throw ClaudeUsageError.invalidResponse }
            let reset: TimeInterval?
            if let raw = fields["resets_at"], !(raw is NSNull) {
                if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                   number.doubleValue.isFinite, number.doubleValue > 0 {
                    reset = number.doubleValue
                } else if let text = raw as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let fractional = formatter.date(from: text)
                    formatter.formatOptions = [.withInternetDateTime]
                    guard let date = fractional ?? formatter.date(from: text) else { throw ClaudeUsageError.invalidResponse }
                    reset = date.timeIntervalSince1970
                } else { throw ClaudeUsageError.invalidResponse }
            } else { reset = nil }
            return UsageWindow(usedPercent: used, resetsAt: reset)
        }
        let fiveHour = try window("five_hour"), weekly = try window("seven_day")
        guard fiveHour != nil || weekly != nil else { throw ClaudeUsageError.invalidResponse }
        return UsageSnapshot(fiveHour: fiveHour, weekly: weekly, fetchedAt: now)
    }
}
