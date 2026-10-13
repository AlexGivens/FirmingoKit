# Shared compiler adapter — 2026-10-12

Current public preparation integration and updated package identities: [service-free preparation](service-free-preparation.md). Earlier records remain historical evidence.

Both `ManagedSketchCompiler.build` overloads now use Firmingo-Compiler for raw-source
preprocessing, WASM compile/link, ELF validation and FMS1 packaging. Swift owns the
private WebKit page/worker adapter, verified resource access, strict output checks,
native receipt translation and physical-device/deployment rules. No compiler
source is generated during a consumer build and no sibling checkout is consulted.

## Imported package and compatibility

The committed source-only development package is version `0.0.0-development`,
interface one/service ABI two. Its manifest SHA-256 is
`508216d85611a7bb0b604a09ae642cd9050b1d5a14abb7190d6db1543eb519d5`.
The runtime manifest is
`87c364e7091698480c3cabcc7b44c2ccc2ea46fe9221a9349c44eae614937074`;
the eight-role SDK inventory is
`45400194b577dd903a407ab9cc21a5ab905ee3fac146f622c7b8c1e714492ba5`.
Compiler source/recipe/vendor notices and recreation scripts accompany the bundle.
Staging requires an explicit export directory and independently selected trusted
manifest digest. Normal SwiftPM resources carry compiled-in integrity anchors.
The service remains absent/pending and the default catalogue remains empty.

The legacy request sends only nine static resident-binding fields. Its device ID
stays in Swift; it does not invent firmware version/commit/report evidence. Offline
requests retain exact schema-one descriptor identity. UUID/revision becomes a
lossless ASCII compiler token, including UInt64.max. Native output checks receipt
correlation/input hash, exact target/source/revision, service/recipe/shim identities,
ELF/capsule bytes/digests, report binding, canonical base64 and closed field bounds.
The independent deployment parser and fresh session/association/transaction checks
remain active.

Existing native legacy/offline receipt schemas and saved association/journal records
retain their meaning. Runtime provenance changes with the package. Optional
`compilerReceiptJSON` preserves the distinct execution receipt; independent
supplied-ELF packaging leaves it nil. First-line BOM diagnostic byte columns include
the original three bytes. Progress now verifies before preparing and can report
compiling twice; internal validation does not add a public enum case.

The private native deadline is 60 seconds including loading. Cancellation/deadline
waits for disposal acknowledgment; cleanup has a separate two-second watchdog.
Every build gets a fresh page and worker. No visible view is required.
Public Swift preparation/conversion APIs and old standalone developer compiler tools
remain compatibility references pending deliberate retirement. The actual SDK build
facade uses the imported compiler package. Historical evidence below and elsewhere
still describes the original bytes and must not be rewritten as current evidence.

## Actual checks

On the recorded macOS arm64/Xcode 27.0/Swift 6.4 host:

- `swift test`: 154 reported tests, nine real-WebKit cases explicitly skipped.
- Explicit-service `ManagedWebKitCompilerTests`: all nine pass, including both
  build APIs, known Blink/Console bytes, failure diagnostics, busy/cancellation/
  deadline/reentry, Unicode/BOM/UInt64.max and eight receipt/byte mutations.
- Separate SwiftPM consumer: bundled empty catalogue discovery and actual Blink
  compilation pass using only the SDK dependency and explicit service input.
- Generic iOS Simulator and iOS device SDK builds pass; native DocC passes without
  documentation warnings. These are build results, not physical iOS runtime tests.
- Fixture verification: 34 files unchanged; resource inventory check passes.
- Compiler repository: 89 fast checks, eight actual Node/WASM cases and nine Chrome
  cases (six actual compiler) pass; source export is recreated byte-for-byte.

Exact SDK commands, with ignored output under `.build/`:

```sh
python3 Tools/verify-fixtures.py
python3 Tools/ManagedWASM/update-resource-inventory.py --check
swift test
FIRMINGOKIT_WASM_MODULE="$PWD/.build/managed-wasm/compiler-bounded.wasm" \
  swift test --filter ManagedWebKitCompilerTests
python3 Tools/ManagedWASM/make-resource-consumer.py
swift run --package-path .build/compiler-resource-consumer ResourceConsumer \
  "$PWD/.build/managed-wasm/compiler-bounded.wasm"
xcodebuild build -workspace Validation/FirmingoKit.xcworkspace -scheme FirmingoKit \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode-simulator CODE_SIGNING_ALLOWED=NO
xcodebuild build -workspace Validation/FirmingoKit.xcworkspace -scheme FirmingoKit \
  -destination 'generic/platform=iOS' -derivedDataPath .build/xcode-device CODE_SIGNING_ALLOWED=NO
xcodebuild docbuild -workspace Validation/FirmingoKit.xcworkspace -scheme FirmingoKit \
  -destination 'generic/platform=macOS' -derivedDataPath .build/docc CODE_SIGNING_ALLOWED=NO
```

The explicitly supplied service is the previously recorded bounded 101196044-byte
binary, SHA-256 `3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33`.
No test capsule is deployable: all resident bindings are synthetic.
Logs are `.build/adapter-{package-tests,webkit-final,consumer,ios-simulator,ios-device,docc}.log`.
No firmware, upload, visual inspection or hardware operation was performed.

`.github/workflows/adapter.yml` defines manual package/resource/consumer/runtime-
availability checks and independent iOS Simulator/device/DocC jobs. It requires a
provisioned `firmingo-xcode-27` self-hosted macOS ARM64 runner; none is claimed
configured and no GitHub run is verified. It fetches no service. Actual runtime
absence remains explicit skips. Bash preserves pipeline failures and matrix builds
retain `fail-fast: false`. Compiler CI owns the portable/Node/source-export checks;
SDK legacy standalone Node tools are retained migration references, excluded from
this new workflow. Actionlint was unavailable locally.

Signed sandbox/minimum-OS and physical iOS/iPadOS execution, real resident exports,
service-source/distribution review, hardware deployment, and retirement of the
remaining compatibility implementations remain open.

The subsequent [standalone compiler retirement](compiler-retirement.md) removes the old Node/WASI copies and ELF-only bridge. Public Swift preparation/conversion APIs remain compatible; see that record for current test counts and commands.
