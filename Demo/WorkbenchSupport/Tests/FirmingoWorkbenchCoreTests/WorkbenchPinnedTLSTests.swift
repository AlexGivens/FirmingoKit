import Foundation
import Testing
@testable import FirmingoWorkbenchCore

/// Explicit opt-in Foundation TLS qualification; ordinary tests contact no network endpoint.
@Test(.enabled(if: ProcessInfo.processInfo.environment["WORKBENCH_TLS_ENDPOINT"] != nil))
@MainActor func actualPinnedTLSAcceptsOnlyTheSelectedLeaf() async throws {
    let environment = ProcessInfo.processInfo.environment
    let endpoint = try #require(environment["WORKBENCH_TLS_ENDPOINT"])
    let pin = try #require(environment["WORKBENCH_TLS_PIN"])
    let object: [String: Any] = ["schema":1,"sessionID":UUID().uuidString,"endpoint":endpoint,
        "certificateSHA256":pin,"token":String(repeating:"a",count:64),"label":"Explicit TLS probe"]
    let invitation = try WorkbenchPairingInvitation.decode(JSONSerialization.data(withJSONObject: object))
    for valid in [true, false] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5; configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration,
            delegate: WorkbenchPinnedTLS(digest: valid ? invitation.certificateSHA256 : String(repeating:"0",count:64)),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        if valid {
            let (_, response) = try await session.data(from: invitation.endpoint)
            #expect((response as? HTTPURLResponse)?.statusCode == 501)
        } else {
            await #expect(throws: URLError.self) { try await session.data(from: invitation.endpoint) }
        }
    }
}
