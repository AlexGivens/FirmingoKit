/** Checks exact bridge object fields, excluding arrays and silently ignored additive data. */
function fields(value, expected) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).sort().join() === expected.slice().sort().join();
}
/** Applies a UTF-8 byte bound to textual bridge data without trusting JavaScript's UTF-16 length. */
function text(value, maximum) {
  return typeof value === "string" && value.length > 0 && !value.includes("\0") && new TextEncoder().encode(value).length <= maximum;
}
/** Requires finite nonnegative phase durations, independent of host deadlines. */
function duration(value) { return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 120000; }
/** Decodes one correlated progress/failure/result without dropping malformed diagnostics or fields. */
export function validateResponse(response, id) {
  if (!response || response.id !== id) { throw new Error("Invalid worker correlation"); }
  if (response.kind === "progress") {
    if (!fields(response, ["id", "kind", "phase"]) || !["verifying", "compiling", "linking"].includes(response.phase)) {
      throw new Error("Invalid worker progress");
    }
    return response;
  }
  if (response.kind === "failure") {
    if (!fields(response, ["id", "kind", "reason"]) || !text(response.reason, 4096)) { throw new Error("Invalid worker failure"); }
    return response;
  }
  const result = response.result;
  const keys = ["succeeded", "status", "canRunAgain", "diagnostics", "timings", "memoryBytes", "moduleMilliseconds", "instantiateMilliseconds"];
  if (result?.succeeded === true) { keys.push("elf"); }
  if (!fields(response, ["id", "kind", "result"]) || response.kind !== "result" || !fields(result, keys)
      || typeof result.succeeded !== "boolean" || typeof result.canRunAgain !== "boolean"
      || !Number.isInteger(result.status) || result.status < -2147483648 || result.status > 2147483647
      || !Number.isSafeInteger(result.memoryBytes) || result.memoryBytes < 65536 || result.memoryBytes > 268435456
      || !duration(result.moduleMilliseconds) || !duration(result.instantiateMilliseconds)
      || !Array.isArray(result.diagnostics) || result.diagnostics.length > 128
      || !Array.isArray(result.timings) || result.timings.length < 1 || result.timings.length > 3) {
    throw new Error("Invalid worker result");
  }
  for (const [index, timing] of result.timings.entries()) {
    if (!fields(timing, ["phase", "milliseconds"]) || timing.phase !== (index < 2 ? "compiling" : "linking") || !duration(timing.milliseconds)) {
      throw new Error("Invalid compiler timing sequence");
    }
  }
  for (const diagnostic of result.diagnostics) {
    if (!fields(diagnostic, ["severity", "message", "filename", "line", "column"])
        || !["error", "warning", "note"].includes(diagnostic.severity) || !text(diagnostic.message, 4096)
        || !(diagnostic.filename === null || text(diagnostic.filename, 256))
        || !((diagnostic.line === null && diagnostic.column === null) ||
          (diagnostic.filename !== null && Number.isSafeInteger(diagnostic.line) && diagnostic.line > 0
            && Number.isSafeInteger(diagnostic.column) && diagnostic.column > 0))) {
      throw new Error("Invalid compiler diagnostic record");
    }
  }
  const errors = result.diagnostics.some(item => item.severity === "error");
  if (result.succeeded) {
    if (result.status !== 0 || !result.canRunAgain || errors || result.timings.length !== 3
        || !(result.elf instanceof Uint8Array) || result.elf.length < 52 || result.elf.length > 2 * 1024 * 1024) {
      throw new Error("Incomplete successful compiler result");
    }
  } else if (!errors) { throw new Error("Failed compiler result omitted its error"); }
  return response;
}
