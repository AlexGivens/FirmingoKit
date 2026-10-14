import { createHash } from "node:crypto";
import { openSync, closeSync, readSync, fstatSync, lstatSync, writeFileSync, constants } from "node:fs";
import { join, resolve } from "node:path";

// Explicit import of reviewed documentation only. Never copy a WASM binary or source archive into SwiftPM.
const [directory, expected] = process.argv.slice(2);
if (!directory || !/^[0-9a-f]{64}$/.test(expected || "") || process.argv.length !== 4) throw new Error("Select paired delivery and independent manifest SHA-256");
const root = resolve(directory), destination = "Sources/FirmingoKit/Resources/ManagedCompiler";
if (!lstatSync(root).isDirectory() || lstatSync(root).isSymbolicLink()) throw new Error("Unsafe delivery directory");
const hash = bytes => createHash("sha256").update(bytes).digest("hex");
const readSmall = (path, maximum) => {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size < 1 || stat.size > maximum) throw new Error("Invalid bounded delivery document");
    const bytes = Buffer.alloc(maximum + 1); let length = 0;
    while (length < bytes.length) {
      const count = readSync(fd, bytes, length, bytes.length - length, null); if (!count) break; length += count;
    }
    if (length !== stat.size) throw new Error("Delivery document changed during read");
    return bytes.subarray(0, length);
  } finally { closeSync(fd); }
};
const data = readSmall(join(root, "manifest.json"), 16384);
if (hash(data) !== expected) throw new Error("Delivery manifest anchor mismatch");
const manifest = JSON.parse(data);
const roles = new Set(["compiler.wasm", "compiler-source.tar.gz", "LICENSE", "LICENSES.txt", "FILE-NOTICES.txt", "source-notices.json", "delivery-review.json", "README.md", "BUILDING.md"]);
if (manifest.schema !== 1 || manifest.version !== "llvm-22.1.8-wasip1-abi2-r1" || manifest.distributionStatus !== "reviewed-paired-delivery"
    || manifest.completeCorrespondingSource !== true || manifest.serviceABI !== 2 || manifest.files.length !== roles.size
    || manifest.reviewSHA256 !== "2627a80ee5845929f030cfec6253f05e3cfc4f8c98bff69a0117b3d78114cb26") throw new Error("Unsupported paired review");
const documents = {};
const records = new Map();
for (const record of manifest.files) {
  if (!roles.delete(record.path) || !Number.isSafeInteger(record.bytes) || record.bytes < 1 || record.bytes > 400 * 1024 * 1024) throw new Error("Unsafe delivery role");
  records.set(record.path, record);
  const path = join(root, record.path);
  if (lstatSync(path).isSymbolicLink()) throw new Error("Symlinked delivery role");
  const fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size !== record.bytes) throw new Error("Invalid delivery file");
    const digest = createHash("sha256"), chunk = Buffer.alloc(1024 * 1024); let length = 0;
    while (true) {
      const count = readSync(fd, chunk, 0, chunk.length, null); if (!count) break;
      length += count; if (length > record.bytes) throw new Error("Delivery file grew"); digest.update(chunk.subarray(0, count));
    }
    if (length !== record.bytes || digest.digest("hex") !== record.sha256) throw new Error("Delivery byte mismatch");
    if (["delivery-review.json", "source-notices.json", "LICENSES.txt", "FILE-NOTICES.txt"].includes(record.path)) {
      const bytes = readSmall(path, record.bytes); if (bytes.length !== record.bytes || hash(bytes) !== record.sha256) throw new Error("Delivery changed before import");
      documents[record.path] = bytes;
    }
  } finally { closeSync(fd); }
}
const review = JSON.parse(documents["delivery-review.json"]);
if (hash(documents["delivery-review.json"]) !== manifest.reviewSHA256
    || review.service.sha256 !== "a7648688ae9e349304c576804367b66b68b22185060a847a2e292675329ca493"
    || review.service.bytes !== 101194565 || review.source.sha256 !== "dcdbe2d1fc2135dc726f06aa7b4fa4be9d81ac61f5fba2969d464f21b86089ef") throw new Error("Unexpected reviewed service/source pair");
for (const [name, pin] of [["compiler.wasm", review.service], ["compiler-source.tar.gz", review.source]]) {
  const record = records.get(name);
  if (record.bytes !== pin.bytes || record.sha256 !== pin.sha256) throw new Error("Delivery payload differs from reviewed pair");
}
if (hash(documents["source-notices.json"]) !== review.noticeManifest.sha256) throw new Error("Wrong source-notice inventory");
for (const pin of JSON.parse(documents["source-notices.json"]).files) {
  if (["LICENSES.txt", "FILE-NOTICES.txt"].includes(pin.path) && (documents[pin.path].length !== pin.bytes || hash(documents[pin.path]) !== pin.sha256)) throw new Error("Wrong source-notice text");
}
for (const [source, name] of [["delivery-review.json", "service-review.json"], ["source-notices.json", "service-source-notices.json"],
  ["LICENSES.txt", "service-LICENSES.txt"], ["FILE-NOTICES.txt", "service-FILE-NOTICES.txt"]]) writeFileSync(join(destination, name), documents[source]);
console.log(JSON.stringify({ status: "staged_reviewed_service_documentation", reviewSHA256: hash(documents["delivery-review.json"]), files: 4, binaryCopied: false, sourceArchiveCopied: false }));
