import { readFileSync, readSync, writeFileSync, lstatSync, openSync, closeSync, fstatSync, constants } from "node:fs";
import { resolve, join } from "node:path";
import { createHash } from "node:crypto";
import { Script } from "node:vm";

// Explicit maintenance import; normal SDK builds use only committed resources and compiled-in anchors.
const [directory, expectedSHA256] = process.argv.slice(2);
if (!directory || !/^[0-9a-f]{64}$/.test(expectedSHA256 || "") || process.argv.length !== 4) throw new Error("Select an explicit compiler export directory and trusted manifest SHA-256");
const hash = bytes => createHash("sha256").update(bytes).digest("hex");
const root = resolve(directory);
if (lstatSync(root).isSymbolicLink() || !lstatSync(root).isDirectory()) throw new Error("Select a real export directory");
const readBounded = (name, maximum) => {
  const path = join(root, name);
  if (lstatSync(path).isSymbolicLink()) throw new Error("Symlinked compiler export");
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size < 1 || stat.size > maximum) throw new Error("Excessive compiler export resource");
    const bytes = Buffer.alloc(stat.size);
    let offset = 0;
    while (offset < bytes.length) {
      const count = readSync(fd, bytes, offset, bytes.length - offset, offset);
      if (!count) throw new Error("Compiler export changed while reading");
      offset += count;
    }
    if (fstatSync(fd).size !== stat.size) throw new Error("Compiler export changed while reading");
    return bytes;
  } finally { closeSync(fd); }
};
const manifestData = readBounded("manifest.json", 16384);
if (manifestData.length > 16384 || hash(manifestData) !== expectedSHA256) throw new Error("Compiler export manifest mismatch");
const manifest = JSON.parse(manifestData);
const roles = ["compiler.js", "worker.js", "preparation-worker.js", "resources.json", "LICENSE-MIT", "LICENSE-APACHE", "Firmingo-Compiler-LICENSE", "sources.json"];
if (manifest.schema !== 1 || manifest.package !== "firmingo-compiler" || manifest.interfaceVersion !== 1 || manifest.serviceABI !== 2 || manifest.version !== "0.0.0-development"
    || manifest.files.length !== roles.length || manifest.files.map(item => item.path).sort().join() !== roles.sort().join()) throw new Error("Incompatible compiler export");
const files = {};
for (const item of manifest.files) {
  if (!roles.includes(item.path) || !Number.isSafeInteger(item.bytes) || item.bytes < 1 || item.bytes > 524288) throw new Error("Invalid compiler export resource");
  const bytes = readBounded(item.path, item.bytes);
  if (bytes.length !== item.bytes || hash(bytes) !== item.sha256) throw new Error("Compiler export resource mismatch");
  files[item.path] = bytes;
}
const bridge = readFileSync("Tools/ManagedWASM/PortableHostBridge.js", "utf8");
const script = `${files["compiler.js"].toString("utf8")}\nconst workerSource=${JSON.stringify(files["worker.js"].toString("utf8"))};\nconst preparationWorkerSource=${JSON.stringify(files["preparation-worker.js"].toString("utf8"))};\nconst recipeResources=${files["resources.json"].toString("utf8")};\n${bridge}`;
new Script(script);
const html = Buffer.from(`<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'wasm-unsafe-eval'; worker-src blob:; connect-src firmingo-compiler:;"><script>${script.replace(/<\/script/gi,"<\\/script")}</script>`);
if (html.length > 524288) throw new Error("Excessive native host page");
const destination = "Sources/FirmingoKit/Resources/ManagedCompiler";
const output = { "host.html": html, "LICENSE-MIT": files["LICENSE-MIT"], "LICENSE-APACHE": files["LICENSE-APACHE"],
  "Firmingo-Compiler-LICENSE": files["Firmingo-Compiler-LICENSE"], "compiler-package.json": manifestData, "compiler-sources.json": files["sources.json"] };
for (const [name, bytes] of Object.entries(output)) writeFileSync(join(destination, name), bytes);
const runtime = { schema: 1, recipe: "nano-stateless-clang-22.1.8-v1-experimental", serviceABI: 2, recipeSHA256: manifest.recipeSHA256,
  compilerPackageSHA256: expectedSHA256, files: Object.entries(output).map(([path, bytes]) => ({ path, bytes: bytes.length, sha256: hash(bytes) })) };
const data = Buffer.from(JSON.stringify(runtime, null, 2) + "\n"); writeFileSync(join(destination, "manifest.json"), data);
console.log(JSON.stringify({ status: "staged_compiler_source_package_and_sdk_bridge", manifestSHA256: hash(data), compilerPackageSHA256: expectedSHA256, pageBytes: html.length }));
