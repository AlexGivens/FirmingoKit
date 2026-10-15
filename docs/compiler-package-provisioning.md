# Prepare a self-contained experimental SDK package

Current explicit FMS2 compiler/upload support and refreshed package identities: [stateful adoption](stateful-adoption.md). Older records below retain their original qualification scope.

The SDK now includes one experimental Nano descriptor from a checked schema-2
Firmware CI export at `e0a79d1…`: build `c44d25ef…`, API `0x10022c9c`, catalogue
SHA-256 `e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e`.
It is static metadata, not installed-image/device/hardware evidence. Selection is
explicit. The source checkout omits the compiler and reports missing bytes.

Compiler package `0.1.0-nano-managed-experimental.1` ties together service,
corresponding source, notices, web runtime, recipe and exact firmware evidence.
The SDK independently accepts manifest SHA-256
`d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c`,
verifying all 33 roles with streaming hashes, closed paths and bounds.

```sh
node Tools/ManagedWASM/stage-sdk-consumer.mjs EXPLICIT_COMPILER_PACKAGE \
  d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c
python3 Tools/ManagedWASM/update-resource-inventory.py --check
# After reviewing/committing metadata and its compiled inventory anchor:
node Tools/ManagedWASM/prepare-sdk-package.mjs EXPLICIT_COMPILER_PACKAGE \
  d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c NEW_PREPARED_SDK
python3 Tools/ManagedWASM/make-bundled-consumer.py PREPARED_SDK NEW_CONSUMER
swift run --package-path CONSUMER BundledConsumer NEW_RESULTS
```

Staging writes metadata/runtime/notice documents only. New imports require deliberate
inventory generation and compiled-anchor review. Current thirteen-role inventory
SHA-256 is `e3c6080b78d2014cf82ca54f4605647f5e3b3967a8acb23c0daff2812475acf2`;
runtime, recipe, service and native toolchain digests are unchanged.

Preparation requires a clean committed tracked SDK snapshot and new output. It
copies tracked sources, supplies verified `compiler.wasm` to app resources, and
retains complete paired source/notices under `CompilerDelivery/`, outside app
resources. It records every copied identity, SDK commit and compiler anchor,
rechecks output/source state and writes `prepared-package.json` last. No Git
metadata, untracked developer data or device associations are copied. Failures
remove only their own output. There is no network operation or publication.

Consumers of this prepared SDK use `loadBundled()`, an explicit build ID and
`ManagedSketchCompiler()` without a service URL, environment override, file picker,
maintenance runtime or compiler sibling. The helper builds two supported sketches,
rejects syntax errors and rebuilds through those public APIs. It has no device or
upload calls. Ordinary service-free CI continues to test absent-binary behavior;
complete packaged compilation is an explicit-asset check. No binary is committed,
downloaded implicitly or published. Complete source/notices accompany the shared
prepared package; firmware evidence images are not SDK installation resources.

Signed/minimum-OS/physical hosts and device qualification remain open. Preserve
independent deployment/capability/source-freshness checks and explicit installed
image/device evidence before any later Run.

## Actual first prepared consumer

Clean SDK commit `fbd5993…` produced 261 prepared files, manifest
`5d47369942c75afe6ac5d7bfcbba22dea817f645929ab0a74535c7ff5bfc3566`.
A fresh consumer using only that SDK copy passed default `loadBundled()` and
`ManagedSketchCompiler()` execution with no service URL or compiler sibling lookup.
GPIO/delay and binary console capsules match independent Node results (`958b861b…`,
`b372c00e…`); a syntax error rejects and a fresh revision reproduces GPIO bytes.
The independent firmware validator accepts both at the exact API and rejects
the old address with `wrong_api`. No payload executes on a board.

Ordinary SDK tests pass 152 functions with nine unavailable-service skips; actual
explicit-service WebKit tests pass all nine cases. Thirteen-role corruption tests,
the host-only default controller harness, iOS Simulator/device builds and DocC pass.
Three SDK maintenance boundary tests pass. Signing/physical/device results remain
open. Capsule bytes are reproducible; UUID-based request/receipt identities vary
deliberately between snapshots. Logs remain local under `.build/consumer-package-*`
and `.build/default-nano-consumer-r1.log`.

The full prepared-package suite exposed two historical test assumptions that all
SDK packages omit compiler bytes. Dedicated resource checks now cover present
and absent service states; preparation/ELF tests retain their service-independent
assertions. Clean corrected commit `3927416…` prepares 261 records, manifest
`ba8d63b3742c8cc78022e56c364483ed030dca927c1d31c866b1bf31dfe5480e`.
The complete native suite from that prepared copy reports 152 tests passing with
ten explicit skips (nine opt-in compiler cases and one source-only absence case).
The source checkout's sixteen focused adapter/resource functions also pass.

Final source-checkout validation again reports 152 tests passing with nine
unavailable-service skips and three maintenance boundary passes. The corrected
prepared SDK separately passes all nine actual WebKit cases using its own local
service, covering both build overloads, diagnostics and cancellation/deadline/
fresh-state behavior. Final DocC succeeds without warnings. Logs are
`.build/prepared-nano-sdk-r3-{tests,webkit}.log`,
`.build/consumer-package-final-sdk-tests.log` and
`.build/consumer-package-docc-final.log`. SDK CI still requires its provisioned
Apple runner; local passes do not establish a remote run.
