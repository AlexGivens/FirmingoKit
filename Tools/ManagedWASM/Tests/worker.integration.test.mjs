import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { compileInWorker } from "../NodeController.mjs";
import { contract } from "../Sources/ManagedRecipe.js";

/** Explicit opt-in service path; ordinary tests do not require compiler assets or sibling checkouts. */
const modulePath = process.env.FIRMINGOKIT_WASM_MODULE;
const skip = modulePath ? false : "Set FIRMINGOKIT_WASM_MODULE to an SDK-local verified development service";
/** Owns the immutable development bytes, whose exact hash is checked inside every worker. */
const moduleBytes = modulePath ? new Uint8Array(readFileSync(resolve(modulePath))) : null;
/** Loads only independently authored recipe files, validated against their committed maintenance manifest. */
const manifest = JSON.parse(readFileSync(new URL("../Recipe/manifest.json", import.meta.url), "utf8"));
const recipeAssets = ["Arduino.h", "Entry.cpp", "Module.ld"].map(name => {
  const bytes = new Uint8Array(readFileSync(new URL("../Recipe/" + name, import.meta.url)));
  const asset = manifest.assets.find(item => item.path === "Recipe/" + name);
  assert(asset); assert.equal(bytes.length, asset.bytes); assert.equal(createHash("sha256").update(bytes).digest("hex"), asset.sha256);
  return { name, bytes, sha256: asset.sha256 };
});
/** Builds one uniquely correlated immutable test job with explicitly synthetic resident metadata. */
function request(id, filename, source) {
  return { id, moduleBytes, identity: { bytes: 101196044, sha256: "3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33" }, recipeAssets,
    input: { schema: 1, recipe: contract.recipe, board: contract.board, profile: contract.profile,
      filename, apiAddress: 0x10022ca0, translationUnit: `#include <Arduino.h>\n#line 1 "${filename}"\n${source}\n` } };
}

/// The real worker compiles/links two revisions and retains no artifact from the first in the second.
test("actual isolated WASM worker compiles two different stateless sketches", { skip }, async () => {
  const stages = [];
  const first = await compileInWorker(request(1, "A.ino", "void setup() { pinMode(6, 1); } void loop() { digitalWrite(6, 1); delay(10); }"), { progress: stage => stages.push(stage) });
  const second = await compileInWorker(request(2, "B.ino", 'void setup() { Serial.println("ready"); } void loop() { const int c = Serial.read(); if (c >= 0) Serial.write(uint8_t(c)); }'));
  assert(first.succeeded); assert(second.succeeded); assert.deepEqual(stages, ["verifying", "compiling", "compiling", "linking"]);
  assert.notDeepEqual(first.elf, second.elf); assert.equal(first.elf[0], 0x7f);
});
/// Frontend diagnostics are terminal even when ABI-two reports zero status; source locations map once.
test("actual frontend error does not proceed to entry compile or link", { skip }, async () => {
  const stages = [];
  const result = await compileInWorker(request(3, "Bad.ino", "void setup() { missingFunction(); } void loop() {}"), { progress: phase => stages.push(phase) });
  assert.equal(result.succeeded, false); assert.equal(result.elf, undefined);
  assert.deepEqual(stages, ["verifying", "compiling"]);
  const diagnostic = result.diagnostics.find(item => item.severity === "error"); assert(diagnostic);
  assert.equal(diagnostic.filename, "Bad.ino"); assert.equal(diagnostic.line, 1); assert.equal(diagnostic.column, 16);
});
/// Statelesness and missing runtime-helper errors expose explicit failures instead of a library fallback.
test("actual linker rejects globals, constructors and division helper dependencies", { skip }, async () => {
  const cases = [
    ["volatile int x; void setup() { x = 1; } void loop() { ++x; }", "mutable storage"],
    ["struct X { X(); }; X::X() { pinMode(6, 1); } X object; void setup() {} void loop() {}", "runtime constructors"],
    ["void setup() {} void loop() { digitalWrite(6, millis() / 250); }", "__aeabi_uidiv"],
  ];
  for (const [source, expected] of cases) {
    const result = await compileInWorker(request(4, "Unsupported.ino", source));
    assert.equal(result.succeeded, false); assert.equal(result.elf, undefined);
    assert(result.diagnostics.some(item => item.severity === "error" && item.message.includes(expected)));
  }
});
/// Aborting on a real compile-phase notification terminates synchronous WASM before resolving the caller.
test("actual compiler worker cancellation permits a fresh subsequent build", { skip }, async () => {
  const controller = new AbortController();
  await assert.rejects(compileInWorker(request(5, "Cancel.ino", "void setup() {} void loop() {}"), {
    signal: controller.signal, progress: phase => { if (phase === "compiling") { controller.abort(); } },
  }), { name: "AbortError" });
  const result = await compileInWorker(request(6, "Fresh.ino", "void setup() {} void loop() {}"));
  assert(result.succeeded);
});
/// A worker deadline disposes initialization work and cannot later return its linked artifact.
test("actual worker timeout leaves the next build independent", { skip }, async () => {
  await assert.rejects(compileInWorker(request(7, "Timeout.ino", "void setup() {} void loop() {}"), { timeoutMilliseconds: 1 }), /deadline exceeded/);
  const result = await compileInWorker(request(8, "After.ino", "void setup() {} void loop() {}")); assert(result.succeeded);
});
