import Foundation
import Security

/// Tokens/passwords belong in the Keychain – never in UserDefaults.
enum KeychainStore {
    private static let service = "dev.miquno.kurafuto"

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Every token of this app.
    static func deleteAll() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

/// Persists the list of instances (without secrets).
@Observable
final class InstanceStore {
    private(set) var instances: [Instance] = []
    // Application Support, not Documents: the file must never show up in the Files app.
    private let url = URL.applicationSupportDirectory.appending(path: "instances.json")

    init(preview: [Instance]? = nil) {
        if let preview { instances = preview; return }
        Self.forgetEarlierInstall(listExists: FileManager.default.fileExists(atPath: url.path()), defaults: .standard,
                                  deleteTokens: KeychainStore.deleteAll)
        if let d = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Instance].self, from: d) {
            instances = list
        }
    }

    /// iOS keeps Keychain items when the app is deleted, but removes its files and settings. On the first launch of
    /// a new install, tokens from an earlier one are deleted. A panel list on disk means this install already ran
    /// (its settings may just be unreadable before the first unlock), so nothing is deleted then.
    static func forgetEarlierInstall(listExists: Bool, defaults: UserDefaults, deleteTokens: () -> Void) {
        guard !defaults.bool(forKey: installedKey) else { return }
        if !listExists { deleteTokens() }
        defaults.set(true, forKey: installedKey)
    }

    static let installedKey = "installed"

    func upsert(_ instance: Instance, token: String) {
        if let i = instances.firstIndex(where: { $0.id == instance.id }) { instances[i] = instance }
        else { instances.append(instance) }
        KeychainStore.set(token, for: instance.id.uuidString)
        save()
    }

    func remove(_ instance: Instance) {
        instances.removeAll { $0.id == instance.id }
        KeychainStore.delete(instance.id.uuidString)
        save()
    }

    func token(for instance: Instance) -> String? { KeychainStore.get(instance.id.uuidString) }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(instances).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
