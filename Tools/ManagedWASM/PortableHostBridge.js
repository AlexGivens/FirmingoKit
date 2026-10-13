/** Native WebKit adapter only; all compilation/preparation/packaging is imported from Firmingo-Compiler. */
let consumed = false, cancelled = false, pending = null, cancellation = null;
const workerFactory = source => () => {
  const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
  let worker;
  try { worker = new Worker(url); } catch (error) { URL.revokeObjectURL(url); throw error; }
  return { postMessage: (value, transfers) => worker.postMessage(value, transfers),
    terminate() { worker.terminate(); URL.revokeObjectURL(url); },
    listen(message, error) {
      const receive = event => message(event.data), failed = () => error(new Error("WebKit compiler worker failed"));
      worker.addEventListener("message", receive); worker.addEventListener("error", failed); worker.addEventListener("messageerror", failed);
      return () => { worker.removeEventListener("message", receive); worker.removeEventListener("error", failed); worker.removeEventListener("messageerror", failed); };
    } };
};
const controller = new FirmingoCompiler.CompilerController({ workerFactory: workerFactory(workerSource) });
const preparationController = new FirmingoCompiler.PreparationController({ workerFactory: workerFactory(preparationWorkerSource) });
const packagingController = new FirmingoCompiler.PackagingController({ workerFactory: workerFactory(preparationWorkerSource) });
/** Bounded ELF transfer for independent native validation/receipt translation, never native packaging. */
function encodeBytes(bytes) {
  const chunks = []; for (let offset = 0; offset < bytes.length; offset += 16384) chunks.push(String.fromCharCode(...bytes.subarray(offset, offset + 16384)));
  return btoa(chunks.join(""));
}
async function execute(inputJSON) {
  const request = FirmingoCompiler.parseBuildRequest(inputJSON);
  let terminal;
  const assets = { recipeManifest: new Uint8Array(recipeResources.recipeManifest), recipeAssets: Object.fromEntries(Object.entries(recipeResources.recipeAssets)
    .map(([name, bytes]) => [name, new Uint8Array(bytes)])) };
  try {
    const response = await fetch("firmingo-compiler://assets/compiler.wasm", { signal: cancellation.signal });
    if (!response.ok) throw new Error("Verified local service unavailable");
    const serviceBytes = new Uint8Array(await response.arrayBuffer());
    if (cancelled) throw new Error("Native build cancelled");
    const result = await controller.build(request, { ...assets, serviceBytes }, { signal: cancellation.signal, onEvent: event => {
      if (event.kind === "progress") globalThis.webkit.messageHandlers.firmingoCompiler.postMessage(JSON.stringify(event));
      if (event.kind === "result") terminal = event;
    } });
    const prepared = await FirmingoCompiler.prepareSketch(request);
    return JSON.stringify({ schema: 1, event: JSON.parse(FirmingoCompiler.serializeRuntimeEvent(terminal)),
      preparation: { translationUnit: prepared.translationUnit, sourceLineCount: prepared.sourceLineCount, sourceBOMBytes: prepared.sourceBOMBytes },
      diagnostics: result.diagnostics, memoryBytes: result.memoryBytes, linkedELFBase64: encodeBytes(result.linkedELF) });
  } catch (error) {
    if (!terminal) throw error;
    return JSON.stringify({ schema: 1, event: JSON.parse(FirmingoCompiler.serializeRuntimeEvent(terminal)), diagnostics: error.diagnostics || [] });
  }
}
/** One private page consumes one raw immutable request; inputs are arguments, never script source. */
async function compile(inputJSON) {
  if (consumed || cancelled) throw new Error("Compiler page already consumed/cancelled");
  consumed = true; cancellation = new AbortController(); pending = execute(inputJSON);
  return await pending;
}
/** Prepares raw source using the isolated compiler stage, without loading or executing a service. */
async function prepare(inputJSON) {
  if (consumed || cancelled) throw new Error("Compiler page already consumed/cancelled");
  consumed = true; cancellation = new AbortController();
  const request = FirmingoCompiler.parseBuildRequest(inputJSON);
  pending = (async () => {
    const common = { schema: 1, operation: "prepare", buildID: request.buildID, requestSHA256: await FirmingoCompiler.requestIdentity(request) };
    try {
      const { request: captured, ...preparation } = await preparationController.prepare(request, { signal: cancellation.signal });
      return JSON.stringify({ ...common, outcome: "succeeded", preparation });
    } catch (error) {
      return JSON.stringify({ ...common, outcome: error.code === "cancelled" ? "cancelled" : error.code === "timed_out" ? "timed_out" : "failed",
        error: { code: error.code || "runtime_failed", stage: "preprocessing", message: error.message }, diagnostics: error.diagnostics || [] });
    }
  })();
  return await pending;
}
/** Acknowledges cancellation only after loading/build work settles and the compiler disposes its worker. */
async function cancel() {
  cancelled = true; cancellation?.abort();
  if (pending) { try { await pending; } catch {} }
  return true;
}
/** Declared supplied-ELF conversion through the shared service-free worker, without recipe/service substitution. */
async function packageELF(inputJSON, elfBase64) {
  if (consumed || cancelled) throw new Error("Compiler page already consumed/cancelled");
  consumed = true; cancellation = new AbortController();
  const request = FirmingoCompiler.parseDeclaredPackagingRequest(inputJSON);
  if (typeof elfBase64 !== "string" || elfBase64.length > 2796204) throw new Error("Excessive ELF transfer");
  const decoded = atob(elfBase64);
  if (decoded.length < 52 || decoded.length > 2097152 || btoa(decoded) !== elfBase64) throw new Error("Invalid ELF transfer");
  const elfBytes = Uint8Array.from(decoded, value => value.charCodeAt(0));
  pending = (async () => {
    const common = { schema: 1, operation: "package_elf", buildID: request.buildID,
      requestSHA256: await FirmingoCompiler.declaredPackagingIdentity(request) };
    try {
      const artifact = await packagingController.package(elfBytes, request, { signal: cancellation.signal });
      return JSON.stringify({ ...common, outcome: "succeeded", artifact: { format: artifact.format, filename: artifact.filename,
        bytes: encodeBytes(artifact.bytes), sha256: artifact.sha256, reportJSON: artifact.reportJSON, receipt: artifact.receipt } });
    } catch (error) {
      return JSON.stringify({ ...common, outcome: error.code === "cancelled" ? "cancelled" : error.code === "timed_out" ? "timed_out" : "failed",
        error: { code: error.code || "runtime_failed", stage: error.stage || "packaging", message: error.message }, diagnostics: error.diagnostics || [] });
    }
  })();
  return await pending;
}
globalThis.firmingoCompiler = Object.freeze({ compile, prepare, packageELF, cancel });
