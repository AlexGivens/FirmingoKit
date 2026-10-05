import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { contract } from "./Sources/ManagedRecipe.js";

/** Verifies each exact recipe source/argument file against the local maintenance manifest before compilation. */
export function loadRecipeAssets() {
  verifyVendoredAssets();
  const manifest = JSON.parse(readFileSync(new URL("./Recipe/manifest.json", import.meta.url), "utf8"));
  if (manifest.schema !== contract.schema || manifest.serviceABI !== contract.serviceABI || manifest.recipe !== contract.recipe
      || manifest.board !== contract.board || manifest.profile !== contract.profile || manifest.target !== contract.target
      || !Array.isArray(manifest.assets) || manifest.assets.length !== 4) { throw new Error("Incompatible managed recipe manifest"); }
  const expected = ["Recipe/Arduino.h", "Recipe/Entry.cpp", "Recipe/Module.ld", "Sources/ManagedRecipe.js"];
  const assets = [];
  for (const path of expected) {
    const records = manifest.assets.filter(item => item.path === path);
    if (records.length !== 1) { throw new Error("Missing or duplicate managed recipe role"); }
    const record = records[0]; const bytes = new Uint8Array(readFileSync(new URL(path, import.meta.url)));
    if (record.bytes !== bytes.length || record.sha256 !== createHash("sha256").update(bytes).digest("hex")) {
      throw new Error("Managed recipe resource integrity mismatch");
    }
    if (path.startsWith("Recipe/")) { assets.push({ name: path.slice(7), bytes, sha256: record.sha256 }); }
  }
  return assets;
}

/** Checks the unchanged third-party version/license/source bytes against the retained local package receipt. */
export function verifyVendoredAssets() {
  const base = new URL("./Vendor/browser_wasi_shim/", import.meta.url);
  const receipt = JSON.parse(readFileSync(new URL("receipt.json", base), "utf8"));
  if (receipt.package !== "@bjorn3/browser_wasi_shim" || receipt.version !== "0.4.2" || !Array.isArray(receipt.files)) {
    throw new Error("Incompatible WASI shim receipt");
  }
  const seen = new Set();
  for (const record of receipt.files) {
    if (typeof record.path !== "string" || !/^(dist\/[A-Za-z0-9_]+\.js|package\.json|LICENSE-MIT|LICENSE-APACHE)$/.test(record.path)
        || seen.has(record.path)) { throw new Error("Unsafe or duplicate WASI shim resource"); }
    seen.add(record.path);
    const bytes = readFileSync(new URL(record.path, base));
    if (record.bytes !== bytes.length || record.sha256 !== createHash("sha256").update(bytes).digest("hex")) {
      throw new Error("WASI shim integrity mismatch");
    }
  }
  if (!seen.has("LICENSE-MIT") || !seen.has("LICENSE-APACHE") || !seen.has("dist/index.js")) {
    throw new Error("Missing WASI license/runtime resources");
  }
}
