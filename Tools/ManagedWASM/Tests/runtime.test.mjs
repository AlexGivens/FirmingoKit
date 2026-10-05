import test from "node:test";
import assert from "node:assert/strict";
import { Workspace, OutputCapture, limits } from "../Sources/Workspace.js";
import { contract, validateInput, makeJobs } from "../Sources/ManagedRecipe.js";
import { parseDiagnostics, ManagedService, compileModule } from "../Sources/ManagedService.js";
import { validateRequest } from "../Sources/WorkerCore.js";
import { boundMemory, memoryLimits, requireBoundedMemory } from "../Sources/ModuleMemory.js";
import { wasi } from "../Vendor/browser_wasi_shim/dist/index.js";
import { loadRecipeAssets, verifyVendoredAssets } from "../DevelopmentAssets.mjs";

/** Valid fake preparation for parser/workspace tests, without compiler execution. */
function input(changes = {}) {
  return { schema: 1, recipe: contract.recipe, board: contract.board, profile: contract.profile,
    filename: "Sketch.ino", apiAddress: 0x10020000,
    translationUnit: '#include <Arduino.h>\n#line 1 "Sketch.ino"\nvoid setup() {} void loop() {}\n', ...changes };
}
/** Opens one test descriptor using explicit WASI flags/rights, without host filesystem access. */
function open(workspace, path, flags = 0, rights = 0n) {
  return workspace.path_open(0, path, flags, rights, 0n, 0);
}
/** Creates bounded fake resource transfer envelopes for pure request-shape tests. */
function envelope(changes = {}) {
  return { id: 1, input: input(), moduleBytes: new Uint8Array(8), identity: { bytes: 8, sha256: "0".repeat(64) },
    recipeAssets: ["Arduino.h", "Entry.cpp", "Module.ld"].map(name => ({ name, bytes: new Uint8Array([1]), sha256: "1".repeat(64) })), ...changes };
}

/// Local recipe/argument and unmodified third-party/runtime license hashes must match before a development build.
test("recipe and licensed WASI resources match recorded versioned identities", () => {
  verifyVendoredAssets(); assert.equal(loadRecipeAssets().length, 3);
});

/// Board/profile/recipe/API identity and prepared filename mapping cannot be substituted through extra fields.
test("strict prepared build inputs reject substitutions, source bounds and path injection", () => {
  validateInput(input());
  for (const changes of [{ board: "raspberry_pi_pico" }, { profile: "application" }, { recipe: "other" }, { schema: 2 },
    { filename: "../Sketch.ino" }, { filename: "a\n.ino" }, { filename: "é.ino" }, { filename: "a..ino" },
    { flags: ["-I/private"] }, { apiAddress: 0x10200000 }, { apiAddress: 0x10020001 }, { apiAddress: NaN },
    { translationUnit: "void setup() {}" }, { translationUnit: "\0" }, { translationUnit: "é".repeat(140000) }]) {
    assert.throws(() => validateInput(input(changes)));
  }
});
/// Service arguments contain only fixed target/paths and explicit API address, with no sysroot/library fallback.
test("fixed two-compile/one-link recipe carries exact resident address", () => {
  const jobs = makeJobs(input()); assert.deepEqual(jobs.map(job => job.phase), ["compiling", "compiling", "linking"]);
  const source = new TextDecoder().decode(jobs[0].bytes);
  assert(source.includes("--target=armv6m-none-eabi\n")); assert(source.includes("-DFIRMINGO_API_ADDRESS=268566528\n"));
  assert(!source.includes("--sysroot")); assert(!new TextDecoder().decode(jobs[2].bytes).includes("-lgcc"));
});
/// Writable file descriptors reject sparse growth/allocation/set-size through every mutation route.
test("workspace bounds every descriptor resize and positioned write", () => {
  const workspace = new Workspace("/workspace");
  const handle = open(workspace, "output.o", wasi.OFLAGS_CREAT, BigInt(wasi.RIGHTS_FD_WRITE)).fd_obj;
  assert(handle); assert.equal(handle.fd_write(new Uint8Array([1, 2])).ret, 0);
  assert.equal(handle.fd_allocate(0n, BigInt(limits.fileBytes + 1)), wasi.ERRNO_FBIG);
  assert.equal(handle.fd_filestat_set_size(2n ** 63n), wasi.ERRNO_FBIG);
  assert.equal(handle.fd_pwrite(new Uint8Array([3]), BigInt(limits.fileBytes)).ret, wasi.ERRNO_FBIG);
  handle.fd_seek(2n ** 63n, wasi.WHENCE_SET);
  assert.equal(handle.fd_write(new Uint8Array([4])).ret, wasi.ERRNO_FBIG);
  assert.deepEqual(workspace.read("output.o"), new Uint8Array([1, 2]));
});
/// Compiler-created and directly inserted files share the same aggregate allocation budget.
test("workspace aggregate growth cannot exceed its per-build bound", () => {
  const workspace = new Workspace("/workspace");
  for (let index = 0; index < 4; index++) { workspace.insert(`file${index}`, new Uint8Array(limits.fileBytes)); }
  const handle = open(workspace, "next", wasi.OFLAGS_CREAT, BigInt(wasi.RIGHTS_FD_WRITE)).fd_obj;
  assert(handle); assert.equal(handle.fd_write(new Uint8Array([1])).ret, wasi.ERRNO_FBIG);
});
/// Immutable files remain immutable after child directory opens and direct descriptor mutator calls.
test("readonly capability survives child descriptors and direct resizing", () => {
  const files = new Map([["nested/Arduino.h", new Uint8Array([1, 2, 3])]]);
  const toolchain = new Workspace("/toolchain", files);
  const dir = open(toolchain, "nested", wasi.OFLAGS_DIRECTORY).fd_obj; assert(dir);
  assert.equal(dir.path_create_directory("extra"), wasi.ERRNO_ROFS);
  assert.equal(dir.path_unlink_file("Arduino.h"), wasi.ERRNO_ROFS);
  assert.equal(dir.path_open(0, "Arduino.h", wasi.OFLAGS_TRUNC, 0n, 0n, 0).ret, wasi.ERRNO_ROFS);
  const file = dir.path_open(0, "Arduino.h", 0, 0n, 0n, 0).fd_obj; assert(file);
  assert.equal(file.fd_allocate(0n, 100n), wasi.ERRNO_ROFS);
  assert.equal(file.fd_filestat_set_size(0n), wasi.ERRNO_ROFS);
  assert.equal(file.fd_pwrite(new Uint8Array([4]), 0n).ret, wasi.ERRNO_ROFS);
  assert.deepEqual(toolchain.read("nested/Arduino.h"), new Uint8Array([1, 2, 3]));
});
/// Canonical paths cannot traverse preopens or introduce aliases in writable source/output storage.
test("path traversal and ambiguous aliases fail before resolving an inode", () => {
  const workspace = new Workspace("/workspace");
  for (const path of ["../x", "a/../x", "/x", "a//x", "a/./x", "x\0", "a\\x", ""]) {
    assert.throws(() => workspace.insert(path, new Uint8Array([1])));
    assert.notEqual(open(workspace, path, wasi.OFLAGS_CREAT).ret, 0);
  }
  assert.equal(workspace.path_filestat_get(0, ".").ret, 0);
});
/// Descriptor domains do not permit linking immutable recipe inodes into the mutable workspace.
test("cross-capability links and excessive entry creation are rejected", () => {
  const toolchain = new Workspace("/toolchain", new Map([["header", new Uint8Array([1])]]));
  const workspace = new Workspace("/workspace");
  assert.equal(workspace.path_link("header", toolchain.path_lookup("header", 0).inode_obj, false), wasi.ERRNO_NOTCAPABLE);
  for (let index = 0; index < limits.entries; index++) { assert.equal(open(workspace, "f" + index, wasi.OFLAGS_CREAT).ret, 0); }
  assert.notEqual(open(workspace, "overflow", wasi.OFLAGS_CREAT).ret, 0);
});
/// Workspace instances and retained output copies cannot leak a previous source revision.
test("fresh workspace and owned output prevent stale data reuse", () => {
  const first = new Workspace("/workspace"); first.insert("file", new Uint8Array([1]));
  const copy = first.read("file"); copy[0] = 9; assert.equal(first.read("file")[0], 1);
  const second = new Workspace("/workspace"); assert.throws(() => second.read("file"));
});
/// Exact stderr bytes are bounded rather than silently truncated, including a final unterminated line.
test("output capture retains exact bytes and rejects excessive writes", () => {
  const output = new OutputCapture(); output.fd_write(new Uint8Array([0xff, 0, 65]));
  assert.deepEqual(output.bytes, new Uint8Array([0xff, 0, 65]));
  assert.throws(() => output.fd_write(new Uint8Array(65536)));
});
/// Source-mapped diagnostics retain unmatched linker lines and reject oversized positions/messages.
test("diagnostic parsing retains locations, severity and unmatched failure context", () => {
  const result = parseDiagnostics("Sketch.ino:2:4: error: bad call\nld.lld: error: undefined symbol\n>>> detail");
  assert.deepEqual(result[0], { severity: "error", message: "bad call", filename: "Sketch.ino", line: 2, column: 4 });
  assert.equal(result[1].severity, "error"); assert.equal(result[2].message, ">>> detail");
  assert.throws(() => parseDiagnostics("x:99999999999999999:1: error: bad"));
  assert.throws(() => parseDiagnostics("error: " + "x".repeat(4097)));
  assert.throws(() => parseDiagnostics("note: n\n".repeat(129)));
});
/// An error diagnostic is terminal even when the observed service returns status zero.
test("zero status with frontend error stops before wrapper compilation or linking", () => {
  const memory = new WebAssembly.Memory({ initial: 1 });
  const text = new TextEncoder().encode("/workspace/Sketch.cpp:3:16: error: bad call\n"); new Uint8Array(memory.buffer).set(text, 512);
  let calls = 0; const exports = { memory, malloc: () => 16, free: () => {},
    arduino_compiler_service_compile: () => { calls++; return 0; }, arduino_compiler_service_link: () => { throw new Error("must not link"); },
    arduino_compiler_service_can_run_again: () => 1, arduino_compiler_service_last_diagnostics: () => 512,
    arduino_compiler_service_last_diagnostics_size: () => text.length };
  const service = new ManagedService(exports, new Workspace("/workspace"), new OutputCapture(), new OutputCapture());
  const result = service.run(input()); assert.equal(result.succeeded, false); assert.equal(result.status, 0); assert.equal(calls, 1);
  assert.equal(result.diagnostics[0].filename, "Sketch.ino"); assert.equal(result.diagnostics[0].line, 1);
  assert.throws(() => service.run(input()), /already consumed/);
});
/// A valid digest alone cannot grant compiler capabilities to a wrong module or service ABI.
test("asset digest, size and required exports are independently checked", async () => {
  const bytes = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]);
  await assert.rejects(compileModule(bytes, { bytes: 9, sha256: "1".repeat(64) }));
  await assert.rejects(compileModule(bytes, { bytes: 8, sha256: "1".repeat(64) }), /digest mismatch/);
  await assert.rejects(compileModule(bytes, { bytes: 8, sha256: "93a44bbb96c751218e4c00d479e4c14358122a389acca16205b1e4d0dc5f9476" }), /defined WASM memory/);
});
/// A missing maximum is rejected; the maintenance adaptation preserves all bytes outside the memory section.
test("WASM memory declarations must impose a hard bounded maximum", () => {
  const original = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 0, 1, 0, 3, 1, 65, 0]);
  assert.equal(memoryLimits(original).maximum, null); assert.throws(() => requireBoundedMemory(original));
  const adapted = boundMemory(original); requireBoundedMemory(adapted);
  assert.equal(memoryLimits(adapted).maximum, 4096);
  assert.deepEqual(adapted.slice(memoryLimits(adapted).sectionEnd), original.slice(memoryLimits(original).sectionEnd));
  for (const invalid of [original.slice(0, 12), new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 5, 4, 1, 1, 1, 0]),
    new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 2, 1])]) {
    assert.throws(() => memoryLimits(invalid));
  }
});
/// Worker envelopes reject missing/extra assets and unknown fields before module initialization.
test("worker transfer schema rejects malformed and excessive recipe inputs", () => {
  validateRequest(envelope());
  for (const message of [envelope({ id: 0 }), envelope({ extra: true }), envelope({ recipeAssets: [] }),
    envelope({ recipeAssets: [envelope().recipeAssets[0], envelope().recipeAssets[0], envelope().recipeAssets[2]] })]) {
    assert.throws(() => validateRequest(message));
  }
});

/// Correct export names and bounded memory cannot substitute a different service ABI version.
test("runtime refuses a structurally complete synthetic module reporting the wrong ABI", async () => {
  const names = ["_initialize", "malloc", "free", "arduino_compiler_service_abi_version", "arduino_compiler_service_compile",
    "arduino_compiler_service_link", "arduino_compiler_service_last_diagnostics", "arduino_compiler_service_last_diagnostics_size",
    "arduino_compiler_service_can_run_again"];
  // Independently hand-encoded WASM: one () -> i32 function returns one, exported under all names.
  const exports = [10, 6, ...new TextEncoder().encode("memory"), 2, 0];
  for (const name of names) { const bytes = new TextEncoder().encode(name); exports.push(bytes.length, ...bytes, 0, 0); }
  const length = exports.length;
  const leb = length < 128 ? [length] : [(length % 128) | 128, Math.floor(length / 128)];
  const bytes = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 0x60, 0, 1, 0x7f,
    3, 2, 1, 0, 5, 4, 1, 1, 1, 2, 7, ...leb, ...exports, 10, 6, 1, 4, 0, 0x41, 1, 0x0b]);
  const module = await WebAssembly.compile(bytes);
  const files = new Map(["Arduino.h", "Entry.cpp", "Module.ld"].map(name => [name, new Uint8Array([1])]));
  await assert.rejects(ManagedService.create(module, files), /service ABI mismatch/);
});

/** Portable opaque-origin worker hashing matches independent FIPS vectors and Node digests at padding boundaries. */
test("portable SHA-256 matches independent vectors and block boundaries", async () => {
  const { portableSHA256 } = await import("../Sources/Digest.js");
  const { createHash } = await import("node:crypto");
  for (const length of [0, 3, 55, 56, 63, 64, 65, 127, 128, 1024]) {
    const bytes = new Uint8Array(length).map((_,index) => index % 251);
    assert.equal(Buffer.from(portableSHA256(bytes)).toString("hex"), createHash("sha256").update(bytes).digest("hex"));
  }
  assert.equal(Buffer.from(portableSHA256(new TextEncoder().encode("abc"))).toString("hex"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});
