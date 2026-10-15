import { mkdirSync, writeFileSync, rmSync, lstatSync, readFileSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { verifyConsumerPackage, fileRecord, CONSUMER_SHA256 } from "../ManagedWASM/consumer-package.mjs";

export const EXPORT_SHA = "90911f7d3684dab4123d36b9a018805cc36ae58cb197c318fe720cb18d434a65";
export const CATALOGUE_SHA = "8b8f1432d40b42502acca728083e5045f09ed493014bbde1786d3fa8aeed13cd";
export const BUILD_ID = "dacbf259b96de0e050514764253403f3ef1ef51d0f9efaf1f43a10d8654c0e18";

/** Capture explicit independently anchored FMS2 firmware evidence and Compiler catalogue without device access. */
export function prepare(consumer, firmwareInput, metadataInput, outputInput) {
  const checked = verifyConsumerPackage(consumer, CONSUMER_SHA256);
  const firmware = resolve(firmwareInput), metadata = resolve(metadataInput), output = resolve(outputInput);
  for (const root of [firmware, metadata]) if (!lstatSync(root).isDirectory() || lstatSync(root).isSymbolicLink()) throw new Error("Select real input directories");
  if (fileRecord(join(firmware, "manifest.json"), 16384).sha256 !== EXPORT_SHA
      || fileRecord(join(metadata, "catalogue.json"), 16384).sha256 !== CATALOGUE_SHA) throw new Error("Select the exact reviewed FMS2 export and imported catalogue");
  const manifest = JSON.parse(readFileSync(join(firmware, "manifest.json")));
  if (manifest.schema !== 3 || manifest.profile !== "nano-managed-v2" || manifest.files.length !== 39) throw new Error("Unsupported stateful export");
  mkdirSync(output);
  try {
    const files = [];
    for (const record of [...manifest.files, { path: "manifest.json", ...fileRecord(join(firmware, "manifest.json"), 16384) }]) {
      let source = firmware;
      for (const part of record.path.split("/")) {
        if (!/^[A-Za-z0-9_.-]+$/.test(part) || [".", ".."].includes(part)) throw new Error("Unsafe firmware path");
        source = join(source, part); if (lstatSync(source).isSymbolicLink()) throw new Error("Symlinked firmware evidence");
      }
      const path = "firmware/" + record.path, target = join(output, path); mkdirSync(dirname(target), { recursive: true });
      const actual = fileRecord(source, record.bytes, target);
      if (actual.bytes !== record.bytes || actual.sha256 !== record.sha256) throw new Error("FMS2 evidence changed while copying");
      files.push({ path, ...actual });
    }
    for (const [path, source, expected] of [["catalogue.json", join(metadata, "catalogue.json"), CATALOGUE_SHA],
      ["consumer-manifest.json", join(checked.root, "manifest.json"), CONSUMER_SHA256]]) {
      const actual = fileRecord(source, 65536, join(output, path));
      if (actual.sha256 !== expected) throw new Error("Qualification metadata changed");
      files.push({ path, ...actual });
    }
    const plan = { schema: 2, kind: "nano-fms2-sdk-qualification-inputs", consumerManifestSHA256: CONSUMER_SHA256,
      exportManifestSHA256: EXPORT_SHA, catalogueSHA256: CATALOGUE_SHA, firmwareBuildID: BUILD_ID,
      board: "nano_rp2040_connect", profile: "nano-managed-v2", firmwareVersion: "0.1.0-statefulupload-exp1",
      residentUF2SHA256: "1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f",
      firmwareCommit: manifest.firmwareCommit, files, installed: false, deviceOperations: false, hardwareQualified: false,
      effect: "Resident-only UF2 preserves old slot; separately prepare a checked initial FMS2 composite and verify ROM readback before boot. No device operation in this tool." };
    writeFileSync(join(output, "test-plan.json"), JSON.stringify(plan, null, 2) + "\n", { flag: "wx" });
    return { status: "prepared_explicit_fms2_qualification_inputs", testPlanSHA256: fileRecord(join(output, "test-plan.json"), 65536).sha256,
      files: files.length, deviceOperations: false };
  } catch (error) { rmSync(output, { recursive: true }); throw error; }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === "--help") console.log("Usage: node prepare-stateful-nano-test.mjs REVIEWED_CONSUMER EXPLICIT_FMS2_EXPORT EXPLICIT_IMPORTED_METADATA NEW_OUTPUT\nOffline evidence capture only; no device operation.");
  else { if (args.length !== 4) throw new Error("Use --help and select all four explicit paths"); console.log(JSON.stringify(prepare(...args))); }
}
