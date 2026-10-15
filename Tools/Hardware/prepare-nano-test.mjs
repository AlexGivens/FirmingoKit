#!/usr/bin/env node
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fileRecord, verifyConsumerPackage, CONSUMER_SHA256 } from '../ManagedWASM/consumer-package.mjs';

/** Copy only independently anchored resident evidence; never connect, build firmware, compose an image or flash. */
export function prepare(input, output) {
  const { root, manifest, bytes } = verifyConsumerPackage(input, CONSUMER_SHA256);
  output = resolve(output); mkdirSync(output);
  try {
    mkdirSync(join(output, 'firmware')); mkdirSync(join(output, 'firmware/contract'));
    mkdirSync(join(output, 'firmware/contract/facade'));
    const selected = manifest.files.filter(f => f.path.startsWith('firmware/') || f.path === 'catalogue.json');
    if (selected.length !== 13) throw new Error('Unexpected Nano evidence inventory');
    for (const f of selected) {
      const actual = fileRecord(join(root, f.path), f.bytes, join(output, f.path));
      if (actual.bytes !== f.bytes || actual.sha256 !== f.sha256) throw new Error('Resident evidence changed while copying');
    }
    writeFileSync(join(output, 'consumer-manifest.json'), bytes, { flag: 'wx' });
    const plan = { schema: 1, kind: 'nano-sdk-hardware-qualification-inputs', consumerManifestSHA256: CONSUMER_SHA256,
      firmwareBuildID: manifest.review.firmwareBuildID, firmwareCommit: manifest.review.firmwareCommit,
      catalogueSHA256: manifest.catalogueSHA256, board: 'nano_rp2040_connect', profile: 'nano-managed-v1',
      residentUF2: selected.find(f => f.path === 'firmware/resident.uf2'),
      residentELF: selected.find(f => f.path === 'firmware/resident.elf'),
      apiAddress: '0x10022c9c', firmwareVersion: '0.1.0-m9exp1',
      defaultTestEndpoint: { address: '192.168.77.1', port: 7420 },
      imageEffect: 'Resident-only UF2; existing managed slot is preserved. Review/read back or initialize the slot during separately selected ROM setup before booting an unknown prior sketch.',
      recovery: 'Board-correct Nano REC/GND ROM procedure; D2/GPIO25-to-GND is separate managed-upload authorization.',
      association: 'Explicit operator evidence of exact installed resident required; hello/version/API matching is not installed-image attestation.',
      files: [...selected, { path: 'consumer-manifest.json', ...fileRecord(join(output, 'consumer-manifest.json'), 65536) }],
      deviceOperations: false, installed: false, hardwareQualified: false };
    writeFileSync(join(output, 'test-plan.json'), JSON.stringify(plan, null, 2) + '\n', { flag: 'wx' });
    return { status: 'prepared_nano_test_inputs', files: plan.files.length,
      testPlanSHA256: fileRecord(join(output, 'test-plan.json'), 65536).sha256, deviceOperations: false };
  } catch (error) { rmSync(output, { recursive: true }); throw error; }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--help') console.log('Usage: node Tools/Hardware/prepare-nano-test.mjs EXPLICIT_REVIEWED_CONSUMER_PACKAGE NEW_OUTPUT\nCopies verified resident-only test inputs; no device access or flashing.');
  else {
    if (args.length !== 2) throw new Error('Select the reviewed consumer package and a new output; use --help');
    console.log(JSON.stringify(prepare(args[0], args[1])));
  }
}
