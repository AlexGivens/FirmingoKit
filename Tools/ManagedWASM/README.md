# Managed WASM development runner

This development workflow compiles and links constrained Nano sketches using the
real Clang/LLD WASI service, then validates/packages the ELF through FirmingoKit.
It is **not** the production SDK compiler. No compiler service is bundled with the
package. The SDK now integrates an independent WebKit host/worker and demo
Build/Run, but requires the exact service to be selected explicitly until redistribution
is resolved. The Node runner remains a separate development workflow.
Node is a development requirement only; it is not a host-app runtime or fallback.

The browser-capable worker core is independently authored following ArduinoKit's
ABI-two service boundary. It uses the vendored `@bjorn3/browser_wasi_shim` 0.4.2
under its MIT option; both offered license texts and byte/hash receipts are
retained under `Vendor/browser_wasi_shim`. No custom ArduinoKit worker, filesystem,
recipe, bridge, host page, service source, or conventional sysroot was copied.
The compiler-service binary is copied once only under `.build/` for validation;
its redistribution/license decision remains pending. LLVM/WASI service component
license and build-provenance review also remains required before packaging.

## Recipe and restrictions

`Recipe/manifest.json` pins the independent facade, entry wrappers, linker script
and fixed arguments. Refresh it after an intentional recipe change with:

```sh
node Tools/ManagedWASM/update-recipe-manifest.mjs
```

The target is Cortex-M0+ Thumb, `armv6m-none-eabi`, base/soft-float AAPCS and the
pinned Nano stateless ABI-one table. `Arduino.h` uses compiler predefined integer
and size types, asserts a 40-byte table with offsets 8–36, and exposes the selected
Nano facade only. The API address comes from the explicit request. No sample
address is embedded in the recipe; the development cases use synthetic bindings.

No conventional Arduino sysroot, libc, libgcc, compiler-rt, external library or
native compiler is linked. This is deliberately narrower than the GCC proof:
operations requiring runtime helpers, including the observed `millis() / 250`,
fail with an unresolved `__aeabi_uidiv` diagnostic. No compatibility with arbitrary
Arduino sketches is claimed. Setup/loop must return; compile/link cannot prove
that behavior. Used mutable storage and runtime constructors/destructors fail.

The linker folds code/readonly constants into `.text` at `0x10200100`, capped at
3840 bytes. It discards unused ARM unwind metadata because exceptions/unwinding
are disabled. LLD can propagate MERGE|STRINGS metadata into `.text`; SDK parsing
accepts only the reviewed readonly/executable flags `0x06` / `0x36`. Writable and
other unknown flag variants still fail. This does not change the FMS1 wire contract.

## Isolated worker and bounds

Every revision receives a fresh WASI instance and workspace. Immutable toolchain
capabilities remain readonly through child-directory and direct file-descriptor
opens. Writable files are capped at 2 MiB each, monotonic total growth at 8 MiB,
and created/linked entries at 64. Paths reject traversal and ambiguous aliases;
no host filesystem or network capability is preopened. Input includes only the
SDK-prepared translation unit, safe filename, exact recipe/board/profile and
aligned resident API address. There are no caller flags or archive inputs.

The service module must match declared byte count/SHA-256, required imports/exports,
ABI two and a hard defined-memory maximum of at most 256 MiB. The observed
ArduinoKit binary declares no maximum. `bound-service-memory.mjs` verifies that
exact original and creates a separate SDK-local derivative changing only its
memory limits and section length; all instruction/data sections remain verbatim.
Both hashes/limits are recorded. This is an explicit maintenance adaptation,
not a source/compiler swap. It does not bound total JavaScript/JIT/process memory.

`BrowserWorker.js` is the browser worker entry; the staged classic bundle now runs
in the SDK's private WebKit host, with offline macOS integration evidence. `NodeWorker.mjs` executes the same core for development. The controller
correlates one job, validates all response fields/diagnostics/timings/output,
terminates before reporting completion/failure/cancellation, and enforces a
1–120000 ms configurable deadline (default 60000). It never reuses mutable compiler
state or returns a previous artifact after cancellation. A new build needs a new
worker. No device operation occurs.

Observed service behavior is documented in
[compiler-service-observations.md](../../docs/compiler-service-observations.md):
frontend errors can return zero status, and diagnostic locations can use physical
workspace lines despite `#line`. The runner checks error diagnostics after every
phase and stops before wrapper compilation/linking. It maps only the known
workspace source's two prefix lines, leaving already presumed source names alone.
Unmatched diagnostic lines remain visible; oversized/malformed output fails rather
than silently dropping records.

## Reproduce development validation

First supply the **exact approved development service** at
`.build/managed-wasm/compiler.wasm`. The selected reference is documented in
`docs/compiler-reference.json`; no script locates or builds a sibling checkout.
Creating that directory and copying an existing service from a read-only reference
is a one-time maintenance input, not a normal package build dependency. The
required original is 101196042 bytes with SHA-256
`bce6632512852bf86baf7ca7b6eddd07209c0c4e29ae3b2288ec27e69028887d`.
The derived bounded binary is 101196044 bytes with SHA-256
`3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33`.

```sh
node Tools/ManagedWASM/bound-service-memory.mjs
node --test Tools/ManagedWASM/Tests/*.test.mjs
FIRMINGOKIT_WASM_MODULE=.build/managed-wasm/compiler-bounded.wasm \
  node --test Tools/ManagedWASM/Tests/*.test.mjs
node Tools/ManagedWASM/run-validation.mjs
node Tools/ManagedWASM/make-development-manifest.mjs
swift test
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/ManagedWASM/VerifyCapsules.swift .build/out/Products/Debug/FirmingoKit.o \
  -o .build/managed-wasm/verify-capsules
.build/managed-wasm/verify-capsules
```

Adjust SwiftPM module/object paths for another Xcode layout. Ordinary JavaScript
tests skip the five explicitly opt-in real-service tests if the environment
variable is absent; ordinary Swift package tests never depend on the development module. Four macOS
WebKit tests are explicitly opt-in with the same environment variable.
The runner writes only SDK `.build/managed-wasm/` outputs. It checks Blink/Console,
syntax failure, globals, constructors and a missing division helper. The verifier
uses SDK preparation and the resulting ELF, exact recipe/toolchain manifest hashes,
and deliberately synthetic resident/image hashes. **Never upload these outputs.**
Their success establishes offline development compile/link/structural packaging,
not trusted installed-resident association, instruction/ABI execution, useful sketch
behavior or hardware qualification. Node timing and linear-memory observations
are not WebKit/macOS-sandbox/physical-iPad performance measurements.

Production work still requires license/provenance clearance, approved bundled
resources, signed-host distribution checks, executable ABI and board evidence, and physical
macOS/iOS/iPadOS sandbox and minimum-OS validation. The current tests do not meet
that product gate.

## SDK WebKit staging and real-runtime checks

`stage-sdk-runtime.mjs` bundles only the reviewed static ES-module syntax used by
these independent sources and the licensed shim. It rejects external imports,
cycles and unhandled exports, checks the recipe/shim receipts, syntax-checks both
bundles, and packages the host/recipe/worker/licenses with an integrity manifest.
No custom reference source or compiler binary is staged. Review the printed
manifest SHA-256 and deliberately update `VerifiedManagedToolchain.manifestSHA256`
after an intentional runtime change; staging never changes the Swift anchor itself.

```sh
node Tools/ManagedWASM/stage-sdk-runtime.mjs
FIRMINGOKIT_WASM_MODULE="$PWD/.build/managed-wasm/compiler-bounded.wasm" swift test
```

This runs actual macOS SDK/WebKit/WASI source compile/link/packaging, syntax errors,
overlapping-build rejection, cancellation during compilation, and deadline/fresh
build tests with synthetic resident bindings. Default tests skip the eight real WebKit tests when
no service is supplied. It does not exercise a signed sandbox or physical iOS host.

The retained `VerifyWebKit.swift` and `VerifyDemoBuild.swift` harnesses are also
macOS development-only. The latter checks actual editor-revision cancellation,
subsequent build identity, selection changes, durable managed journals, corruption
and explicit clear. All journal outputs stay beneath SDK `.build`. Run with:

```sh
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/ManagedWASM/VerifyWebKit.swift .build/out/Products/Debug/FirmingoKit.o \
  -o .build/managed-wasm/verify-webkit
cp -R .build/out/Products/Debug/FirmingoKit_FirmingoKit.bundle .build/managed-wasm/
.build/managed-wasm/verify-webkit
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/ManagedWASM/VerifyDemoBuild.swift Demo/Shared/WorkbenchBuildModel.swift \
  Demo/Shared/WorkbenchModel.swift Demo/Shared/InstallationRecordStore.swift \
  Demo/Shared/DemoOperationError.swift Demo/Shared/CompilerRecordReader.swift \
  .build/out/Products/Debug/FirmingoKit.o -o .build/managed-wasm/verify-demo-build
.build/managed-wasm/verify-demo-build
```

The adjacent resource bundle is needed for this Xcode SwiftPM command-line layout;
normal app consumers receive the package bundle automatically. These harnesses
never connect or upload. Their capsules have synthetic resident metadata and
must never be used on hardware. See `docs/compiler.md` for the explicit demo
resident-record format and the remaining licensing/qualification gates.

The host-only multiwindow check also needs no compiler module or WebKit process:

```sh
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/verify-demo-device-operations.swift Demo/Shared/WorkbenchBuildModel.swift \
  Demo/Shared/WorkbenchModel.swift Demo/Shared/InstallationRecordStore.swift \
  Demo/Shared/DemoOperationError.swift Demo/Shared/CompilerRecordReader.swift \
  .build/out/Products/Debug/FirmingoKit.o -o .build/managed-wasm/verify-demo-device-operations
.build/managed-wasm/verify-demo-device-operations
```

It checks competing reservations, stale Run/review/clear decisions, corrupt
journals, cancellation and storage failures using temporary `.build` files.
No connection, upload or firmware backend is executed.


The development catalogue controller harness uses only SDK-local synthetic parser
metadata and the same explicit service. It checks exact selection/no latest fallback,
Pico availability, actual offline edit cancellation and receipt identity, separate
association review, revocation during offline compilation, stale durable context
before compiler loading, changed/mismatched anchors, bounded imports and symlinks.
No board is connected, staged or committed. All artifacts are NEVER DEPLOY fixtures.

```sh
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/ManagedWASM/VerifyDemoCatalogue.swift Demo/Shared/WorkbenchBuildModel.swift \
  Demo/Shared/WorkbenchModel.swift Demo/Shared/InstallationRecordStore.swift \
  Demo/Shared/DemoOperationError.swift Demo/Shared/CompilerRecordReader.swift \
  .build/out/Products/Debug/FirmingoKit.o -o .build/managed-wasm/verify-demo-catalogue
.build/managed-wasm/verify-demo-catalogue
```

The existing adjacent SDK resource bundle remains required for these standalone
harnesses. The app receives the same package resources through Xcode. This does
not establish approved compiler/catalogue bundling, actual file-picker UI, signed
sandbox or hardware behavior. Exact receipts are in `docs/demo-catalogue-experiment.json`.

The host-only association persistence harness needs no compiler service or WebKit
process. It restores synthetic SDK records from isolated `.build` storage, checks
explicit save/restore/forget, no automatic device/build/trust selection, stale Run
before compiler or network access, stale mutations, active-operation guards,
missing descriptors, unrelated-device preservation, schema/bounds/corruption,
symlinks, cancellation and storage failures. No board is contacted.

```sh
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/verify-demo-associations.swift Demo/Shared/WorkbenchBuildModel.swift \
  Demo/Shared/WorkbenchModel.swift Demo/Shared/InstallationRecordStore.swift \
  Demo/Shared/DemoOperationError.swift Demo/Shared/CompilerRecordReader.swift \
  .build/out/Products/Debug/FirmingoKit.o -o .build/managed-wasm/verify-demo-associations
.build/managed-wasm/verify-demo-associations
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/verify-demo-journal.swift Demo/Shared/InstallationRecordStore.swift \
  Demo/Shared/DemoOperationError.swift .build/out/Products/Debug/FirmingoKit.o \
  -o .build/managed-wasm/verify-demo-journal
.build/managed-wasm/verify-demo-journal
```

The final command retains complete-image journal validation after shared-storage
changes. Exact association receipts are in `docs/demo-associations-experiment.json`.
The user disabled visual inspection; validation uses source, controller tests and
platform builds exclusively.

## Pending package inventory and minimal consumer

`update-resource-inventory.py` stages only deterministic pending service metadata
and an empty descriptor catalogue. It inventories the existing runtime manifest,
page and WASI licenses, never copies/approves a service, rejects an unapproved
`compiler.wasm` in the package and does not change Swift trust anchors. After a
reviewed runtime change, regenerate and independently review/pin both runtime and
inventory hashes; the current resource inventory anchor is
`9a2a074d1d3ba5135f37edba7b8d2937b934a1759dc3d10fedceafb601b92d82`.
The existing runtime/recipe/service digests and build-receipt identities are unchanged.

```sh
python3 Tools/ManagedWASM/update-resource-inventory.py --check
# After a deliberate reviewed runtime staging change:
python3 Tools/ManagedWASM/update-resource-inventory.py
swift test --filter ManagedCompilerResourceTests
python3 Tools/ManagedWASM/make-resource-consumer.py
swift run --package-path .build/compiler-resource-consumer ResourceConsumer
```

The separate consumer uses only this local Swift package and generated inputs
under `.build`; it loads the verified empty catalogue without imported metadata or
service. It demonstrates package-resource discovery, not successful default
compilation. The current default compiler fails with pending-service review.
The additional opt-in runtime test uses an isolated internally test-anchored
inventory and the exact existing development service to verify known Blink output;
it never modifies production resources or establishes redistribution approval.

Exact source/platform/archive evidence and limits are in
`docs/compiler-resources-experiment.json`. Actual approved service/production
descriptor staging, signed sandbox, physical iPad and hardware remain open.

An unsigned macOS archive can be checked without opening or inspecting the app:

```sh
xcodebuild archive -project Demo/FirmingoDemo.xcodeproj -scheme FirmingoDemo \
  -destination 'generic/platform=macOS' -derivedDataPath .build/demo-resource-archive \
  -archivePath .build/FirmingoResources.xcarchive CODE_SIGNING_ALLOWED=NO
python3 Tools/ManagedWASM/verify-resource-archive.py .build/FirmingoResources.xcarchive
```

This checks byte-exact resource inclusion and the current pending/service-free,
empty-catalogue policy. It does not run the archive or qualify signed distribution.

## Default demo source checks

The SDK now exposes `ManagedSketchCompiler.verifyResources()` for asset-only
setup checks, without preprocessing/WebKit/device access. Default demo startup
uses it with SDK-owned catalogue loading. The standalone harness needs a freshly
copied adjacent package bundle; app consumers receive their bundle automatically.

```sh
cp -R .build/out/Products/Debug/FirmingoKit_FirmingoKit.bundle .build/managed-wasm/
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/ManagedWASM/VerifyDemoDefaults.swift Demo/Shared/WorkbenchBuildModel.swift \
  Demo/Shared/WorkbenchModel.swift Demo/Shared/InstallationRecordStore.swift \
  Demo/Shared/DemoOperationError.swift Demo/Shared/CompilerRecordReader.swift \
  .build/out/Products/Debug/FirmingoKit.o -o .build/managed-wasm/verify-demo-defaults
.build/managed-wasm/verify-demo-defaults
```

It checks actual empty/pending SDK startup, no implicit selection/fallback,
independent providers, released imported capabilities, late startup after imports,
failed metadata/reloads, cancellation and closed-window late delivery. Internally
injected synthetic readiness permits a Build request that must still fail the real
SDK's pending-service check before runtime/device access. It needs no service,
WebKit or board. Existing catalogue tests now explicitly renew review after a
compiler-file change before testing the stale durable Run gate. Exact receipts
are in `docs/demo-default-resources-experiment.json`.
