import test from "node:test";
import assert from "node:assert/strict";
import { validateResponse } from "../Sources/WorkerResponse.js";

/** Complete synthetic success is only a bridge vector, never compiler or executable evidence. */
function success() {
  return { id: 1, kind: "result", result: { succeeded: true, status: 0, canRunAgain: true, diagnostics: [],
    timings: [{ phase: "compiling", milliseconds: 1 }, { phase: "compiling", milliseconds: 2 }, { phase: "linking", milliseconds: 3 }],
    memoryBytes: 65536, moduleMilliseconds: 1, instantiateMilliseconds: 1, elf: new Uint8Array(52) } };
}
/// Correlation and closed bridge schemas reject unknown progress/failure fields.
test("strict worker correlation and envelope shapes", () => {
  validateResponse({ id: 1, kind: "progress", phase: "compiling" }, 1);
  for (const response of [{ id: 2, kind: "progress", phase: "compiling" }, { id: 1, kind: "progress", phase: "done" },
    { id: 1, kind: "progress", phase: "compiling", extra: true }, { id: 1, kind: "failure", reason: "\0" }]) {
    assert.throws(() => validateResponse(response, 1));
  }
});
/// Structured diagnostics, safe-reentry, output bounds and real phase order are separate success gates.
test("worker result validation cannot ignore malformed output or diagnostics", () => {
  validateResponse(success(), 1);
  for (const changes of [{ status: 1 }, { canRunAgain: false }, { diagnostics: [{ severity: "warning" }] },
    { memoryBytes: 268435457 }, { moduleMilliseconds: Infinity }, { elf: new Uint8Array(51) },
    { timings: [{ phase: "linking", milliseconds: 1 }] }, { extra: true }]) {
    const response = success(); Object.assign(response.result, changes); assert.throws(() => validateResponse(response, 1));
  }
  const response = success(); response.result.succeeded = false; delete response.result.elf;
  assert.throws(() => validateResponse(response, 1));
  response.result.diagnostics = [{ severity: "error", message: "frontend error despite zero status", filename: "Sketch.ino", line: 1, column: 1 }];
  validateResponse(response, 1);
});
