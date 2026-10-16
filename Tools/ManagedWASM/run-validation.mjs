#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = fileURLToPath(new URL("../../", import.meta.url));

/** SDK checks only; compiler maintenance and portable/Node builds belong to Firmingo-Compiler. */
function run(command, args, env = process.env) {
  const result = spawnSync(command, args, { cwd: root, env, stdio: "inherit", timeout: 180000 });
  if (result.error || result.signal || result.status !== 0)
    throw new Error(result.error?.message || `${command} failed (${result.signal || result.status})`);
}

/** Do not silently omit a newly introduced XCTest suite while selecting this package's sole test framework. */
function requireSwiftTesting(directory) {
  for (const item of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, item.name);
    if (item.isDirectory()) requireSwiftTesting(path);
    else if (item.name.endsWith('.swift') && /\bimport\s+XCTest\b|\bXCTestCase\b/.test(readFileSync(path, 'utf8')))
      throw new Error('XCTest source added: review the explicit Swift Testing runner selection before continuing');
  }
}

const args = process.argv.slice(2);
if (args.length === 1 && args[0] === "--help") {
  console.log("Usage: node Tools/ManagedWASM/run-validation.mjs [explicit-pinned-service.wasm]\n"
    + "Checks SDK fixtures, packaged resources, Swift adapters and deployment boundaries.\n"
    + "Actual WebKit compilation is explicitly skipped when the service argument is absent.\n"
    + "Portable/Node compilation and service-memory adaptation: Firmingo-Compiler tools/dev.mjs.\n"
    + "No sibling lookup, binary copying, installation, device access or network fallback.");
} else {
  if (args.length > 1 || args[0] === "" || args[0]?.startsWith("-")) throw new Error("Select at most one explicit local service; use --help");
  run("python3", ["Tools/verify-fixtures.py"]);
  run(process.execPath, ["--test", "Tools/ManagedWASM/test-consumer-package.mjs"]);
  run("python3", ["-I", "-S", "-B", "Tools/ManagedWASM/test-compiler-host.py"]);
  run("python3", ["-I", "-S", "-B", "Tools/Hardware/test-nano-host.py"]);
  run(process.execPath, ["--check", "Tools/Hardware/prepare-nano-test.mjs"]);
  run(process.execPath, ["--check", "Tools/Hardware/prepare-stateful-nano-test.mjs"]);
  run("python3", ["-I", "-S", "-B", "Tools/Hardware/check-nano-gates.py"]);
  run("python3", ["-I", "-S", "-B", "Tools/Hardware/check-nano-proxy.py", "--compile-only"]);
  run("python3", ["Tools/ManagedWASM/update-resource-inventory.py", "--check"]);
  const env = { ...process.env };
  delete env.FIRMINGOKIT_WASM_MODULE;
  if (args[0]) env.FIRMINGOKIT_WASM_MODULE = resolve(args[0]);
  requireSwiftTesting(join(root, 'Tests'));
  run("swift", ["test", "--disable-xctest", "--enable-swift-testing"], env);
  run("python3", ["-I", "-S", "-B", "Tools/ManagedWASM/check-compiler-host.py"]);
  run("python3", ["-I", "-S", "-B", "Tools/Hardware/check-nano-host.py"]);
  console.log(JSON.stringify({ status: "sdk_adapter_checks_completed", actualRuntimeRequested: Boolean(args[0]),
    qualification: "local SDK tests only; absent-service runtime cases skip; no hardware qualification" }));
}
