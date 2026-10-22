import Foundation

private let credentialQueueLabel: String = {
    let identifier = Bundle.main.bundleIdentifier ?? "dev.arkab.macmon"
    return "\(identifier).credential"
}()

public final class ClaudeCredentialStore: @unchecked Sendable {
    public static let shared = ClaudeCredentialStore()

    private var value: ClaudeCredentials?
    private var loadStarted = false
    private let queue = DispatchQueue(label: credentialQueueLabel,
                                      qos: .utility)

    private init() {}

    public func unsafeGet(forceReload: Bool = false,
                          completion: @escaping (ClaudeCredentials?) -> Void) {
        queue.async {
            if !forceReload, let value = self.value, !value.isExpired {
                completion(value)
                return
            }
            let loaded = ClaudeKeychain.loadCredentials()
            if let loaded {
                self.value = loaded
            }
            let result = self.value
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
