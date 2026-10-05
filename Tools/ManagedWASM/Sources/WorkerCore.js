import { digestSHA256 } from "./Digest.js";
import { compileModule, ManagedService } from "./ManagedService.js";
import { validateInput } from "./ManagedRecipe.js";

/** Validates a one-build transfer envelope before instantiation or workspace construction. */
export function validateRequest(message) {
  if (!message || typeof message !== "object" || Array.isArray(message)
      || Object.keys(message).sort().join() !== "id,identity,input,moduleBytes,recipeAssets"
      || !Number.isSafeInteger(message.id) || message.id < 1 || !Array.isArray(message.recipeAssets)
      || message.recipeAssets.length !== 3 || !(message.moduleBytes instanceof Uint8Array)
      || message.moduleBytes.length > 128 * 1024 * 1024) { throw new Error("Invalid compiler worker envelope"); }
  validateInput(message.input);
  const names = new Set(); let total = 0;
  for (const asset of message.recipeAssets) {
    if (!asset || Object.keys(asset).sort().join() !== "bytes,name,sha256" || !["Arduino.h", "Entry.cpp", "Module.ld"].includes(asset.name)
        || names.has(asset.name) || !(asset.bytes instanceof Uint8Array) || asset.bytes.length === 0
        || asset.bytes.length > 65536 || !/^[0-9a-f]{64}$/.test(asset.sha256)) { throw new Error("Invalid recipe asset envelope"); }
    names.add(asset.name); total += asset.bytes.length;
  }
  if (total > 128 * 1024) { throw new Error("Excessive recipe bytes"); }
}
/** Verifies every transferred recipe file, then creates and consumes one fresh in-memory service instance. */
export async function executeRequest(message, progress) {
  validateRequest(message);
  const files = new Map();
  for (const asset of message.recipeAssets) {
    const digest = await digestSHA256(asset.bytes);
    const hex = [...digest].map(byte => byte.toString(16).padStart(2, "0")).join("");
    if (hex !== asset.sha256) { throw new Error("Managed recipe asset digest mismatch"); }
    files.set(asset.name, asset.bytes);
  }
  progress("verifying");
  const start = performance.now();
  const module = await compileModule(message.moduleBytes, message.identity);
  const moduleMilliseconds = performance.now() - start;
  const instantiateStart = performance.now();
  const service = await ManagedService.create(module, files);
  const instantiateMilliseconds = performance.now() - instantiateStart;
  const result = service.run(message.input, progress);
  return { ...result, moduleMilliseconds, instantiateMilliseconds };
}
/** Installs a single-operation worker protocol in a browser or the development Node adapter. */
export function installWorker(receive, send) {
  let consumed = false;
  receive(async message => {
    if (consumed) { return; }
    consumed = true;
    const id = Number.isSafeInteger(message?.id) ? message.id : 0;
    try {
      const result = await executeRequest(message, phase => send({ id, kind: "progress", phase }));
      const transfer = result.elf ? [result.elf.buffer] : [];
      send({ id, kind: "result", result }, transfer);
    } catch (error) {
      // The controller discards this worker on any thrown/trapped/invalid state; no compiler instance is reused.
      const reason = error instanceof Error ? error.message : String(error);
      send({ id, kind: "failure", reason: reason.slice(0, 1024) });
    }
  });
}
