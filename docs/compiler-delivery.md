# Reviewed source-built compiler integration — 2026-10-14

FirmingoKit now wraps the reproduced LLVM 22.1.8/WASI ABI-two service,
101,194,565 bytes, SHA-256
`a7648688ae9e349304c576804367b66b68b22185060a847a2e292675329ca493`.
Its exact source/notice and paired-delivery review is owned by Firmingo-Compiler.
The historical service is no longer an accepted new-build input. Public types,
recipe/interface/receipt semantics and independent deployment checks are retained;
stored artifacts, associations and journals are not rewritten.

Explicit maintenance commands, with reviewed anchors:

```sh
node Tools/ManagedWASM/stage-sdk-runtime.mjs EXPLICIT_SOURCE_EXPORT \
  4cbdf856304063dbac59a27ea8703f74ffedbc534521b0d40d13013913d4dba5
node Tools/ManagedWASM/stage-sdk-service-review.mjs EXPLICIT_PAIRED_DELIVERY \
  261dcdfd80b39c11d522289d8ac411b0882cdc36ec91f370b0f92f11f2957d39
python3 Tools/ManagedWASM/update-resource-inventory.py --check
node Tools/ManagedWASM/run-validation.mjs
FIRMINGOKIT_WASM_MODULE=EXPLICIT_LOCAL_REVIEWED_SERVICE \
  swift test --filter ManagedWebKitCompilerTests
python3 Tools/ManagedWASM/make-resource-consumer.py --fresh NEW_SIMPLE_NAME
swift run --package-path .build/NEW_SIMPLE_NAME ResourceConsumer EXPLICIT_LOCAL_REVIEWED_SERVICE
```

Imports are explicit maintenance only. Normal builds use committed resources,
never discover a compiler sibling, fetch binaries or run Node/Python. Service
review staging verifies all delivery payload bytes against an independent
inventory, checks the pinned service/source review and notice identities, then
copies four documents only. The service and source archive are not bundled.
Twelve fixed roles include source-specific credits, full license/grant texts,
review and source-notice provenance. Root checkout attributes preserve exact bytes.

Runtime manifest SHA-256:
`9fbf7807c22468083fd38fcf7870bd3c71b1b6d002b849631aa7a5cb31572c47`.
Inventory SHA-256:
`a2621c2010df4094b43e789d3e5de83c1ae94ad13444cc771ce83b5e19bb3729`.
Toolchain SHA-256:
`3eda5778fdc515f974d683570a6d6d8e1891ec9a64d0285e473401ebae14dd86`.
All anchors change deliberately with imported bytes. An explicit service also
verifies the retained review/notice documents. Editing approval, roles or bytes
cannot bypass the independently compiled inventory. A reviewed service identity
is separate from availability: default builds report `invalidFile("compiler.wasm")`
while the binary is absent. The production descriptor catalogue stays empty.

Actual local checks pass: 22 focused resource/preparation/ELF test functions,
152 ordinary SDK test functions with nine unavailable-service skips, and all nine
real public-API/private-WebKit tests in the separate explicit-service run. The
new fresh SwiftPM consumer uses an SDK-local paired delivery copy and reproduces
the known synthetic Blink capsule, service-free preparation and declared-ELF
conversion. iOS Simulator/device target builds and native DocC pass with signing
disabled. The initial real-WebKit run found one stale old asset-fingerprint golden;
its update is recorded, and final behavior expectations all pass.

The existing default-resource controller harness also passes: empty catalogue,
reviewed-but-absent service, no fallback/device operation, stale readiness discard
and explicit fresh retry. It uses the current SwiftPM `.build/out/Products/Debug`
module/object/bundle and excludes the app entry point when linking the harness.
No native UI or visual inspection is performed.

The tests remain synthetic-resident compiler evidence, never deployable firmware
qualification. Signing/minimum-OS, physical iOS/iPadOS, installed-image evidence,
board operations and useful hardware behavior remain unqualified. No board is
contacted or changed. Manual SDK CI requires a provisioned Xcode 27 runner;
these local results do not claim a GitHub run. See [compiler adapter](compiler-adapter.md)
and the retained review files in `Sources/FirmingoKit/Resources/ManagedCompiler/`.

## Provisioning from a transferred transport

Firmingo-Compiler now provides `service-release build|verify|extract` for a
deterministic local ZIP with the reviewed service, source archive, notices and
delivery manifest. A separate `release.json` binds the archive and delivery
identities. The release inventory hash must come from a trusted package/release
context, independently of the downloaded files. The transport has no downloader
and creates no publication or automatic SDK resource installation.

After verifying/extracting with the compiler's explicit maintenance CLI, use the
SDK-local extracted directory as `EXPLICIT_PAIRED_DELIVERY` above. Supply its
`compiler.wasm` explicitly to the existing compiler initializer/test environment.
Keep the complete source/notices with shared binary delivery. Neither the SDK
consumer nor its ordinary build needs a compiler checkout or maintenance tools.
The source-only runtime import, twelve committed role identities and empty
production descriptor catalogue remain unchanged.

The first local transport has release inventory SHA-256
`c7fca729708f4213ca586b35d4d7fdaef568e35a61209bce8b95976a3cd6b39b`;
its 336,179,045-byte ZIP has SHA-256
`fcb9dee7c117cab83d0f1597cf3a4a8dea3172d6abde72d3a83c6a3847a8d26f`.
See the compiler's `docs/service-release.md` and `docs/release-qualification.md`
for bounded verification and the remaining signed/physical host and device gates.

A fresh `.build/transport-consumer-r1` package has now built and run against the
SDK-local extracted service. Actual private-WebKit compilation reproduces the
same synthetic Blink capsule; service-free preparation and declared-ELF conversion
also pass. Execution has no compiler sibling lookup. The ordinary adapter harness
passes all 152 SDK test functions with nine absent-service skips. Logs are
`.build/transport-fresh-consumer.log` and `.build/transport-adapter-validation.log`.
These results qualify local transfer/consumption only; no device is contacted.
