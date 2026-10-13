import Foundation
import AppKit
import WebKit

/// Hosts an explicitly selected compiler-maintenance page; never bypasses the SDK's consumer asset pins.
@main @MainActor struct VerifyBuiltServiceWebKit {
    /// Rejects external or ambiguous addresses before starting WebKit or AppKit.
    static func loopbackURL(_ text: String) throws -> URL {
        guard let url = URL(string: text), let port = url.port, (1...65535).contains(port),
              url.scheme == "http", url.host == "127.0.0.1", url.path == "/",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              text == "http://127.0.0.1:\(port)/" else {
            throw Failure.invalidInput("Select an exact numeric IPv4 loopback origin with an explicit port")
        }
        return url
    }

    /// Tests the real address boundary without starting a browser, fetching assets, or touching a device.
    static func checkInputs() throws {
        _ = try loopbackURL("http://127.0.0.1:8080/")
        for text in ["https://example.com/", "http://localhost:8080/", "http://127.0.0.1/", "http://127.0.0.1:0/",
                     "http://127.0.0.1:65536/", "http://user@127.0.0.1:8080/", "http://127.0.0.1:8080/?x=1",
                     "http://127.0.0.1:8080/#x", "http://127.0.0.1:8080/other", "file:///tmp/compiler.html"] {
            do { _ = try loopbackURL(text) } catch Failure.invalidInput { continue }
            throw Failure.invalidInput("Address boundary accepted \(text)")
        }
        print("WebKit host address checks passed: 1 accepted, 10 rejected; no compiler executed")
    }

    /// Runs a bounded invisible WebKit host and saves only a successful, main-frame correlated report.
    static func main() async {
        do {
            if CommandLine.arguments == [CommandLine.arguments[0], "--check-inputs"] { try checkInputs(); return }
            guard CommandLine.arguments.count == 3 else { throw Failure.invalidInput("Usage: VerifyBuiltServiceWebKit numeric-loopback-origin new-report.json | --check-inputs") }
            let url = try loopbackURL(CommandLine.arguments[1])
            let output = URL(fileURLWithPath: CommandLine.arguments[2])
            guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure.invalidInput("Select a new report path") }
            _ = NSApplication.shared
            let host = Host(url: url, policyDirectory: output.deletingLastPathComponent().appendingPathComponent("policy"))
            let report = try await host.run()
            try Data(report.utf8).write(to: output, options: .withoutOverwriting)
            print("Native WebKit maintenance report saved; no device code executed")
        } catch { print("WebKit maintenance failed: \(error)"); exit(1) }
    }

    /// Carries address, lifetime, navigation, and report failures to the CLI's nonzero exit.
    enum Failure: Error {
        /// Invalid host input or untrusted report; no artifact may be published.
        case invalidInput(String)
    }

    /// Owns one ephemeral web view and settles its continuation once, removing every handler on completion.
    @MainActor final class Host: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        /// The single origin authorized by the caller's explicitly started read-only resource server.
        private let url: URL
        /// Keeps generated WebKit rule bytes in the caller-owned temporary output directory.
        private let policyDirectory: URL
        /// A nonpersistent, never displayed page; compiler execution stays in its module workers.
        private var view: WKWebView?
        /// The single pending report operation, cleared before resolving or rejecting it.
        private var continuation: CheckedContinuation<String, any Error>?
        /// Terminates the page even when synchronous WASM work cannot cooperate.
        private var deadline: Task<Void, Never>?
        /// Keeps native observation active while the invisible page executes its fixed maintenance promise.
        private var invocation: Task<Void, Never>?

        /// Records the checked loopback origin without fetching any content.
        init(url: URL, policyDirectory: URL) { self.url = url; self.policyDirectory = policyDirectory; super.init() }

        /// Installs a closed subresource policy before loading the page and waiting at most 120 seconds.
        func run() async throws -> String {
            let filter = "^http://127\\.0\\.0\\.1:\(url.port ?? 0)/"
            let rules: [[String: Any]] = [
                ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
                ["trigger": ["url-filter": filter], "action": ["type": "ignore-previous-rules"]]
            ]
            let encoded = try JSONSerialization.data(withJSONObject: rules)
            guard let text = String(data: encoded, encoding: .utf8) else { throw Failure.invalidInput("Invalid policy encoding") }
            try FileManager.default.createDirectory(at: policyDirectory, withIntermediateDirectories: false)
            guard let store = WKContentRuleListStore(url: policyDirectory) else {
                throw Failure.invalidInput("Could not create isolated WebKit policy store")
            }
            let policy: WKContentRuleList = try await withCheckedThrowingContinuation { pending in
                store.compileContentRuleList(forIdentifier: "firmingo-built-service-\(UUID().uuidString)", encodedContentRuleList: text) { list, error in
                    if let error { pending.resume(throwing: error) }
                    else if let list { pending.resume(returning: list) }
                    else { pending.resume(throwing: Failure.invalidInput("Missing WebKit resource policy")) }
                }
            }
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.add(policy)
            configuration.userContentController.add(self, name: "firmingoBuiltService")
            let page = WKWebView(frame: .zero, configuration: configuration)
            FileHandle.standardError.write(Data("WebKit policy installed; loading maintenance page\n".utf8))
            page.navigationDelegate = self
            view = page
            return try await withCheckedThrowingContinuation { pending in
                continuation = pending
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(120)) }
                    catch { return }
                    self?.finish(.failure(Failure.invalidInput("WebKit maintenance deadline exceeded")))
                }
                page.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
            }
        }

        /// Disposes the page and message handler before settling; late messages cannot become success.
        private func finish(_ result: Result<String, any Error>) {
            guard let pending = continuation else { return }
            continuation = nil
            deadline?.cancel(); deadline = nil
            invocation?.cancel(); invocation = nil
            view?.stopLoading()
            view?.configuration.userContentController.removeScriptMessageHandler(forName: "firmingoBuiltService")
            view?.configuration.userContentController.removeAllContentRuleLists()
            view?.navigationDelegate = nil; view = nil
            pending.resume(with: result)
        }

        /// Accepts bounded case progress from the selected main frame, never a child frame or alternate origin.
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "firmingoBuiltService", message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.protocol == "http", message.frameInfo.securityOrigin.host == "127.0.0.1",
                  message.frameInfo.securityOrigin.port == url.port, let text = message.body as? String,
                  text.utf8.count <= 65536 else {
                finish(.failure(Failure.invalidInput("Untrusted WebKit report sender or size"))); return
            }
            do {
                guard let report = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                    throw Failure.invalidInput("Invalid WebKit report object")
                }
                if report["schema"] as? Int == 1, report["progress"] is [String: Any], text.utf8.count <= 4096 {
                    FileHandle.standardError.write(Data((text + "\n").utf8)); return
                }
                throw Failure.invalidInput("Unexpected progress message")
            } catch { finish(.failure(error)) }
        }

        /// Dispatches the fixed page operation once; awaiting its promise keeps background WebKit execution active.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard continuation != nil, invocation == nil else { return }
            invocation = Task { @MainActor [weak self] in
                do {
                    let result = try await webView.callAsyncJavaScript("await globalThis.firmingoHarnessReady; return await globalThis.firmingoRunOwnedChecks();",
                        arguments: [:], in: nil, contentWorld: .page)
                    guard let text = result as? String, text.utf8.count <= 65536,
                          let report = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                          report["schema"] as? Int == 1, report["operation"] as? String == "owned_service_web_checks",
                          report["passed"] as? Int == 9, report["failed"] as? Int == 0,
                          report["consumerPinsChanged"] as? Bool == false, report["hardwareExecuted"] as? Bool == false else {
                        throw Failure.invalidInput("Incomplete or failing development report")
                    }
                    self?.finish(.success(text))
                } catch { self?.finish(.failure(error)) }
            }
        }

        /// Prevents navigation to new frames, alternate paths, or any external origin.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let allowed = navigationAction.targetFrame?.isMainFrame == true && navigationAction.request.url == url
            decisionHandler(allowed ? .allow : .cancel)
            if !allowed { finish(.failure(Failure.invalidInput("Unexpected WebKit navigation"))) }
        }

        /// Preserves provisional loading failures instead of allowing a timeout to mask them.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
            finish(.failure(error))
        }

        /// Preserves final navigation failures and prevents publishing partial artifacts.
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
            finish(.failure(error))
        }

        /// Rejects content-process termination rather than silently reloading or retrying the compiler.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            finish(.failure(Failure.invalidInput("WebKit content process terminated")))
        }
    }
}
