#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { compileModule, ManagedService } from "./Sources/ManagedService.js";
import { contract } from "./Sources/ManagedRecipe.js";
import { loadRecipeAssets } from "./DevelopmentAssets.mjs";

/** Explicit local-only development invocation; all outputs must live under SDK .build. */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const modulePath = resolve(root, ".build/managed-wasm/compiler-bounded.wasm");
const output = resolve(root, ".build/managed-wasm/results");
mkdirSync(output, { recursive: true });
/** Fixed development inputs include two distinct useful sketches and negative stateless/diagnostic cases. */
const cases = [
  ["Blink.ino", "void setup() { pinMode(LED_BUILTIN, OUTPUT); }\nvoid loop() { digitalWrite(LED_BUILTIN, HIGH); delay(100); digitalWrite(LED_BUILTIN, LOW); delay(100); }", true],
  ["Console.ino", "void setup() { Serial.begin(115200); Serial.println(\"ready\"); }\nvoid loop() { const int value = Serial.read(); if(value >= 0) Serial.write(uint8_t(value)); }", true],
  ["Syntax.ino", "void setup() { missingFunction(); }\nvoid loop() {}", false],
  ["Globals.ino", "volatile unsigned value;\nvoid setup() { value = 1; }\nvoid loop() { ++value; }", false],
  ["Constructors.ino", "struct X { X(); }; X::X() { pinMode(6, 1); } X object;\nvoid setup() {} void loop() {}", false],
  ["Division.ino", "void setup() {}\nvoid loop() { digitalWrite(6, millis() / 250); }", false],
];
/** Verifies the development service and materializes independently authored recipe resources. */
const identity = { bytes: 101196044, sha256: "3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33" };
const start = performance.now();
const module = await compileModule(new Uint8Array(readFileSync(modulePath)), identity);
const compilationMilliseconds = performance.now() - start;
const files = new Map(loadRecipeAssets().map(asset => [asset.name, asset.bytes]));
const observations = [];
for (const [filename, source, expected] of cases) {
  const instanceStart = performance.now(); const service = await ManagedService.create(module, files);
  const initializationMilliseconds = performance.now() - instanceStart;
  const input = { schema: 1, recipe: contract.recipe, board: contract.board, profile: contract.profile,
    filename, apiAddress: 0x10022ca0, translationUnit: `#include <Arduino.h>\n#line 1 "${filename}"\n${source}\n` };
  const stages = []; const result = service.run(input, stage => stages.push(stage));
  if (result.succeeded !== expected) { throw new Error(`Unexpected ${filename} outcome: ${JSON.stringify(result.diagnostics)}`); }
  if (result.succeeded) { writeFileSync(resolve(output, filename + ".elf"), result.elf); }
  writeFileSync(resolve(output, filename), source + "\n");
  const { elf, ...metadata } = result;
  const observation = { filename, expected, stages, initializationMilliseconds, ...metadata,
    sourceSHA256: createHash("sha256").update(source + "\n").digest("hex"),
    ...(elf ? { elfBytes: elf.length, elfSHA256: createHash("sha256").update(elf).digest("hex") } : {}) };
  observations.push(observation);
  console.log(JSON.stringify(observation));
}
writeFileSync(resolve(output, "receipt.json"), JSON.stringify({ status: "Development Node/WASI compile-link only; no WebKit, installed-resident or hardware qualification",
  contract, identity, compilationMilliseconds, observations }, null, 2) + "\n");
