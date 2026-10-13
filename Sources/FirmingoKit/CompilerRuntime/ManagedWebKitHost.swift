import Foundation
import WebKit
#if os(macOS)
import AppKit
#endif

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
    private var inputJSON = ""
    /// Reviewed bridge entry point, selected only by the native operation overload.
    private var bridgeFunction = "compile"
    /// Exact active correlation validated in every bridge event.
    private var buildID = ""
    /// Last accepted sequence, including every actual portable progress event.
    private var sequence = 0
    /// Finite phase observer; callbacks run only for correlated validated worker progress.
    private var progress: (@Sendable (ManagedCompilationPhase) -> Void)?
    /// Enforces the worker's finite ordered progress sequence.
    private var phaseIndex = 0
    /// True only after native code dispatched the reviewed compiler call.
    private var compileDispatched = false

    /// Compatibility helper translates the captured legacy request, not its independently prepared text.
    func run(prepared: PreparedManagedSketch, toolchain: VerifiedManagedToolchain,
             progress: @escaping @Sendable (ManagedCompilationPhase) -> Void, timeout: Duration = .seconds(60)) async throws -> String {
        try await run(request: ManagedPortableRequest(prepared.request), toolchain: toolchain, progress: progress, timeout: timeout)
    }
    /// Compatibility helper translates the captured offline request without a physical association.
    func run(prepared: PreparedManagedOfflineSketch, toolchain: VerifiedManagedToolchain,
             progress: @escaping @Sendable (ManagedCompilationPhase) -> Void, timeout: Duration = .seconds(60)) async throws -> String {
        try await run(request: ManagedPortableRequest(prepared.request), toolchain: toolchain, progress: progress, timeout: timeout)
    }
    /// Starts the portable compiler with a bounded native deadline and immutable raw source selection.
    func run(request: ManagedPortableRequest, toolchain: VerifiedManagedToolchain,
             progress: @escaping @Sendable (ManagedCompilationPhase) -> Void, timeout: Duration = .seconds(60)) async throws -> String {
        try await run(request: request, page: toolchain.page, service: toolchain.service, function: "compile", progress: progress, timeout: timeout)
    }
    /// Runs service-free source preparation through the same bounded private-page ownership/disposal path.
    func prepare(request: ManagedPortableRequest, page: Data, timeout: Duration = .seconds(60)) async throws -> String {
        try await run(request: request, page: page, service: nil, function: "prepare", progress: { _ in }, timeout: timeout)
    }
    /// Admits one page operation with exact resource capabilities and a native loading-through-disposal deadline.
    private func run(request: ManagedPortableRequest, page: Data, service: Data?, function: String,
                     progress: @escaping @Sendable (ManagedCompilationPhase) -> Void, timeout: Duration) async throws -> String {
        try Task.checkCancellation()
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        bridgeFunction = function
        inputJSON = String(decoding: request.json, as: UTF8.self); buildID = request.buildID
        self.progress = progress
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(ManagedCompilerOrigin(page: page, service: service), forURLScheme: "firmingo-compiler")
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
                guard let self, completion != nil else { return }
                compileDispatched = true
                let result = try await webView.callAsyncJavaScript("return await globalThis.firmingoCompiler[operation](inputJSON);",
                    arguments: ["inputJSON": inputJSON, "operation": bridgeFunction],
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
                  let json = message.body as? String, json.utf8.count <= 512 else { throw WireJSON.invalid }
            let value = try WireJSON.parse(Data(json.utf8))
            guard Set(try value.object().keys) == Set(["interfaceVersion", "buildID", "sequence", "kind", "phase"].map { Data($0.utf8) }),
                  try value.required("interfaceVersion").uint32() == 1, try value.required("buildID").string() == buildID,
                  try value.required("sequence").uint32() == sequence + 1,
                  try value.required("kind").string() == "progress" else { throw WireJSON.invalid }
            let phases = ["verifying", "preprocessing", "compiling", "compiling", "linking", "validating", "packaging"]
            guard phaseIndex < phases.count, try value.required("phase").string() == phases[phaseIndex] else { throw WireJSON.invalid }
            let mapped: ManagedCompilationPhase? = switch phases[phaseIndex] {
            case "verifying": .verifying
            case "preprocessing": .preparing
            case "compiling": .compiling
            case "linking": .linking
            case "packaging": .packaging
            default: nil // Internal validation is checked but does not add a new public enum case.
            }
            if let mapped { progress?(mapped) }; phaseIndex += 1; sequence += 1
        } catch { finish(.failure(ManagedCompilerError.runtime("invalid progress bridge"))) }
    }
    /// Resolves once after removing all page/handler/task ownership; a late callback cannot affect another build.
    private func finish(_ result: Result<String, any Error>) {
        guard let continuation = completion else { return }
        completion = nil; progress = nil; inputJSON = ""
        deadline?.cancel(); deadline = nil; invocation?.cancel(); invocation = nil
        let view = webView; webView = nil
        if let view {
            view.navigationDelegate = nil
            view.configuration.userContentController.removeScriptMessageHandler(forName: "firmingoCompiler")
        }
        Task { @MainActor in
            let disposed = if let view { await ManagedWebKitDisposal().run(view, dispatched: compileDispatched) } else { true }
            view?.stopLoading()
            if disposed { continuation.resume(with: result) }
            else { continuation.resume(throwing: ManagedCompilerError.runtime("private compiler worker did not acknowledge cleanup")) }
        }
    }
}

/// Bounds native cleanup and acknowledges only the portable controller's completed cancellation/disposal.
@MainActor private final class ManagedWebKitDisposal {
    /// One bounded cleanup continuation, consumed exactly once.
    private var completion: CheckedContinuation<Bool, Never>?
    /// Pending JavaScript acknowledgment, released on response or timeout.
    private var invocation: Task<Void, Never>?
    /// Native cleanup watchdog independent of synchronous worker progress.
    private var deadline: Task<Void, Never>?
    /// Cancels before any late queued compile call can start, then waits for worker termination.
    func run(_ view: WKWebView, dispatched: Bool) async -> Bool {
        if !dispatched { view.stopLoading(); return true }
        return await withCheckedContinuation { continuation in
            completion = continuation
            deadline = Task { do { try await Task.sleep(for: .seconds(2)) } catch { return }; finish(false) }
            invocation = Task {
                do {
                    let result = try await view.callAsyncJavaScript("return await globalThis.firmingoCompiler?.cancel();", arguments: [:], in: nil, contentWorld: .page)
                    finish((result as? Bool) == true)
                } catch {
                    view.stopLoading()
                    let failure = error as NSError
                    finish(failure.domain == WKError.errorDomain && failure.code == WKError.Code.webContentProcessTerminated.rawValue)
                }
            }
        }
    }
    /// Resolves at most once and releases every owned cleanup task.
    private func finish(_ value: Bool) {
        guard let continuation = completion else { return }
        completion = nil; deadline?.cancel(); deadline = nil; invocation?.cancel(); invocation = nil
        continuation.resume(returning: value)
    }
}
