#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));

/** SDK checks only; compiler maintenance and portable/Node builds belong to Firmingo-Compiler. */
function run(command, args, env = process.env) {
  const result = spawnSync(command, args, { cwd: root, env, stdio: "inherit", timeout: 180000 });
  if (result.error || result.signal || result.status !== 0)
    throw new Error(result.error?.message || `${command} failed (${result.signal || result.status})`);
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
  run("python3", ["Tools/ManagedWASM/update-resource-inventory.py", "--check"]);
  const env = { ...process.env };
  delete env.FIRMINGOKIT_WASM_MODULE;
  if (args[0]) env.FIRMINGOKIT_WASM_MODULE = resolve(args[0]);
  run("swift", ["test"], env);
  run("python3", ["-I", "-S", "-B", "Tools/ManagedWASM/check-compiler-host.py"]);
  console.log(JSON.stringify({ status: "sdk_adapter_checks_completed", actualRuntimeRequested: Boolean(args[0]),
    qualification: "local SDK tests only; absent-service runtime cases skip; no hardware qualification" }));
}
