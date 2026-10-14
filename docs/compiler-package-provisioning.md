# Prepare a self-contained experimental SDK package

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
