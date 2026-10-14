import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, rmSync, symlinkSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { createHash } from "node:crypto";
import { fileRecord, verifyConsumerPackage, CONSUMER_SHA256 } from "./consumer-package.mjs";

test("SDK package verifier streams observed copies and rejects overwrites and byte bounds", () => {
  const root = mkdtempSync(join(tmpdir(), "firmingokit-package-fixture-"));
  try {
    const data = Buffer.alloc(1024 * 1024 + 19, 0x81); writeFileSync(join(root, "input"), data);
    assert.deepEqual(fileRecord(join(root, "input"), data.length, join(root, "copy")), {
      bytes: data.length, sha256: createHash("sha256").update(data).digest("hex") });
    assert.deepEqual(readFileSync(join(root, "copy")), data);
    assert.throws(() => fileRecord(join(root, "input"), data.length - 1));
    assert.throws(() => fileRecord(join(root, "input"), data.length, join(root, "copy")), /EEXIST/);
    symlinkSync(join(root, "input"), join(root, "link"));
    assert.throws(() => fileRecord(join(root, "link")));
  } finally { rmSync(root, { recursive: true }); }
});

test("SDK maintenance refuses an unchecked manifest even if its caller supplies a self-calculated hash", () => {
  const root = mkdtempSync(join(tmpdir(), "firmingokit-package-anchor-"));
  try {
    const bytes = Buffer.from('{"schema":1,"qualification":"approved"}'); writeFileSync(join(root, "manifest.json"), bytes);
    assert.throws(() => verifyConsumerPackage(root, createHash("sha256").update(bytes).digest("hex")), /anchor/);
    assert.throws(() => verifyConsumerPackage(root, CONSUMER_SHA256), /anchor/);
  } finally { rmSync(root, { recursive: true }); }
});

test("anchored package inventory rejects missing, extra, linked and corrupt payload fixtures", () => {
  // Exact public inventory, tiny placeholder payloads: structural boundary tests, never compiler execution.
  const data = readFileSync(new URL("../../Sources/FirmingoKit/Resources/ManagedCompiler/consumer-package.json", import.meta.url));
  const manifest = JSON.parse(data);
  for (const mutation of ["missing", "extra", "link", "corrupt"]) {
    const root = mkdtempSync(join(tmpdir(), "firmingokit-package-roles-"));
    try {
      writeFileSync(join(root, "manifest.json"), data);
      for (const file of manifest.files) {
        const path = join(root, file.path); mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, "NEVER DEPLOY");
      }
      if (mutation === "missing") rmSync(join(root, "catalogue.json"));
      if (mutation === "extra") writeFileSync(join(root, "unexpected"), "unlisted");
      if (mutation === "link") { rmSync(join(root, "catalogue.json")); symlinkSync("manifest.json", join(root, "catalogue.json")); }
      assert.throws(() => verifyConsumerPackage(root, CONSUMER_SHA256), /Missing|Unlisted|Symlinked|integrity|Invalid consumer/);
    } finally { rmSync(root, { recursive: true }); }
  }
});
