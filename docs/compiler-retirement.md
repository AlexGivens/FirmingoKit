# Retiring the SDK standalone compiler — 2026-10-12

Current public preparation integration and updated package identities: [service-free preparation](service-free-preparation.md). Earlier records remain historical evidence.

The SDK's real build facade already passed the shared-compiler adapter gates. This
increment removes its redundant standalone Node/WASI compiler: `Sources/`, `Recipe/`,
`Vendor/`, JavaScript tests, Node controller/worker/assets/host bridge, and obsolete
recipe/service-manifest maintenance tools under `Tools/ManagedWASM/`. The inactive
`ManagedWorkerOutput` ELF-only native decoder and its old-schema tests are also
removed. The [36-file retirement inventory](compiler-retirement.json) verifies every
removed file was unchanged from `05cae8fa8e58c706eceb6a15812d7ca500375d7b` and retains
its exact byte count/hash. No unrelated working change was discarded.

Firmingo-Compiler now owns original-service memory adaptation through explicit
`bound-service`/`test-memory` commands. It checks the original and derived pinned
hashes, independently compares every section outside the memory declaration,
requires a new output directory and emits a pending-distribution receipt. Local
verification reproduces exactly 101196044 bytes/SHA-256
`3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33` with a 4096-page
maximum. The original is unchanged; existing outputs cannot be overwritten.
No binary is committed or added to SDK resources, and source/distribution review
remains unresolved. Imported compiler package/runtime/inventory identities remain
unchanged from [adapter evidence](compiler-adapter.md).

`run-validation.mjs` is now an SDK test entry point: fixture integrity, resource
inventory, full Swift package tests, and optional actual WebKit execution through
an explicitly selected service. It never selects an ambient service path. An
empty environment value previously enabled runtime tests and resolved to the
current directory; both the entry point and opt-in test boundary now treat absence/
empty environment as unavailable. Explicit empty CLI paths are rejected.

`VerifyCapsules.swift` becomes a read-only capsule/report/binding verifier; it no
longer needs retired recipe/developer-manifest files or packages ELF. `VerifyWebKit.swift`
embeds its test sketches and accepts an explicit service rather than reading old
Node-produced files. SDK CI calls the refocused validation entry point with pinned
Node; portable runtime/service-maintenance checks stay in compiler CI. Definitions
are not verified GitHub runs and need the documented provisioned Apple runner.

Public Swift source/preparation/conversion/build/receipt APIs are retained. Independent
SDK capsule/report validation, associations, fresh capability/selection checks,
installation, uploads and durable journals are retained. Public preparation and
supplied-ELF conversion implementations still require deliberate compatibility
migration; this increment retires the standalone runtime and old bridge, not those
public APIs. Original dated evidence/manifests remain historical records.

## Actual local verification

- SDK validation without a service: 148 tests reported in 16 suites, all passing,
  with nine real-WebKit cases skipped. Explicit empty environment likewise skips
  those nine cases. With an explicitly selected regenerated service, all 148 pass,
  including all nine actual WebKit cases.
- Compiler fast suite: 90 passed and one actual memory-adaptation case explicitly
  skipped. Explicit original-service maintenance: two cases pass; actual Node/WASM
  compilation/lifecycle: eight pass using the regenerated derivative.
- Compiler CLI produces a 276-byte synthetic capsule with SHA-256
  `b1fe6d33463c0147d82ce646af01439055b372d4b6a17d2e621935d22eaaa802`.
  The independent SDK capsule/report/binding verifier accepts those exact bytes.
  Wrong binding, corrupted capsule and nonregular input are rejected with exit 1.
  The binding is synthetic and this capsule must never be deployed.
- iOS Simulator/device builds and native DocC pass without documentation warnings. Fixture verification remains 34 files;
  the pending inventory remains unchanged. Updated standalone Swift verifiers
  compile with the declared Swift/concurrency settings; the standalone WebKit
  verifier compiles the known Blink/Console vectors and rejects actual syntax errors.

Logs are SDK `.build/retirement-{sdk,sdk-runtime,empty-service,ios-simulator,ios-device,capsule-tool,capsule-tool-build,webkit-tool,webkit-tool-build}.log`
and compiler `.build/retirement-{contracts,memory,memory-availability,runtime,build,check}.log`.
No source-to-resident hardware qualification, device write, signed sandbox or
physical iOS/iPadOS run occurred. No firmware executable source changed.
