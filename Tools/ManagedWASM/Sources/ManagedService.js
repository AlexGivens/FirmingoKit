import { digestSHA256 } from "./Digest.js";
import { WASI, Fd, wasi } from "../Vendor/browser_wasi_shim/dist/index.js";
import { Workspace, OutputCapture } from "./Workspace.js";
import { contract, makeJobs } from "./ManagedRecipe.js";
import { requireBoundedMemory } from "./ModuleMemory.js";

/** Required stable exports of the pinned ABI-two compiler service, not arbitrary module exports. */
const requiredExports = ["_initialize", "malloc", "free", "arduino_compiler_service_abi_version",
  "arduino_compiler_service_compile", "arduino_compiler_service_link",
  "arduino_compiler_service_last_diagnostics", "arduino_compiler_service_last_diagnostics_size",
  "arduino_compiler_service_can_run_again"];
/** Empty immutable stdin; inherited mutation calls reject rather than allocating a hidden buffer. */
class EmptyInput extends Fd {
  /** Reports a regular readonly descriptor for libc. */
  fd_fdstat_get() { return { ret: 0, fdstat: new wasi.Fdstat(wasi.FILETYPE_REGULAR_FILE, 0) }; }
  /** Always signals EOF without input ownership or a host filesystem. */
  fd_read() { return { ret: 0, data: new Uint8Array() }; }
  /** Positioned reads also signal EOF. */
  fd_pread() { return this.fd_read(); }
}
/** Verifies import/export shape before instantiation, rejecting native or non-WASI capabilities. */
export function validateModule(module) {
  const imports = WebAssembly.Module.imports(module);
  if (imports.some(item => item.module !== "wasi_snapshot_preview1" || item.kind !== "function")) {
    throw new Error("Only WASI Preview 1 function imports are allowed");
  }
  const exports = WebAssembly.Module.exports(module);
  if (!exports.some(item => item.name === "memory" && item.kind === "memory")
      || requiredExports.some(name => !exports.some(item => item.name === name && item.kind === "function"))) {
    throw new Error("Compiler module omits required ABI-two exports");
  }
}
/** Compiles only a size/digest-verified local service; callers provide exact approved asset identity. */
export async function compileModule(bytes, identity) {
  if (!(bytes instanceof Uint8Array) || !identity || !Number.isSafeInteger(identity.bytes)
      || identity.bytes < 8 || identity.bytes > 128 * 1024 * 1024 || bytes.length !== identity.bytes
      || !/^[0-9a-f]{64}$/.test(identity.sha256)) { throw new Error("Invalid compiler asset bounds or identity"); }
  const digest = await digestSHA256(bytes);
  const hex = [...digest].map(byte => byte.toString(16).padStart(2, "0")).join("");
  if (hex !== identity.sha256) { throw new Error("Compiler asset digest mismatch"); }
  requireBoundedMemory(bytes);
  const module = await WebAssembly.compile(bytes); validateModule(module); return module;
}
/** Reads a bounded service diagnostic buffer, never assuming NUL termination or stale memory views. */
function diagnosticText(exports) {
  const pointer = Number(exports.arduino_compiler_service_last_diagnostics());
  const count = Number(exports.arduino_compiler_service_last_diagnostics_size());
  const memory = new Uint8Array(exports.memory.buffer);
  if (!Number.isSafeInteger(pointer) || !Number.isSafeInteger(count) || pointer < 0 || count < 0
      || count > 256 * 1024 || pointer > memory.length || count > memory.length - pointer) {
    throw new Error("Compiler diagnostics exceed the bounded exported buffer");
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(memory.subarray(pointer, pointer + count));
}
/** Invokes a service operation using one checked, owned, terminated path allocation. */
function invoke(exports, path, operation) {
  const encoded = new TextEncoder().encode(path);
  const pointer = Number(exports.malloc(encoded.length + 1));
  if (!Number.isSafeInteger(pointer) || pointer <= 0 || pointer > exports.memory.buffer.byteLength - encoded.length - 1) {
    throw new Error("Invalid service path allocation");
  }
  try {
    const view = new Uint8Array(exports.memory.buffer); view.set(encoded, pointer); view[pointer + encoded.length] = 0;
    const status = operation(pointer);
    if (!Number.isInteger(status)) { throw new Error("Service omitted integer operation status"); }
    return status;
  } finally { exports.free(pointer); }
}
/** Strict source-mapped Clang/LLD diagnostics; unmapped failure text remains visible as a diagnostic. */
export function parseDiagnostics(text) {
  if (new TextEncoder().encode(text).length > 256 * 1024) { throw new Error("Excessive combined diagnostics"); }
  const diagnostics = [];
  for (const raw of text.split(/\r?\n/)) {
    if (raw.trim() === "") { continue; }
    const match = /^(.*?):([1-9][0-9]*):([1-9][0-9]*): (fatal error|error|warning|note): (.*)$/.exec(raw);
    const plain = /^(?:[^:]+: )?(fatal error|error|warning|note): (.*)$/.exec(raw);
    let result;
    if (match) {
      const line = Number(match[2]); const column = Number(match[3]);
      if (!Number.isSafeInteger(line) || !Number.isSafeInteger(column)) { throw new Error("Invalid diagnostic position"); }
      result = { severity: match[4] === "fatal error" ? "error" : match[4], message: match[5], filename: match[1], line, column };
    } else if (plain) {
      result = { severity: plain[1] === "fatal error" ? "error" : plain[1], message: plain[2], filename: null, line: null, column: null };
    } else {
      result = { severity: "note", message: raw, filename: null, line: null, column: null };
    }
    if (new TextEncoder().encode(result.message).length > 4096
        || (result.filename !== null && new TextEncoder().encode(result.filename).length > 256)
        || diagnostics.length >= 128) { throw new Error("Excessive compiler diagnostic records"); }
    diagnostics.push(result);
  }
  return diagnostics;
}
/** A one-build service instance: new WASI descriptors, memory and mutable compiler state for each revision. */
export class ManagedService {
  /** Instantiates the verified compiled module in a closed in-memory capability space. */
  static async create(module, recipeFiles) {
    validateModule(module);
    if (!(recipeFiles instanceof Map) || [...recipeFiles.keys()].sort().join() !== "Arduino.h,Entry.cpp,Module.ld") {
      throw new Error("Require only the exact managed recipe resources");
    }
    const toolchain = new Workspace("/toolchain", recipeFiles);
    const workspace = new Workspace("/workspace");
    const stdout = new OutputCapture(); const stderr = new OutputCapture();
    const wasiHost = new WASI(["firmingo-managed-compiler"], ["LC_ALL=C", "TZ=UTC"],
      [new EmptyInput(), stdout, stderr, toolchain, workspace], { debug: false });
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasiHost.wasiImport });
    if (instance.exports.memory.buffer.byteLength > 256 * 1024 * 1024) { throw new Error("Excessive initial compiler memory"); }
    wasiHost.initialize(instance);
    if (instance.exports.arduino_compiler_service_abi_version() !== contract.serviceABI) { throw new Error("Compiler service ABI mismatch"); }
    return new ManagedService(instance.exports, workspace, stdout, stderr);
  }
  /** Captures a fresh instance; callers must not replace exports or workspace after creation. */
  constructor(exports, workspace, stdout, stderr) {
    this.exports = exports; this.workspace = workspace; this.stdout = stdout; this.stderr = stderr; this.consumed = false;
  }
  /** Compiles and links exactly one prepared revision, with real phase timings and no execution side effect. */
  run(input, progress = () => {}) {
    if (this.consumed) { throw new Error("Service instance already consumed; create a fresh build workspace"); }
    this.consumed = true;
    const jobs = makeJobs(input); const encoder = new TextEncoder();
    this.workspace.insert("Sketch.cpp", encoder.encode(input.translationUnit));
    for (const job of jobs) { this.workspace.insert(job.path.slice("/workspace/".length), job.bytes); }
    const timings = []; const messages = []; let canRunAgain = true;
    for (const job of jobs) {
      progress(job.phase);
      const start = performance.now();
      const operation = job.phase === "compiling" ? this.exports.arduino_compiler_service_compile : this.exports.arduino_compiler_service_link;
      const status = invoke(this.exports, job.path, operation);
      timings.push({ phase: job.phase, milliseconds: performance.now() - start });
      canRunAgain = this.exports.arduino_compiler_service_can_run_again() === 1;
      messages.push(diagnosticText(this.exports));
      if (this.exports.memory.buffer.byteLength > 256 * 1024 * 1024) { throw new Error("Excessive compiler memory"); }
      // The observed service may return zero after a frontend error: diagnostics are a separate gate.
      if (status !== 0 || !canRunAgain || parseDiagnostics(messages.join("\n")).some(item => item.severity === "error")) {
        return this.result(false, status, canRunAgain, messages, timings, input.filename);
      }
    }
    const result = this.result(true, 0, canRunAgain, messages, timings, input.filename);
    if (result.diagnostics.some(item => item.severity === "error")) { throw new Error("Successful service returned error diagnostics"); }
    const elf = this.workspace.read("Sketch.elf");
    if (elf.length < 52) { throw new Error("Compiler omitted linked ELF"); }
    return { ...result, elf };
  }
  /** Retains structured and unmatched service output without silently dropping errors. */
  result(succeeded, status, canRunAgain, messages, timings, filename) {
    const decode = new TextDecoder("utf-8", { fatal: true });
    const console = [decode.decode(this.stdout.bytes), decode.decode(this.stderr.bytes)].join("\n");
    const diagnostics = parseDiagnostics([...messages, console].join("\n"));
    // The observed service can report physical workspace positions despite #line; do not remap presumed names twice.
    for (const diagnostic of diagnostics) {
      if (diagnostic.filename === "/workspace/Sketch.cpp" && diagnostic.line >= 3) {
        diagnostic.filename = filename; diagnostic.line -= 2;
      }
    }
    if (!succeeded && !diagnostics.some(item => item.severity === "error")) {
      diagnostics.push({ severity: "error", message: `Compiler service failed with status ${status}; safe re-entry: ${canRunAgain}`,
        filename: null, line: null, column: null });
    }
    return { succeeded, status, canRunAgain, diagnostics, timings, memoryBytes: this.exports.memory.buffer.byteLength };
  }
}
