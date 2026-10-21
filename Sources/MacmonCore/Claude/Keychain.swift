import Foundation
import Security

public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

public enum ClaudeKeychain {
    public static func loadCredentials() -> ClaudeCredentials? {
        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !token.isEmpty {
            return ClaudeCredentials(accessToken: token, expiresAt: nil,
                                     subscriptionType: nil)
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }

        var expiresAt: Date?
        if let milliseconds = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: milliseconds / 1000)
        } else if let milliseconds = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }

        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }
}
