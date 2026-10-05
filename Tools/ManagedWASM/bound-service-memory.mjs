#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { boundMemory, memoryLimits } from "./Sources/ModuleMemory.js";
/** Fixed SDK-local maintenance transformation; never rewrites a reference or the original copied module. */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const source = new Uint8Array(readFileSync(resolve(root, ".build/managed-wasm/compiler.wasm")));
const sourceSHA256 = createHash("sha256").update(source).digest("hex");
if (source.length !== 101196042 || sourceSHA256 !== "bce6632512852bf86baf7ca7b6eddd07209c0c4e29ae3b2288ec27e69028887d") {
  throw new Error("Require the exact pinned development service input");
}
const bounded = boundMemory(source); const sha256 = createHash("sha256").update(bounded).digest("hex");
writeFileSync(resolve(root, ".build/managed-wasm/compiler-bounded.wasm"), bounded);
writeFileSync(resolve(root, ".build/managed-wasm/memory-receipt.json"), JSON.stringify({ sourceSHA256, sourceBytes: source.length,
  derivedSHA256: sha256, derivedBytes: bounded.length, sourceMemory: memoryLimits(source), derivedMemory: memoryLimits(bounded),
  adaptation: "Only defined-memory limits/section length changed; hard 4096-page maximum. No compiler instructions/data changed. Redistribution pending." }, null, 2) + "\n");
console.log(JSON.stringify({ bytes: bounded.length, sha256, maximumMemoryBytes: 4096 * 65536 }));
