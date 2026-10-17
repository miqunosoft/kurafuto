import Foundation

/// A Crafty installation the user added (several are possible: homelab, a friend's server, ...).
/// The token is NOT stored here but in the Keychain (see KeychainStore).
struct Instance: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var baseURL: URL                       // e.g. https://192.168.1.20:8443
    var username: String
    var authMethod: AuthMethod
    /// SHA-256 of the certificate for self-signed installations (trust on first use).
    var pinnedCertificateSHA256: String?
    var accentColorHex: String = "#3FB950"

    enum AuthMethod: String, Codable { case password, apiToken }
}

extension Instance {
    /// The address as typed, if Kurafuto may connect to it: `https` with a host and nothing else around it.
    /// Plain `http` is refused, so passwords and tokens never travel unencrypted (ADR 0004).
    static func panelURL(from text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty,
              url.user() == nil, url.password() == nil, url.query() == nil, url.fragment() == nil else { return nil }
        return url
    }
}
