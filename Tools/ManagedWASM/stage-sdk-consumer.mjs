import { writeFileSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { verifyConsumerPackage, fileRecord } from "./consumer-package.mjs";

// Explicit metadata staging. Ordinary SDK builds never run Node or discover a sibling checkout.
const [directory, expected] = process.argv.slice(2);
if (!directory || !expected || process.argv.length !== 4) throw new Error("Use stage-sdk-consumer.mjs PACKAGE TRUSTED_MANIFEST_SHA256");
const { root, manifest, bytes } = verifyConsumerPackage(directory, expected);
for (const [script, subdirectory, anchor] of [["stage-sdk-runtime.mjs", "web", manifest.review.webManifestSHA256],
  ["stage-sdk-service-review.mjs", "service", manifest.review.deliveryManifestSHA256]]) {
  const result = spawnSync(process.execPath, ["Tools/ManagedWASM/" + script, join(root, subdirectory), anchor], { stdio: "inherit", timeout: 60000 });
  if (result.error || result.status !== 0) throw new Error("Consumer resource staging failed");
}
const destination = "Sources/FirmingoKit/Resources/ManagedCompiler";
const cataloguePath = join(root, "catalogue.json"), catalogue = readFileSync(cataloguePath);
const pin = manifest.files.find(file => file.path === "catalogue.json");
if (fileRecord(cataloguePath).sha256 !== manifest.catalogueSHA256 || createHash("sha256").update(catalogue).digest("hex") !== manifest.catalogueSHA256
    || catalogue.length !== pin.bytes) throw new Error("Consumer catalogue changed");
writeFileSync(join(destination, "catalogue.json"), catalogue);
writeFileSync(join(destination, "consumer-package.json"), bytes);
console.log(JSON.stringify({ status: "staged_experimental_consumer_metadata", packageSHA256: expected,
  catalogueSHA256: manifest.catalogueSHA256, firmwareBuildID: manifest.review.firmwareBuildID, binaryCopied: false }));
