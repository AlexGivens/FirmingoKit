import { Worker } from "node:worker_threads";
import { validateRequest } from "./Sources/WorkerCore.js";
import { validateResponse } from "./Sources/WorkerResponse.js";

/** Local development worker controller, with cancellation, one-job correlation and timeout cleanup. */
export async function compileInWorker(message, { signal, timeoutMilliseconds = 60000, progress = () => {} } = {}) {
  validateRequest(message);
  if (!Number.isInteger(timeoutMilliseconds) || timeoutMilliseconds < 1 || timeoutMilliseconds > 120000) {
    throw new Error("Invalid compiler deadline");
  }
  if (signal?.aborted) { throw new DOMException("Compiler cancelled", "AbortError"); }
  const worker = new Worker(new URL("./NodeWorker.mjs", import.meta.url));
  return await new Promise((resolve, reject) => {
    let settled = false;
    /** Stops the worker before publishing any outcome; synchronous WASM cannot outlive a cancelled caller. */
    const finish = async (error, result) => {
      if (settled) { return; }
      settled = true; clearTimeout(timer); signal?.removeEventListener("abort", cancel);
      try { await worker.terminate(); } catch (cleanupError) { reject(cleanupError); return; }
      if (error) { reject(error); } else { resolve(result); }
    };
    /** Cancels promptly even while Clang/LLD is executing synchronously on the worker. */
    const cancel = () => { void finish(new DOMException("Compiler cancelled", "AbortError")); };
    const timer = setTimeout(() => { void finish(new Error("Compiler deadline exceeded")); }, timeoutMilliseconds);
    signal?.addEventListener("abort", cancel, { once: true });
    worker.on("error", error => { void finish(error); });
    worker.on("exit", code => { if (!settled) { void finish(new Error(`Compiler worker exited with ${code}`)); } });
    worker.on("message", response => {
      if (settled) { return; }
      try {
        validateResponse(response, message.id);
        if (response.kind === "progress") {
          progress(response.phase); return;
        }
        if (response.kind === "failure") {
          void finish(new Error(response.reason)); return;
        }
        void finish(null, response.result);
      } catch (error) { void finish(error); }
    });
    // A controller owns its module buffer; structured clone avoids detaching a caller's immutable inputs.
    worker.postMessage(message);
  });
}
