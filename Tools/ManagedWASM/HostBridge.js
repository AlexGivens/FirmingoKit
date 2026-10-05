/** Bounded binary serialization accepted by the native bridge without giant function argument lists. */
function base64(bytes) {
  const chunks = [];
  for (let offset = 0; offset < bytes.length; offset += 16384) {
    chunks.push(String.fromCharCode(...bytes.subarray(offset, offset + 16384)));
  }
  return btoa(chunks.join(""));
}
/** Sole build-owned worker and blob URL; disposal always occurs before publishing its outcome. */
let active = null;
/** Prevents a second source revision entering an already consumed page. */
let consumed = false;
/** Terminates synchronous WASM immediately and rejects any pending browser promise. */
function cancel() {
  if (active === null) { return; }
  const state = active; active = null; state.worker.terminate(); URL.revokeObjectURL(state.url);
  state.reject(new Error("Compiler cancelled"));
}
/** Starts one fresh worker with only verified local module/recipe capabilities. */
async function compile(input, identity) {
  if (consumed) { throw new Error("Compiler page already consumed"); }
  consumed = true;
  const response = await fetch("firmingo-compiler://assets/compiler.wasm");
  if (!response.ok) { throw new Error("Local compiler service unavailable"); }
  const moduleBytes = new Uint8Array(await response.arrayBuffer());
  const url = URL.createObjectURL(new Blob([workerSource], { type: "text/javascript" }));
  const worker = new Worker(url);
  const result = await new Promise((resolve, reject) => {
    active = { worker, url, reject };
    /** Disposes this worker's capabilities before resolving or rejecting its only build. */
    const finish = (error, value) => {
      if (active?.worker !== worker) { return; }
      active = null; worker.terminate(); URL.revokeObjectURL(url);
      if (error) { reject(error); } else { resolve(value); }
    };
    worker.onerror = event => finish(new Error(event.message || "Compiler worker failed"));
    worker.onmessageerror = () => finish(new Error("Invalid compiler worker message"));
    worker.onmessage = event => {
      try {
        validateResponse(event.data, 1);
        if (event.data.kind === "progress") {
          globalThis.webkit.messageHandlers.firmingoCompiler.postMessage(JSON.stringify({kind:"progress",phase:event.data.phase}));
        } else if (event.data.kind === "failure") { finish(new Error(event.data.reason)); }
        else { finish(null, event.data.result); }
      } catch (error) { finish(error); }
    };
    const recipeAssets = recipeRecords.map(record => ({name:record.name,sha256:record.sha256,
      bytes:new Uint8Array(record.bytes)}));
    worker.postMessage({id:1,input,identity,moduleBytes,recipeAssets}, [moduleBytes.buffer]);
  });
  if (result.elf) { result.elfBase64 = base64(result.elf); delete result.elf; }
  return JSON.stringify(result);
}
/** Private native entry point; the host owns the page lifetime and end-to-end deadline. */
globalThis.firmingoCompiler = Object.freeze({compile,cancel});
