import Foundation
import Security
import CryptoKit

/// Immutable certificate pin shared with Foundation's delegate queue. No mutable state crosses isolation.
final class WorkbenchPinnedTLS: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    /// Exact DER digest from the explicitly supplied invitation, never a hostname-only trust exception.
    private let digest: String
    /// Captures the explicit pin without loading credentials or changing system trust.
    init(digest: String) { self.digest = digest }
    /// Accepts only the pinned TLS leaf; unrelated/system credential challenges fail closed.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let actual = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        guard actual == digest else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    /// A redirect may not forward a pairing/session token to another endpoint.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
