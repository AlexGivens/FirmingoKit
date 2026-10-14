import { mkdirSync, rmSync, readFileSync, writeFileSync, lstatSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { verifyConsumerPackage, fileRecord } from "./consumer-package.mjs";

// Creates a clean self-contained SDK source package outside Git; no downloader, device operation or publication.
const [directory, expected, destination] = process.argv.slice(2);
if (!directory || !expected || !destination || process.argv.length !== 5) throw new Error("Use prepare-sdk-package.mjs PACKAGE TRUSTED_MANIFEST_SHA256 NEW_OUTPUT");
const sdk = fileURLToPath(new URL("../../", import.meta.url));
const git = args => {
  const result = spawnSync("git", ["--no-optional-locks", "-C", sdk, ...args], { encoding: "utf8", timeout: 15000 });
  if (result.error || result.status !== 0) throw new Error("Select a clean committed SDK source snapshot");
  return result.stdout;
};
git(["diff", "--exit-code", "HEAD", "--"]);
const commit = git(["rev-parse", "HEAD"]).trim();
const paths = git(["ls-files", "-z"]).split("\0").filter(Boolean);
if (paths.length > 1024) throw new Error("Excessive SDK source package");
const { root, manifest, bytes } = verifyConsumerPackage(directory, expected);
const resource = "Sources/FirmingoKit/Resources/ManagedCompiler";
if (!readFileSync(join(sdk, resource, "consumer-package.json")).equals(bytes)) throw new Error("SDK must first deliberately stage this consumer package");
const output = resolve(destination); mkdirSync(output);
try {
  const records = [];
  for (const path of paths) {
    if (path.split("/").some(part => !part || part === "." || part === ".." || part === ".git")) throw new Error("Unsafe SDK source path");
    const source = join(sdk, path);
    if (lstatSync(source).isSymbolicLink()) throw new Error("Symlinked SDK source");
    const target = join(output, path); mkdirSync(dirname(target), { recursive: true });
    records.push({ path, ...fileRecord(source, 2 * 1024 * 1024, target) });
  }
  const service = manifest.files.find(file => file.path === "service/compiler.wasm");
  const copied = fileRecord(join(root, service.path), service.bytes, join(output, resource, "compiler.wasm"));
  if (copied.sha256 !== service.sha256 || copied.bytes !== service.bytes) throw new Error("Prepared service differs from reviewed package");
  records.push({ path: resource + "/compiler.wasm", ...copied });
  // Carry the complete paired service/source/notice delivery with this SDK distribution, outside app resources.
  for (const file of manifest.files.filter(file => file.path.startsWith("service/"))) {
    const path = "CompilerDelivery/" + file.path.slice(8), target = join(output, path);
    mkdirSync(dirname(target), { recursive: true });
    const copied = fileRecord(join(root, file.path), file.bytes, target);
    if (copied.sha256 !== file.sha256 || copied.bytes !== file.bytes) throw new Error("Paired SDK delivery changed");
    records.push({ path, ...copied });
  }
  for (const file of records) {
    const actual = fileRecord(join(output, file.path), file.bytes);
    if (actual.bytes !== file.bytes || actual.sha256 !== file.sha256) throw new Error("Prepared SDK content changed");
  }
  git(["diff", "--exit-code", "HEAD", "--"]);
  if (git(["rev-parse", "HEAD"]).trim() !== commit) throw new Error("SDK source commit changed during preparation");
  const record = { schema: 1, operation: "prepared_experimental_sdk_package", sdkCommit: commit, consumerManifestSHA256: expected,
    firmwareBuildID: manifest.review.firmwareBuildID, qualification: "experimental-unqualified", published: false, files: records };
  const data = Buffer.from(JSON.stringify(record, null, 2) + "\n");
  writeFileSync(join(output, "prepared-package.json"), data, { flag: "wx" });
  console.log(JSON.stringify({ status: record.operation, sdkCommit: commit, files: records.length,
    manifestSHA256: createHash("sha256").update(data).digest("hex"), binaryBundled: true, published: false }));
} catch (error) { rmSync(output, { recursive: true }); throw error; }
