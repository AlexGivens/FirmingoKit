import Foundation
import WebKit

/// Owns one nonpersistent private page and fresh worker, discarded after every outcome.
@MainActor final class ManagedWebKitHost: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    /// Private browser context, never exposed to the host app or inserted into its UI.
    private var webView: WKWebView?
    /// One build continuation; nil after the first terminal outcome.
    private var completion: CheckedContinuation<String, any Error>?
    /// Owned asynchronous bridge invocation, canceled when the page is disposed.
    private var invocation: Task<Void, Never>?
    /// Owned end-to-end runtime deadline, canceled after completion.
    private var deadline: Task<Void, Never>?
    /// Immutable JSON-compatible source selection, created before navigation.
    private var input: [String: Any] = [:]
    /// Finite phase observer; callbacks run only for correlated validated worker progress.
    private var progress: (@Sendable (ManagedCompilationPhase) -> Void)?
    /// Enforces the worker's finite ordered progress sequence.
    private var phaseIndex = 0

    /// Starts one build with a bounded host deadline, cancellation and content-process failure cleanup.
    func run(prepared: PreparedManagedSketch, toolchain: VerifiedManagedToolchain,
             progress: @escaping @Sendable (ManagedCompilationPhase) -> Void,
             timeout: Duration = .seconds(60)) async throws -> String {
        try await run(board: prepared.request.board, profile: prepared.request.profile,
            filename: prepared.request.snapshot.filename, translationUnit: prepared.translationUnit,
            apiAddress: prepared.request.resident.apiAddress, toolchain: toolchain, progress: progress, timeout: timeout)
    }

    /// Runs the same private bridge for an immutable catalogue selection without any physical-device fields.
    func run(prepared: PreparedManagedOfflineSketch, toolchain: VerifiedManagedToolchain,
             progress: @escaping @Sendable (ManagedCompilationPhase) -> Void,
             timeout: Duration = .seconds(60)) async throws -> String {
        try await run(board: prepared.request.firmwareBuild.board, profile: prepared.request.firmwareBuild.profile,
            filename: prepared.request.snapshot.filename, translationUnit: prepared.translationUnit,
            apiAddress: prepared.request.firmwareBuild.apiAddress, toolchain: toolchain, progress: progress, timeout: timeout)
    }

    /// Initializes one isolated worker using only build-affecting metadata; no device association reaches JavaScript.
    private func run(board: FirmingoBoard, profile: ManagedSketchBuildRequest.Profile, filename: String,
                     translationUnit: String, apiAddress: UInt32, toolchain: VerifiedManagedToolchain,
                     progress: @escaping @Sendable (ManagedCompilationPhase) -> Void, timeout: Duration) async throws -> String {
        try Task.checkCancellation()
        input = ["schema": 1, "recipe": "nano-stateless-clang-22.1.8-v1-experimental",
                 "board": board.rawValue, "profile": profile.rawValue, "filename": filename,
                 "translationUnit": translationUnit, "apiAddress": apiAddress]
        self.progress = progress
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(ManagedCompilerOrigin(toolchain: toolchain), forURLScheme: "firmingo-compiler")
        configuration.userContentController.add(self, name: "firmingoCompiler")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isInspectable = false; view.navigationDelegate = self; webView = view
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.finish(.failure(ManagedCompilerError.timedOut))
                }
                guard let url = URL(string: "firmingo-compiler://assets/host.html") else {
                    finish(.failure(ManagedCompilerError.runtime("invalid resource origin"))); return
                }
                view.load(URLRequest(url: url))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }
    /// Calls only the private reviewed bridge once navigation completes; arguments never become executable source.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard completion != nil, invocation == nil else { return }
        invocation = Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await webView.callAsyncJavaScript("return await globalThis.firmingoCompiler.compile(input, identity);",
                    arguments: ["input": input, "identity": ["bytes": VerifiedManagedToolchain.serviceBytes, "sha256": VerifiedManagedToolchain.serviceSHA256]],
                    in: nil, contentWorld: .page)
                guard let json = result as? String, json.utf8.count <= 3_500_000 else {
                    throw ManagedCompilerError.runtime("invalid native bridge output")
                }
                finish(.success(json))
            } catch { self?.finish(.failure(error)) }
        }
    }
    /// Rejects every navigation away from the exact reviewed local page, including remote redirects.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.absoluteString == "firmingo-compiler://assets/host.html" ? .allow : .cancel)
    }
    /// Preserves navigation failure and terminates the only pending build.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    /// Preserves resource/provisional navigation failure and terminates the only pending build.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    /// Never reuses a page after WebKit content-process termination.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(ManagedCompilerError.runtime("WebKit content process terminated"))) }
    /// Accepts only bounded ordered progress from this page's main frame; unexpected messages fail the build.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard completion != nil else { return }
        do {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.absoluteString == "firmingo-compiler://assets/host.html",
                  let json = message.body as? String, json.utf8.count <= 256 else { throw WireJSON.invalid }
            let value = try WireJSON.parse(Data(json.utf8))
            guard Set(try value.object().keys) == Set([Data("kind".utf8), Data("phase".utf8)]),
                  try value.required("kind").string() == "progress" else { throw WireJSON.invalid }
            let phases: [ManagedCompilationPhase] = [.verifying, .compiling, .compiling, .linking]
            guard phaseIndex < phases.count, try value.required("phase").string() == phases[phaseIndex].rawValue else { throw WireJSON.invalid }
            progress?(phases[phaseIndex]); phaseIndex += 1
        } catch { finish(.failure(ManagedCompilerError.runtime("invalid progress bridge"))) }
    }
    /// Resolves once after removing all page/handler/task ownership; a late callback cannot affect another build.
    private func finish(_ result: Result<String, any Error>) {
        guard let continuation = completion else { return }
        completion = nil; progress = nil; input = [:]
        deadline?.cancel(); deadline = nil; invocation?.cancel(); invocation = nil
        if let view = webView {
            view.evaluateJavaScript("globalThis.firmingoCompiler?.cancel();")
            view.stopLoading(); view.navigationDelegate = nil
            view.configuration.userContentController.removeScriptMessageHandler(forName: "firmingoCompiler")
        }
        webView = nil
        continuation.resume(with: result)
    }
}
