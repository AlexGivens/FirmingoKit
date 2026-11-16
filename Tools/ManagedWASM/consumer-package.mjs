import { openSync, closeSync, fstatSync, readSync, writeSync, constants, lstatSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { createHash } from "node:crypto";

// SDK maintenance capability: only this deliberately reviewed complete package may be staged.
export const HISTORICAL_CONSUMER_SHA256 = "1bbc0cc19d80490914799fbec5cb4bbc0a942a73fd3bbf6e09fff2c3856e660a";
export const CONSUMER_SHA256 = "d02bb505fb41cc54620aa7dec42bf1914f8eced06cacfc58583a0dece4fbc3e0";
const MAXIMUM = 400 * 1024 * 1024;
const hash = bytes => createHash("sha256").update(bytes).digest("hex");

/** Stream bounded ordinary files without following links or blocking on special files; optionally copy exclusively. */
export function fileRecord(path, maximum = MAXIMUM, output) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW); let target;
  try {
    const before = fstatSync(fd);
    if (!before.isFile() || before.size < 1 || before.size > maximum) throw new Error("Invalid consumer package file");
    if (output) target = openSync(output, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o644);
    const digest = createHash("sha256"), buffer = Buffer.alloc(1024 * 1024); let bytes = 0;
    for (;;) {
      const count = readSync(fd, buffer, 0, buffer.length, null); if (!count) break;
      bytes += count; if (bytes > before.size) throw new Error("Consumer package file grew");
      digest.update(buffer.subarray(0, count));
      if (target !== undefined) { let written = 0; while (written < count) written += writeSync(target, buffer, written, count - written); }
    }
    const after = fstatSync(fd);
    if (bytes !== before.size || before.size !== after.size || before.mtimeMs !== after.mtimeMs) throw new Error("Consumer package changed during read");
    return { bytes, sha256: digest.digest("hex") };
  } finally { if (target !== undefined) closeSync(target); closeSync(fd); }
}

/** Independently anchored full transport verification; SDK never rebuilds LLVM or invents firmware facts. */
export function verifyConsumerPackage(input, expected) {
  const root = resolve(input);
  if (!lstatSync(root).isDirectory() || lstatSync(root).isSymbolicLink()) throw new Error("Unsafe consumer package directory");
  if (![CONSUMER_SHA256, HISTORICAL_CONSUMER_SHA256].includes(expected) || fileRecord(join(root, "manifest.json"), 65536).sha256 !== expected) throw new Error("Consumer package anchor mismatch");
  const bytes = readFileSync(join(root, "manifest.json"));
  if (hash(bytes) !== expected) throw new Error("Consumer manifest changed before parsing");
  const manifest = JSON.parse(bytes);
  const candidate = expected === CONSUMER_SHA256;
  if (manifest.schema !== 1 || manifest.package !== "firmingo-compiler-consumer" || manifest.version !== (candidate ? "1.0.0-rc.1-nano-fms2" : "0.1.0-nano-managed-experimental.2")
      || manifest.qualification !== "experimental-unqualified" || manifest.files.length !== (candidate ? 73 : 33)
      || manifest.review.firmwareBuildID !== (candidate ? "33a0e866c2873b20aaf9303dc10c7af4d6920e99bb1ba2eee6b0c009034523b5" : "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f")) throw new Error("Incompatible reviewed consumer package");
  const expectedPaths = new Set(["manifest.json"]); let total = 0;
  for (const file of manifest.files) {
    if (!/^(?:[a-zA-Z0-9_.-]+\/){0,4}[a-zA-Z0-9_.-]+$/.test(file.path) || file.path.split("/").some(part => part === "." || part === "..")
        || expectedPaths.has(file.path) || !Number.isSafeInteger(file.bytes) || file.bytes < 1 || file.bytes > MAXIMUM) throw new Error("Unsafe consumer role");
    expectedPaths.add(file.path); total += file.bytes;
    if (total > MAXIMUM) throw new Error("Excessive consumer package");
  }
  const found = new Set();
  const walk = (directory, prefix = "", depth = 0) => {
    const entries = readdirSync(directory);
    if (!entries.length || entries.length > 64 || depth > 4) throw new Error("Unsafe consumer directory");
    for (const name of entries) {
      const relative = prefix + name, path = join(directory, name), facts = lstatSync(path);
      if (facts.isSymbolicLink()) throw new Error("Symlinked consumer role");
      if (facts.isDirectory()) { walk(path, relative + "/", depth + 1); continue; }
      if (!facts.isFile() || (relative !== "operation.json" && !expectedPaths.has(relative))) throw new Error("Unlisted consumer file");
      found.add(relative);
    }
  };
  walk(root);
  for (const path of expectedPaths) if (!found.has(path)) throw new Error("Missing consumer package role");
  for (const file of manifest.files) {
    const actual = fileRecord(join(root, file.path), file.bytes);
    if (actual.bytes !== file.bytes || actual.sha256 !== file.sha256) throw new Error("Consumer package integrity mismatch: " + file.path);
  }
  if (fileRecord(join(root, "manifest.json"), 65536).sha256 !== expected) throw new Error("Consumer manifest changed during verification");
  return { root, manifest, bytes };
}
