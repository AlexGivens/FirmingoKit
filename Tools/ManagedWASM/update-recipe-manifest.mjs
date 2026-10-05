#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { contract } from "./Sources/ManagedRecipe.js";
/** Records exact independent recipe sources/flags for maintenance, without reading a sibling checkout. */
const names = ["Recipe/Arduino.h", "Recipe/Entry.cpp", "Recipe/Module.ld", "Sources/ManagedRecipe.js"];
const assets = names.map(path => {
  const bytes = readFileSync(new URL(path, import.meta.url));
  return { path, bytes: bytes.length, sha256: createHash("sha256").update(bytes).digest("hex") };
});
/** Versioned development contract deliberately excludes compiler/sysroot redistribution or qualification. */
const manifest = { ...contract, status: "Experimental development recipe; no hardware qualification",
  cpu: "cortex-m0plus", abi: "AAPCS base/soft float, 32-bit pointers, stateless resident ABI one",
  maximumCodeBytes: 3840, libraries: [], sysroot: null,
  restrictions: ["Single SDK-prepared .ino", "No mutable storage or runtime initialization", "No external libraries or compiler runtime helpers", "Setup/loop must return"], assets };
writeFileSync(new URL("Recipe/manifest.json", import.meta.url), JSON.stringify(manifest, null, 2) + "\n");
