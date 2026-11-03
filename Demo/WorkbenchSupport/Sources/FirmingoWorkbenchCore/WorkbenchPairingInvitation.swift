import Foundation

/// One-time, short-lived bootstrap capability. Never included in reports, UI status or committed evidence.
public struct WorkbenchPairingInvitation: Codable, Sendable {
    /// Pairing protocol independent of scenario/report schemas.
    public let schema: Int
    /// Explicit controller-assigned device session; never inferred from an IP address.
    public let sessionID: UUID
    /// Explicit private/loopback HTTPS controller, with no redirect or discovery fallback.
    public let endpoint: URL
    /// Exact SHA-256 of the controller's leaf DER certificate.
    public let certificateSHA256: String
    /// One-use 256-bit bootstrap secret, rotated by the successful pairing handshake.
    public let token: String
    /// Human-readable session label, not a physical-device identity or trust assertion.
    public let label: String
    /// Decodes a bounded closed invitation supplied manually or through an explicit development launch.
    public static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= 2048,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == Set(["schema", "sessionID", "endpoint", "certificateSHA256", "token", "label"]) else {
            throw WorkbenchFailure("Invalid pairing invitation.")
        }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.schema == 1, WorkbenchRequest.isDigest(value.certificateSHA256), WorkbenchRequest.isDigest(value.token),
              !value.label.isEmpty, value.label.utf8.count <= 64,
              let parts = URLComponents(url: value.endpoint, resolvingAgainstBaseURL: false), parts.scheme == "https",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let port = parts.port, (1024...65535).contains(port),
              let host = parts.host, privateHost(host) else { throw WorkbenchFailure("Pairing requires a pinned private HTTPS endpoint.") }
        return value
    }
    /// Restricts this developer controller to numeric private IPv4 or loopback; no public-host token forwarding.
    private static func privateHost(_ host: String) -> Bool {
        if host == "localhost" { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let numbers = parts.compactMap { UInt8($0) }
        guard numbers.count == 4, zip(parts, numbers).allSatisfy({ String($0.1) == $0.0 }) else { return false }
        return numbers[0] == 10 || numbers[0] == 127 || (numbers[0] == 192 && numbers[1] == 168) ||
            (numbers[0] == 172 && (16...31).contains(numbers[1]))
    }
}
