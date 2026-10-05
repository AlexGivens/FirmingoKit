#!/usr/bin/env node
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { loadRecipeAssets } from "./DevelopmentAssets.mjs";
/** Records the exact bounded service, recipe, runner/worker sources and licensed shim used by development checks. */
const directory = dirname(fileURLToPath(import.meta.url)); const root = resolve(directory, "../..");
loadRecipeAssets();
const module = readFileSync(resolve(root, ".build/managed-wasm/compiler-bounded.wasm"));
const sha256 = bytes => createHash("sha256").update(bytes).digest("hex");
if (module.length !== 101196044 || sha256(module) !== "3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33") {
  throw new Error("Require the exact derived development module");
}
const paths = ["Recipe/manifest.json", "Vendor/browser_wasi_shim/receipt.json", "NodeWorker.mjs", "NodeController.mjs",
  "run-validation.mjs", "DevelopmentAssets.mjs", ...readdirSync(resolve(directory, "Sources")).filter(name => name.endsWith(".js")).sort().map(name => "Sources/" + name)];
const assets = paths.map(path => { const data = readFileSync(resolve(directory, path)); return { path, bytes: data.length, sha256: sha256(data) }; });
const manifest = { schema: 1, status: "Development only; redistribution/license review and WebKit/physical-host qualification pending",
  serviceABI: 2, compiler: "Clang/LLD 22.1.8 ABI-two WASI service", compilerBytes: module.length, compilerSHA256: sha256(module),
  maximumLinearMemoryBytes: 268435456, compilerMaintenanceReceipt: JSON.parse(readFileSync(resolve(root, ".build/managed-wasm/memory-receipt.json"))), assets };
writeFileSync(resolve(root, ".build/managed-wasm/toolchain-manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
