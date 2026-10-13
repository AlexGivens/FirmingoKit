import Foundation
import WebKit

/// Serves the selected immutable verified capabilities; arbitrary files, paths and network requests are unavailable.
@MainActor final class ManagedCompilerOrigin: NSObject, WKURLSchemeHandler {
    /// Exact local resources for this build, held only until its page is disposed.
    private let resources: [String: Data]
    /// Captures already verified bytes without filesystem access on the WebKit actor.
    convenience init(toolchain: VerifiedManagedToolchain) {
        self.init(page: toolchain.page, service: toolchain.service)
    }
    /// Service-free operations expose only the verified page; no compiler module can be fetched.
    init(page: Data, service: Data? = nil) {
        var selected = ["/host.html": page]
        if let service { selected["/compiler.wasm"] = service }
        resources = selected
    }
    /// Validates exact origin/path/method and responds atomically from immutable in-memory bytes.
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let request = urlSchemeTask.request
        guard let url = request.url, url.scheme == "firmingo-compiler", url.host == "assets",
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil,
              request.httpMethod == "GET", let data = resources[url.path],
              url.absoluteString == "firmingo-compiler://assets" + url.path else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile)); return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": url.path == "/host.html" ? "text/html; charset=utf-8" : "application/wasm",
                           "Content-Length": String(data.count), "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*"]) else {
            urlSchemeTask.didFailWithError(URLError(.badServerResponse)); return
        }
        urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    /// Responses have no pending filesystem or networking tasks to cancel.
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
