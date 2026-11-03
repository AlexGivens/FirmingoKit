import Foundation
import Observation

/// Outbound, explicitly paired app controller. No listener, discovery, background grant or Keychain persistence is added.
@Observable @MainActor public final class WorkbenchPairedClient {
    /// Human-visible transport state, never a scenario pass/fail assertion or credential.
    public private(set) var status = "Not paired"
    /// Whether a live in-memory paired session exists.
    public private(set) var isPaired = false
    /// Explicit controller label; not installed-app or device attestation.
    public private(set) var label = ""
    /// Session UUID safe for display and correlation; contains no authentication secret.
    public private(set) var sessionID: UUID?
    /// Shared production command dispatcher.
    private let host: WorkbenchControlHost
    /// Per-request network session with certificate pinning and no persistent cookie/cache/credential store.
    private var network: URLSession?
    /// Exactly one owned poll/handshake task.
    private var task: Task<Void, Never>?
    /// One-time pending invitation, discarded after successful exchange or disconnect.
    private var invitation: WorkbenchPairingInvitation?
    /// Rotated session credential, held only in app memory and encrypted requests.
    private var token: String?
    /// Pinned explicit origin retained only for this pairing lifetime.
    private var endpoint: URL?
    /// Last executed sequence; retained across background pause and response loss.
    private var acknowledged = 0
    /// Cached reply retransmitted as an acknowledgement, never by executing its command again.
    private var lastReply: WorkbenchControlReply?
    /// Real aggregate phase supplied by the app; never part of a controller command.
    private var phase = "unknown"
    /// Changes on explicit disconnect/replacement so an old task cannot mutate a newer pairing.
    private var generation = 0
    /// Consecutive transport failures; finite retries only retransmit the same acknowledgement.
    private var failures = 0
    /// Creates no network operation until an explicit invitation is connected.
    public init(host: WorkbenchControlHost) { self.host = host }
    /// Begins one explicit ephemeral pairing. Replacing a pairing revokes the prior owned run locally.
    public func connect(_ value: WorkbenchPairingInvitation) {
        disconnect()
        invitation = value; endpoint = value.endpoint; sessionID = value.sessionID; label = value.label
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 45; configuration.timeoutIntervalForResource = 60
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        network = URLSession(configuration: configuration, delegate: WorkbenchPinnedTLS(digest: value.certificateSHA256), delegateQueue: nil)
        status = "Waiting for foreground to pair with " + value.label
        resume()
    }
    /// User/controller revocation forgets credentials and cancels only the controller-owned scenario, retaining its journal.
    public func disconnect() {
        generation += 1; task?.cancel(); task = nil
        network?.invalidateAndCancel(); network = nil
        invitation = nil; token = nil; endpoint = nil; sessionID = nil
        isPaired = false; label = ""; acknowledged = 0; lastReply = nil; failures = 0
        status = "Not paired"; host.disconnect()
    }
    /// Pauses transport on actual backgrounding; lifecycle engine policy remains separate and can settle its own cancellation.
    public func recordScene(_ value: String) {
        phase = value
        if value == "background" {
            task?.cancel()
            if sessionID != nil { status = "Paired transport paused in background" }
        } else if value == "active" { resume() }
    }
    /// Starts only when actual foreground permits command admission; does not create scene events.
    private func resume() {
        guard phase == "active", endpoint != nil, task == nil else { return }
        let current = generation
        task = Task {
            defer {
                if generation == current { task = nil; if phase == "active", endpoint != nil { resume() } }
            }
            do {
                if let invitation {
                    let body = PairRequest(instanceID: host.instanceID, appIdentifier: Bundle.main.bundleIdentifier ?? "unbundled",
                        appVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unbundled",
                        processID: ProcessInfo.processInfo.processIdentifier)
                    let data = try await post("pair", credential: invitation.token, body: body)
                    guard current == generation else { return }
                    let paired = try JSONDecoder().decode(PairResponse.self, from: data)
                    guard paired.schema == 1, paired.sessionID == invitation.sessionID, WorkbenchRequest.isDigest(paired.token) else {
                        throw WorkbenchFailure("Invalid pairing response.")
                    }
                    token = paired.token; self.invitation = nil; isPaired = true
                }
                while !Task.isCancelled {
                    guard phase == "active" else { try await Task.sleep(for: .milliseconds(100)); continue }
                    guard let token, let sessionID else { throw WorkbenchFailure("Pairing session ended.") }
                    do {
                        let data = try await post("exchange", credential: token,
                            body: ExchangeRequest(sessionID: sessionID, instanceID: host.instanceID, ack: acknowledged, reply: lastReply))
                        guard current == generation else { return }
                        failures = 0
                        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              Set(object.keys) == Set(["schema", "sessionID", "sequence", "command"]),
                              (object["schema"] as? Int) == 1, object["sessionID"] as? String == sessionID.uuidString,
                              let sequence = object["sequence"] as? Int else { throw WorkbenchFailure("Invalid controller envelope.") }
                        if object["command"] is NSNull {
                            guard sequence == acknowledged else { throw WorkbenchFailure("Unexpected idle sequence.") }
                            status = "Paired with " + label; continue
                        }
                        guard let raw = object["command"] else { throw WorkbenchFailure("Missing command.") }
                        let command = try WorkbenchControlCommand.decode(JSONSerialization.data(withJSONObject: raw))
                        if sequence == acknowledged {
                            guard lastReply?.command.commandID == command.commandID else { throw WorkbenchFailure("Sequence replay differs from its cached reply.") }
                            continue
                        }
                        guard sequence == acknowledged + 1 else { throw WorkbenchFailure("Controller sequence gap; no command was replayed.") }
                        while phase != "active" { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(100)) }
                        status = "Controller action: " + command.action.rawValue
                        // An admitted SDK operation outlives transport pause; host owns its task and durable run UUID.
                        let reply = await host.handle(command)
                        guard current == generation else { return }
                        lastReply = reply; acknowledged = sequence
                    } catch is CancellationError { throw CancellationError() }
                    catch let error as URLError {
                        guard current == generation else { return }
                        if Task.isCancelled { throw CancellationError() }
                        failures += 1
                        guard failures <= 3 else { throw error }
                        status = "Transport interrupted; retrying only the saved acknowledgement"
                        try await Task.sleep(for: .seconds(1))
                    }
                }
            } catch is CancellationError { return }
            catch {
                guard current == generation else { return }
                let message = String(error.localizedDescription.prefix(256))
                network?.invalidateAndCancel(); network = nil; invitation = nil; token = nil; endpoint = nil
                isPaired = false; sessionID = nil; host.disconnect()
                status = "Pairing stopped: " + message
            }
        }
    }
    /// One pinned POST with bounded streamed response; no redirect or persistent transport state.
    private func post<Body: Encodable>(_ path: String, credential: String, body: Body) async throws -> Data {
        guard let network, let endpoint else { throw WorkbenchFailure("No explicit pairing endpoint.") }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/" + path))
        request.httpMethod = "POST"; request.setValue("Bearer " + credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        guard (request.httpBody?.count ?? 0) <= 98304 else { throw WorkbenchFailure("Controller request exceeds its bound.") }
        let (stream, response) = try await network.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= 98304 else { throw WorkbenchFailure("Controller rejected the paired request.") }
        var data = Data()
        for try await byte in stream {
            guard data.count < 98304 else { throw WorkbenchFailure("Controller response exceeds its bound.") }
            data.append(byte)
        }
        return data
    }
    /// Public app identity sent only within the pinned TLS handshake.
    private struct PairRequest: Encodable {
        /// Protocol schema.
        let schema = 1
        /// Per-process app instance.
        let instanceID: UUID
        /// Actual bundle identity.
        let appIdentifier: String
        /// Actual build number.
        let appVersion: String
        /// Actual app PID, independently checked by the Mac launch tool.
        let processID: Int32
    }
    /// Session token replaces the consumed invitation credential; never persists or appears in status.
    private struct PairResponse: Decodable {
        /// Protocol schema.
        let schema: Int
        /// Invitation-selected session.
        let sessionID: UUID
        /// Rotated secret.
        let token: String
    }
    /// Acknowledgement carries the saved reply, not a request to repeat execution.
    private struct ExchangeRequest: Encodable {
        /// Protocol schema.
        let schema = 1
        /// Exact selected session.
        let sessionID: UUID
        /// Per-process app instance.
        let instanceID: UUID
        /// Last executed sequence.
        let ack: Int
        /// Last completed dispatch result.
        let reply: WorkbenchControlReply?
        /// Emit an explicit null on the initial exchange rather than omitting the acknowledgement slot.
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(schema, forKey: .schema); try values.encode(sessionID, forKey: .sessionID)
            try values.encode(instanceID, forKey: .instanceID); try values.encode(ack, forKey: .ack)
            if let reply { try values.encode(reply, forKey: .reply) } else { try values.encodeNil(forKey: .reply) }
        }
        /// Closed exchange envelope keys.
        private enum CodingKeys: String, CodingKey { case schema, sessionID, instanceID, ack, reply }
    }
}
