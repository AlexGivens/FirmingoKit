# Development and validation

Current public preparation integration and updated package identities: [service-free preparation](service-free-preparation.md). Earlier records remain historical evidence.

Current compiler/SDK validation commands and standalone-runtime retirement are recorded in [compiler-retirement.md](compiler-retirement.md) and [Tools/ManagedWASM/README.md](../Tools/ManagedWASM/README.md). Older commands below refer to their dated reference revisions.


Current build-facade/package integration: [shared compiler adapter](compiler-adapter.md).
The following original implementation records remain historical evidence where they describe SDK-owned compiler execution or earlier resource hashes.

The [compiler migration inventory](compiler-migration.md) records the ownership
split accepted on 2026-10-12. This documentation increment does not change any
commands, resource hashes, fixture manifests, public APIs, or schemas below.
Keep existing SDK-local compiler checks until portable replacements pass; retain
Swift/web-host, consumer-package, and device-safety checks in this repository.

Use Xcode 27.0 (build 27A266a), Apple Swift 6.4
(`swift-driver version 1.168.6`, `swiftlang-6.4.0.34.1`) for this initial
increment. The package declares Swift tools 6.4, macOS 14, and iOS/iPadOS 17.
All outputs below go under `.build/`, ignored by Git. There is no Git remote or
published documentation URL in this checkout.

```sh
swift --version
xcodebuild -version
python3 Tools/verify-fixtures.py
swift build
swift test
xcodebuild -list -workspace Validation/FirmingoKit.xcworkspace
xcodebuild build -workspace Validation/FirmingoKit.xcworkspace \
  -scheme FirmingoKit -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/xcode-simulator CODE_SIGNING_ALLOWED=NO
xcodebuild build -workspace Validation/FirmingoKit.xcworkspace \
  -scheme FirmingoKit -destination 'generic/platform=iOS' \
  -derivedDataPath .build/xcode-device CODE_SIGNING_ALLOWED=NO
xcodebuild test -workspace Validation/FirmingoKit.xcworkspace \
  -scheme FirmingoKit \
  -destination 'platform=iOS Simulator,id=48DD1F0D-419C-44F7-B736-253597BF20F6' \
  -derivedDataPath .build/xcode-simulator-tests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Demo/FirmingoDemo.xcodeproj -scheme FirmingoDemo \
  -destination 'platform=macOS' -derivedDataPath .build/demo-macos CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Demo/FirmingoDemo.xcodeproj -scheme FirmingoDemo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/demo-simulator CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Demo/FirmingoDemo.xcodeproj -scheme FirmingoDemo \
  -destination 'generic/platform=iOS' -derivedDataPath .build/demo-device CODE_SIGNING_ALLOWED=NO
xcodebuild docbuild -workspace Validation/FirmingoKit.xcworkspace \
  -scheme FirmingoKit -destination 'generic/platform=macOS' \
  -derivedDataPath .build/docc CODE_SIGNING_ALLOWED=NO
git diff --check
```

The simulator ID above identifies an installed iPhone 18 Pro with iOS 27.0 on
this machine; choose a locally installed ID after `xcrun simctl list devices
available` elsewhere. Generic destinations compile but cannot run tests.
Generated DocC currently appears in
`.build/docc/Build/Products/Debug/FirmingoKit.doccarchive/`. The Swift-DocC
plugin, static hosting base path, CI, and Pages publication are open work; native
Xcode `docbuild` does not require a plugin or publishing setup.

For the serial/managed-upload increment on 2026-09-29, fixture verification, `swift build`, `swift test` (55 tests),
package iOS Simulator/device SDK builds, demo macOS/Simulator/device SDK builds,
iOS 27.0 Simulator tests (55 tests), and native DocC generation passed. The 14 serial session
tests use a controllable fake peer for interleaved binary bytes, ownership,
partial writes, backpressure, deadlines, cancellation, and fresh connections.
The 23 managed artifact/upload tests add independent FMS1/frame validation,
report/resident rejection, chunk boundaries, one-shot commit, saved records, and
fresh-session reconciliation after loss/cancellation/deadlines. All fixture
capsules are non-executable and were used only with fake transports. Reference
image/ABI/build/harness hashes are added to the fixture provenance manifest.
Builds used `CODE_SIGNING_ALLOWED=NO`; no app was installed on a physical device.
The first `swift test` in the restricted shell could not write SwiftPM's user-level
Clang module cache; rerunning with the normal Xcode/SwiftPM cache access passed.
Computer Use permissions were unavailable, so visual UI interaction and app
launch behavior were not verified. No live board, network peer, firmware update,
flash, compiler runtime, or physical iOS/iPadOS test was performed. These are
separate acceptance tasks, not implied by the checks above.

The complete-image preflight increment on 2026-09-29 passed `swift test` and
iOS 27.0 Simulator tests with **71 tests**, fixture verification with 26 firmware
vectors plus three lifecycle resources, package iOS Simulator/device SDK builds,
demo macOS/Simulator/device SDK builds, native DocC generation without documentation
warnings, and diff whitespace checks. Sixteen new lifecycle tests cover independent
non-executable UF2 headers, exact manifest/recipe metadata, corruption, bounds,
unsafe paths/sources, missing selections/files, cancellation, and Nano/Pico guidance.
The local-file test checks the underlying POSIX/Cocoa missing-file cause; the SDK
does not erase filesystem errors behind a generic validation failure.

A temporary one-time Swift test validated SDK-local copies of all four provisional
observed release images. Its source and image copies remain only under `.build/`;
ordinary tests use checked-in resources and need no reference checkout. The
observed index provenance/hashes are in `Fixtures/lifecycle/provenance.json`.
Logs are `.build/lifecycle-tests-final.log`, `lifecycle-simulator-tests-final.log`,
`lifecycle-observed-images.log`, `lifecycle-package-*.log`, `lifecycle-demo-*.log`,
and `lifecycle-docc.log`. Demo/test builds retain Xcode's benign warning about no
AppIntents.framework dependency. The new review sheet has not been visually or
accessibility tested; physical file-picker/sandbox behavior, minimum-OS execution,
installation, updates, interrupted flashing, and real boards remain unqualified.
No programming backend was invoked or hardware written.

The experimental installation increment on 2026-09-29 passed `swift test` and
iOS 27.0 Simulator tests with **89 tests**, 26 firmware/three lifecycle fixture
verification, package generic iOS Simulator/device builds, demo macOS/Simulator/
device builds, and native DocC without documentation warnings. Eighteen new tests
cover one-shot/target/attachment/lease/durable-record gates, partial writes, sync
and persistence failure, cancellation, pending-session/managed-work rejection,
restored uncertainty and hello mismatch, strict ROM metadata, and the native
transfer loop with bounded in-memory writers. No native writer was invoked.

The development-only demo journal check compiles against the SDK built by this
Xcode 27 SwiftPM configuration and writes exclusively beneath `.build`. It checks
atomic/synchronized save/load, latest/retained operation files, corrupt context,
and storage failure, without executing any programming backend. Repeated directory
creation was fixed after the first check exposed a failure on the second access.
Run after `swift test` (adjust the module/object paths if your SwiftPM layout differs):

```sh
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/verify-demo-journal.swift Demo/Shared/InstallationRecordStore.swift \
  Demo/Shared/DemoOperationError.swift \
  .build/out/Products/Debug/FirmingoKit.o -o .build/verify-demo-journal
.build/verify-demo-journal
```

Logs use `.build/installer-tests-final.log`, `installer-simulator-tests.log`,
`installer-package-*.log`, `installer-demo-*.log`, and `installer-docc.log`.
`installer-demo-journal-build.log` / `installer-demo-journal.log` record the journal
check. Builds remain unsigned; benign AppIntents extraction warnings persist in
test/demo builds. No UI launch, accessibility interaction, signed-sandbox execution,
physical iOS/iPadOS device, minimum-OS run, actual bootloader write, real disconnect,
firmware update or hardware recovery was tested. Those requirements remain open.

Contract references are never built or modified by these commands. To update
firmware fixtures, pin a complete new Firmingo commit, review compatibility,
copy only approved vectors to this test bundle, update `provenance.json` hashes,
and validate the new contract and affected tests together. Do not silently
follow a sibling branch. `Tools/verify-fixtures.py` uses only local resources.

The compiler foundation increment on 2026-09-29 passed `swift test` and iOS 27.0
Simulator tests with **107 tests in 11 suites**, local fixture verification
(26 firmware vectors, three lifecycle resources, one synthetic ELF resource),
package generic iOS Simulator/device builds, demo macOS/Simulator/device builds,
and native DocC without documentation warnings. Eighteen new tests cover immutable
source/provenance bounds, lexical preprocessing/original locations, independent
UTF-8 hash vectors, every ELF truncation, malformed mappings/sections/symbols,
exact code/capsule limits, cancellation and complete input receipts. The eight-byte
parser code is non-executable; capsule bytes match the pinned firmware golden
vector. Receipt tests use fake hashes, not verified compiler assets.

The one-time SDK-local `.build/compiler-observed/VerifyObserved.swift` check
repackaged a provisional existing GCC ELF into the independently recorded FMS
capsule byte for byte. Input provenance is `docs/compiler-observed.json`;
SDK-local copies/harness and output remain under `.build`. The check compiled only
the Swift verifier against the SDK object, without executing a sketch compiler,
reference maintenance command, upload or programming backend. Synthetic binding
metadata was used solely for structural validation. Ordinary tests never read
these observed files or a sibling checkout. This is not actual WASM/source/ABI
qualification. Logs are `.build/compiler-foundation-tests.log`,
`compiler-simulator-tests.log`, `compiler-package-*.log`, `compiler-demo-*.log`,
`compiler-docc.log`, and `compiler-observed-{build,check}.log`.

Unsigned consumer builds retain the benign AppIntents extraction warning.
No compiler assets are packaged, no actual source compile/link or physical board
execution was performed, and no physical iOS/iPadOS, minimum-OS, signed-sandbox,
UI interaction or accessibility qualification was run. Those requirements and
actual runtime integration remain open. Reference hashes were checked against
pinned committed bytes; ArduinoKit stayed clean and Firmingo retained only its
pre-existing `AGENTS.md` modification.

The new managed-preparation DocC Swift examples were extracted into
`.build/compiler-examples.swift` and type-checked against the built SDK with
`xcrun swiftc -typecheck -swift-version 6 -enable-upcoming-feature ApproachableConcurrency
-target arm64-apple-macos14.0 -I .build/out/Products/Debug
.build/compiler-examples.swift` (log: `compiler-examples.log`). Generated DocC data
resolves the landing-page topics and new guide; no visual web preview was run.
The standalone `swift build` also passed (`compiler-build.log`). Tracked diff and
135 untracked authored files passed whitespace checks.

The managed WASM development increment on 2026-09-29 passed **108 Swift tests in
11 suites** on macOS and iOS 27.0 Simulator, standalone `swift build`, package
generic iOS Simulator/device builds, demo macOS/Simulator/device builds, and
native DocC without documentation warnings. The new ELF test checks LLD's reviewed
readonly merged-string flags and rejects writable/unknown variants. Existing
local protocol, lifecycle and compiler fixture checks remain independent of the
development compiler binary and both sibling checkouts.

The reproducible development commands and exact service inputs are in
[Tools/ManagedWASM/README.md](../Tools/ManagedWASM/README.md). With the explicitly
supplied SDK-local bounded service, all **23 JavaScript tests** pass, including
five real-service worker tests. With no service environment variable, 18 tests
pass and those five integration tests skip. Coverage includes resource hashes,
service ABI, fixed recipe/input schemas, memory bounds, readonly descriptors,
workspace limits, strict bridge results, source diagnostics, fresh worker builds,
cancellation, timeout and subsequent independent builds. No Node requirement is
added to normal package builds or host apps.

Real WASI Clang/LLD compiled Blink and Console to ARM ELF. The Swift development
verifier packaged them as 336-byte and 392-byte FMS1 capsules using the exact
recipe/toolchain manifests. An independent Python ELF-section/symbol parse and
little-endian FMS1 reconstruction matched both SDK outputs byte for byte. Syntax
errors, used mutable globals, runtime constructors and unresolved division helpers
failed as expected. Reference/source hashes, output digests, observed phase times
and linear-memory sizes are in `docs/compiler-wasm-experiment.json`; linear memory
is not peak process memory. All outputs use synthetic resident/image bindings
and must never be uploaded.

Logs are `.build/managed-wasm-worker-tests.log`,
`managed-wasm-default-tests.log`, `wasm-recipe-swift-tests.log`, `wasm-tests.log`,
`wasm-swift-build.log`, `wasm-package-*.log`, `wasm-demo-*.log`, and `wasm-docc.log`.
Unsigned demo/test builds retain only the benign AppIntents extraction warning.
No private WebKit host, packaged compiler service or production compilation API
is integrated; demo Build/Run remain unavailable. Custom-service redistribution
licensing and LLVM/WASI component provenance review remain pending. No hardware
execution, physical iOS/iPadOS, minimum-OS execution, signed sandbox, UI interaction,
accessibility or WebKit compiler validation was performed. ArduinoKit and Firmingo
were only read; no reference build, maintenance tool, upload or flashing was run.

The SDK/WebKit compiler increment on **2026-09-30** passed **120 tests in 13 suites**
with the explicit real-service capability enabled on macOS 27.0 (26A428), Xcode
27.0 (27A266a). Four tests execute actual SDK WebKit/WASI compilation: distinct
Blink/Console outputs and syntax diagnostics, cancellation then fresh state,
overlapping-build rejection, and native deadline then fresh build. Their resident
metadata is synthetic; no capsule may be uploaded. Without that capability, the
same suite passes with those four skipped (116 ordinary tests). iOS 27.0 Simulator
passed 116 tests in 12 suites; the real WebKit suite is macOS-only and does not
establish physical iOS/iPadOS support.

All 24 JavaScript tests passed with five opt-in real-service tests, including
portable SHA-256 vectors/padding boundaries, strict resource/bridge validation,
readonly and bounded workspace capabilities, cancellation and deadline recovery.
Package generic iOS Simulator/device builds, demo macOS/Simulator/device builds,
and native DocC passed. DocC emitted no documentation warnings, and its new Swift
compiler example type-checked for `arm64-apple-macos14.0`. Only the existing benign
AppIntents extraction warning remains in unsigned demo/test builds.

The retained `VerifyDemoBuild.swift` check compiled and ran against the actual
SDK with all journals under `.build`: an edit during real compilation returned
no stale artifact; the next document revision compiled correctly; target changes
invalidated results; record reimport revoked trust without canceling its new load;
managed transaction latest/history files synchronized and restored exactly; corrupt
context blocked Run until explicit clear; clearing retained history. The existing
complete-firmware journal harness also passed after the shared bounded reader
refactor. None of these checks connected, staged, committed or flashed a board.

Reproducible SDK-local resource staging, service selection, opt-in tests and
harness commands are in [Tools/ManagedWASM/README.md](../Tools/ManagedWASM/README.md).
The stager never includes a compiler binary or reads a sibling checkout. Its
independent page/worker/recipe and licensed shim resources total 134724 bytes;
the separate reviewed 101196044-byte service remains an explicit host capability
pending custom-service redistribution/component-license review. The runtime's
manifest/hash anchor is independently checked and recorded in
`docs/compiler-webkit-experiment.json`. Recipe/artifact hashes match the earlier
independent FMS1 reconstruction. No reference state changed: ArduinoKit stayed
clean and Firmingo retained only its existing `AGENTS.md` modification.

The subsequent demo coordination increment on **2026-09-30** passed the new
`Tools/verify-demo-device-operations.swift` harness: twelve competing Run requests
granted one reservation; overlapping firmware installation, outcome review and
clear were rejected; stale owners could not release/update another action;
stale windows preserved newer transactions and refreshed their context before
any compiler loading or connection; corrupt/failed storage blocked deployment;
explicit clear retained history; cancellation did not acquire a reservation.
The real WebKit demo build harness and existing complete-firmware journal harness
also passed against the updated host controllers. All outputs stayed under
`.build`; no connection, stage, commit, reset or firmware write was performed.

`swift test` passed the unchanged 116 ordinary package tests (120 discovered, four
opt-in WebKit tests skipped), and the final unsigned demo builds passed for macOS,
generic iOS Simulator and generic iOS device destinations. Only the existing
AppIntents metadata-extraction warning appeared. SDK runtime/recipe resources and
public APIs did not change, so JavaScript tests and DocC generation were not
repeated for this host-only increment. Actual multiwindow UI, filesystem failure
injection at every sync point, signed sandbox, cross-process and physical-device
qualification remain open. Commands are linked above; exact final source receipts
are in [demo-device-coordination.json](demo-device-coordination.json), separate
from the preceding WebKit implementation snapshot.

Logs: `.build/device-coordination-check{,-build}.log`,
`device-coordination-real{,-build}.log`,
`device-coordination-firmware-journal{,-build}.log`,
`device-coordination-package-tests.log`, and
`device-coordination-{macos,simulator,device}.log`.

Logs: `.build/webkit-native-integration-tests.log`, `webkit-default-tests.log`,
`webkit-ios-tests.log`, `webkit-js-tests.log`, `webkit-package-*.log`,
`webkit-demo-{macos,simulator,device}.log`, `webkit-docc.log`, `webkit-examples.log`,
`webkit-real-runtime.log`, `webkit-demo-check{,-build}.log`, and
`webkit-existing-journal{,-build}.log`. Actual UI launch/file-picker/accessibility,
signed sandbox, declared minimum-OS execution, physical iOS/iPadOS compiler,
process-peak performance, resident ABI execution, upload/startup/useful sketch
behavior and hardware installation/recovery remain unrun and unqualified.

The final resource lookup rejects a missing entire SDK bundle with an unavailable
error rather than invoking SwiftPM's trapping accessor. A deterministic lookup test
covers absent candidates and verifies normal package-host discovery.

## Catalogue metadata increment — 2026-09-30

The additive catalogue/descriptor/association APIs passed ten focused tests.
Independent Python fixtures establish exact catalogue bytes, canonical descriptor
identity and persistence bytes; mutation tests cover unsupported scalar/ABI/recipe
fields, bounds, duplicate/conflicting metadata, cancellation, absent/removed builds
and mismatched device evidence. `python3 Tools/verify-fixtures.py` passed all 33
fixture files, including three metadata parser fixtures. Synthetic records remain
test-only and must never be used for deployment.

The full macOS package run passed **130 tests in 14 suites**, including all four
opt-in real WebKit/WASM tests. Ordinary `swift test` passed 126 tests with those
four skipped. The installed iOS 27.0 Simulator passed **126 tests in 13 suites**;
its tests do not execute the macOS-only WebKit suite. Both generic iOS package
builds and unsigned demo builds for macOS, iOS Simulator and iOS device passed
using the commands at the start of this document. Only the existing AppIntents
metadata-extraction warning appeared in applicable Xcode builds/tests.

The new catalogue DocC guide built without warnings. Its Swift example typechecked
against the built package module; generated landing-page references resolve the
guide and every added public type. No visual documentation preview was run.
Catalogue validation adds no service binary, production firmware descriptor,
connection or device write. Compiler requests/receipts and demo selection retain
their existing device-bound APIs. Default resource loading, complete asset manifest,
offline compiler migration, approved metadata/service packaging and demo catalogue
UI remain open. Signed sandbox, minimum-OS, physical iPad and hardware qualification
are not established by these checks.

Additional commands, with all outputs inside FirmingoKit:

```sh
swift test --filter ManagedCatalogueTests
FIRMINGOKIT_WASM_MODULE="$PWD/.build/managed-wasm/compiler-bounded.wasm" swift test
xcrun swiftc -typecheck -swift-version 6 \
  -enable-upcoming-feature ApproachableConcurrency \
  -target arm64-apple-macos14.0 -I .build/demo-macos/Build/Products/Debug \
  .build/catalogue-example.swift
```

The last command uses the Swift block extracted from
`Sources/FirmingoKit/FirmingoKit.docc/ManagedCatalogue.md`. The opt-in command uses
the existing exact development-only service described in
`Tools/ManagedWASM/README.md`; it does not bundle or regenerate that binary.
Unchanged JavaScript/runtime tests and demo operation/journal harnesses were not
repeated. Reference file hashes and pinned committed bytes were rechecked without
modifying either sibling checkout. Exact source receipts, platform results and
limitations are in [compiler-catalogue-experiment.json](compiler-catalogue-experiment.json).

Logs: `.build/catalogue-focused-tests.log`, `catalogue-runtime-tests.log`,
`catalogue-default-tests.log`, `catalogue-ios-tests.log`,
`catalogue-package-{simulator,device}.log`,
`catalogue-demo-{macos,simulator,device}.log`, `catalogue-docc.log` and
`catalogue-example.log`.

## Device-independent compiler increment — 2026-09-30

The SDK now has additive offline request/preparation/compiler/converter/result
APIs and exact input/output receipts without a device ID. FMS1/report validation
and preprocessing are shared with legacy APIs; legacy capsule bytes and receipt
behavior remain compatible. Explicit artifact association binding produces the
existing upload capsule after local metadata/byte checks, with no device side effect.

Seven new ordinary tests passed: independent Python receipt/capsule hashes,
normalization/source mapping, missing selections, complete source/revision/catalogue/
descriptor/toolchain identity (including UInt64.max revision), explicit multi-device
binding and mismatch rejection, unsupported recipe/ELF output and cancellation.
Three new real-WebKit tests passed: offline Blink/Console artifacts match the
independently recorded FMS1 hashes; errors map to original source; cancellation
allows fresh legacy reentry; mixed overloads reject concurrency in both directions.

The final real-runtime macOS run passed **140 tests in 15 suites**, including all
seven opt-in WebKit tests. The ordinary run passed 133 with seven skipped. iOS 27.0
Simulator passed **133 tests in 14 suites** without executing the macOS-only runtime
suite. Both generic iOS package builds, unsigned macOS/iOS Simulator/iOS device
demo builds, and final DocC generation passed. DocC had no warnings; both new guide
examples typechecked against the built SDK, and generated landing references resolve
the guide and all four added public types. Applicable Xcode builds/tests retained
only the existing AppIntents metadata-extraction warning. No visual DocC preview ran.

Run the platform/demo/DocC commands at the start of this document, plus:

```sh
python3 Tools/verify-fixtures.py
swift test --filter ManagedOfflineBuildTests
swift test
FIRMINGOKIT_WASM_MODULE="$PWD/.build/managed-wasm/compiler-bounded.wasm" swift test
xcrun swiftc -typecheck -swift-version 6 \
  -enable-upcoming-feature ApproachableConcurrency \
  -target arm64-apple-macos14.0 -I .build/demo-macos/Build/Products/Debug \
  .build/offline-examples.swift
```

The example file contains both Swift blocks extracted from
`Sources/FirmingoKit/FirmingoKit.docc/OfflineManagedCompilation.md`. The fixture
verifier passed 34 files including the independent offline expectation JSON.
All outputs and the selected existing development service stayed inside FirmingoKit.
The recipe/host JavaScript/WASM service bytes did not change; JavaScript tests and
unchanged demo operation/journal harnesses were not repeated. All listed reference
files matched pinned commit bytes and recorded hashes before and after the work;
both sibling checkouts remained read-only.

Production metadata/service bundling, service redistribution/provenance review,
automatic loading and demo catalogue selection remain open. Actual signed sandbox,
minimum-OS, physical iPad, resident ABI, upload/startup/useful behavior and hardware
installation/recovery remain unqualified. The demo still uses its legacy combined
resident record; the new SDK offline API is documented for reuse. No board connection,
stage, commit, reset or firmware write occurred. Exact source receipts and limitations
are in [compiler-offline-experiment.json](compiler-offline-experiment.json).

Logs: `.build/offline-{initial,focused,default,runtime}-tests.log`,
`offline-ios-tests.log`, `offline-package-{simulator,device}.log`,
`offline-demo-{macos,simulator,device}.log`, `offline-docc.log` and
`offline-examples.log`.

## Demo catalogue selection increment — 2026-09-30

The demo now selects SDK-filtered exact firmware builds from explicitly imported,
hash-verified development metadata and compiles without physical-device inputs.
It separately imports/reviews exact device associations for Run, with no automatic
latest choice or legacy fallback after a failed import. The explicit compatibility
mode retains existing resident records. Compiler-service and production catalogue
packaging/default loading remain open; associations are window context restored
through explicit imports, not an automatic persisted roster.

`Tools/ManagedWASM/VerifyDemoCatalogue.swift` passed SDK-filtered Nano/Pico selection,
unknown-ID clearing, actual offline WebKit edit cancellation/fresh receipt identity,
unusable endpoint/backend independence, review revocation during offline compilation,
strict matching/mismatched association imports, separate Run review gates, stale
durable context rejected before service loading or connection, changed anchors
(including during import), cancellation/reentry, oversize and symlink rejection.
Every metadata/code input is synthetic test-only NEVER DEPLOY evidence. The harness
never calls Run with an empty current durable journal, connects, stages or commits.

The existing real WebKit demo build harness passed legacy cancellation, source
receipts, target/trust invalidation, resident reimport and durable journal handling.
The host-only coordination harness passed twelve competing reservations, stale
Run/review/clear gates, corruption, cancellation and storage failure. The ordinary
package run passed 133 tests (140 discovered, seven macOS real-runtime tests skipped).
Final unsigned demo builds passed for macOS, generic iOS Simulator and generic iOS
device destinations; only the existing AppIntents extraction warning appeared.

Run the three demo build commands at the start of this document. Exact compilation
and execution commands for all three harnesses are in
[Tools/ManagedWASM/README.md](../Tools/ManagedWASM/README.md), including the new
`CompilerRecordReader.swift` dependency. All output remained under `.build`.
SDK public APIs/runtime/recipe/service bytes were unchanged; package platform tests,
the complete-firmware journal harness, JavaScript tests and DocC were not repeated
for this host-only increment. Previous API/platform evidence remains historical.

Native UI inspection was attempted twice and remained blocked by pending macOS
Accessibility/Screen Recording permissions; no permissions were granted or bypassed.
Actual file-picker/keyboard/VoiceOver/layout/light/dark/increased-contrast behavior,
signed sandbox, minimum OS, physical iPad and hardware deployment remain unqualified.
Only source review and platform compilation cover the view's firmware-operation
review gates. Reference checkouts remained read-only with pinned byte hashes intact.
Exact source receipts and limitations are in
[demo-catalogue-experiment.json](demo-catalogue-experiment.json).

Logs: `.build/demo-catalogue-{macos,simulator,device}.log`,
`demo-catalogue-harness{,-build}.log`, `demo-catalogue-legacy{,-build}.log`,
`demo-catalogue-coordination{,-build}.log` and `demo-catalogue-package-tests.log`.

## Demo association persistence increment — 2026-09-30

Explicit Save/Restore/Forget now preserves strict SDK device associations in a
separate bounded, versioned app-private roster. Reopening restores only the roster;
no device/build choice, review, endpoint, connection or compiler-file capability is
restored. Exact saved evidence is rechecked before catalogue Run reserves a device
or loads the compiler. Stale writes/removals refresh evidence without retry;
active device operations exclude roster mutations. Offline Build remains
independent of missing/corrupt stored device context.

`Tools/verify-demo-associations.swift` passed durable reopen/no automatic selection
or trust, exact/missing descriptor restoration, explicit save/forget (including
orphaned descriptors), preservation of unrelated devices, stale mutation and Run,
review revocation, reservation conflicts, sixteen-record/16-KiB bounds, malformed
and future schemas, duplicate device IDs, invalid SDK records, symlinks,
cancellation and storage failure. Its missing-service stale-Run test confirms
rejection before compiler loading; no network operation is attempted. The first
run exposed review revocation cancelling its own conflict refresh; the controller
now ends the rejected Run state before refreshing and the final checks pass.

The existing catalogue and legacy real-WebKit compiler harnesses, process-wide
device-operation harness and complete-image journal harness passed. Ordinary
package tests passed: 140 discovered in fifteen suites, 133 executed and seven
opt-in WebKit tests skipped. Final unsigned demo builds passed on macOS, generic
iOS Simulator and generic iOS device, with only the existing AppIntents metadata
extraction warning. All source/build/log outputs remained in FirmingoKit.
Commands are in [Tools/ManagedWASM/README.md](../Tools/ManagedWASM/README.md) and
the demo build block above. Public SDK APIs, runtime/service/recipe assets and
firmware contracts did not change; package iOS tests, DocC, JavaScript tests and
all seven opt-in SDK runtime tests were not repeated for this host-only increment.

The user disabled visual inspection. No computer-use, accessibility-tree,
screenshot or running-UI inspection was used in this increment. Layout,
file-picker/keyboard/VoiceOver behavior, signed sandbox, real app restart,
minimum OS, physical iPad and hardware deployment remain unqualified. Legacy
records lack catalogue descriptor provenance and require explicit new reviewed
evidence rather than automatic migration. Corrupt archives are never silently
repaired; explicit reload is required after external correction. Cross-process
file coordination is not implemented. Production resources and redistribution
review remain open.

Pinned reference bytes still match all 38 ArduinoKit and eight Firmingo compiler
reference entries and their committed bytes; checkouts remained read-only.
Exact final host-source hashes and limitations are in
[demo-associations-experiment.json](demo-associations-experiment.json).

Logs: `.build/demo-associations-{harness,catalogue,legacy,coordination,journal}.log`,
associated harness compilation logs, `demo-associations-package-tests.log` and
`demo-associations-{macos,simulator,device}.log`.

## SDK bundled-resource foundation — 2026-09-30

`ManagedCompilerCatalogue.loadBundled()` now verifies SDK-owned inventory/runtime/
license/catalogue bytes without a host import. Its intentionally empty catalogue
contains no production or synthetic firmware descriptor. `ManagedSketchCompiler()`
selects the same resource set, performs no construction-time I/O and currently
fails with `ManagedCompilerResourceError.serviceApprovalPending` before source
preparation or WebKit. Explicit development loading/receipt identities remain
compatible; no automatic fallback exists. Distribution/provenance review and
trusted firmware-build exports still block production bundled compilation.

Eight ordinary resource test functions pass, including strict duplicate/scalar/
role/path/recipe/board/ABI/qualification checks, bounds, exact asset integrity,
missing/symlinked files/roots, review anchoring, malformed/missing service,
cancellation/fresh load and both default build overloads/fresh reentry. The full
ordinary macOS run passes 149 discovered tests in sixteen suites: 141 executed
and eight opt-in runtime tests skipped. All eight opt-in actual WebKit/WASI tests
also pass separately; the new internal test-anchored approved-inventory branch
loads the exact development service and produces the independent known Blink
capsule while preserving recipe/toolchain/descriptor identities. Its temporary
resources and synthetic binding are test-only NEVER DEPLOY inputs; no production
approval override is exposed and no service is staged in the SDK.

The latest iOS 27.0 Simulator run passes 141 tests in fifteen suites. Generic iOS
device compilation, DocC generation and the new resource guide example typecheck
pass. A generated separate SwiftPM consumer successfully discovers the verified
empty catalogue using only this local package, with no imported metadata/service
or sibling dependency. It constructs the default compiler but cannot compile a
bundled firmware choice because none is staged. The unsigned universal macOS demo
archive builds, and read-only verification confirms the inventory, all five roles,
empty catalogue and absent service. Its ManagedCompiler directory is 136067 bytes,
excluding bundle metadata/code; the unstaged service remains 101196044 bytes.
Archive validation is packaging evidence, not signed-host execution. AppIntents
metadata extraction remains a warning, and this first archive check also reports
the demo's existing missing App Category. DocC has no warnings.

Reproduce the new maintenance/consumer checks with:

```sh
python3 Tools/ManagedWASM/update-resource-inventory.py --check
swift test --filter ManagedCompilerResourceTests
swift test
FIRMINGOKIT_WASM_MODULE="$PWD/.build/managed-wasm/compiler-bounded.wasm" \
  swift test --filter ManagedWebKitCompilerTests
python3 Tools/ManagedWASM/make-resource-consumer.py
swift run --package-path .build/compiler-resource-consumer ResourceConsumer
xcodebuild archive -project Demo/FirmingoDemo.xcodeproj -scheme FirmingoDemo \
  -destination 'generic/platform=macOS' -derivedDataPath .build/demo-resource-archive \
  -archivePath .build/FirmingoResources.xcarchive CODE_SIGNING_ALLOWED=NO
python3 Tools/ManagedWASM/verify-resource-archive.py .build/FirmingoResources.xcarchive
```

The iOS test/build and DocC commands are at the start of this document. The new
DocC example was extracted to `.build/resource-examples.swift` and typechecked
against `.build/docc/Build/Products/Debug` with Swift 6/ApproachableConcurrency and
macOS 14 target. An initial broader extraction lacked the host-supplied parameters
required by unchanged lifecycle snippets; the corrected focused new-guide check
passes without warnings. Unchanged examples were not claimed as revalidated.

No visual inspection, device connection, upload, commit, reset or firmware write
occurred. Signed sandbox, physical iPad/minimum OS, actual production bundled
compilation and hardware qualification remain open. Unchanged JavaScript and demo
controller/journal harnesses were not repeated; source/recipe/runtime/service bytes,
managed upload behavior and demo code did not change. All 38 ArduinoKit and eight
Firmingo selected compiler-reference files still match recorded hashes and pinned
committed bytes; reference checkouts remained read-only.
Exact resource/source hashes and limits are in
[compiler-resources-experiment.json](compiler-resources-experiment.json).

Logs: `.build/compiler-resources-{initial,focused,default,runtime}.log`,
`compiler-resources-{ios-tests,ios-device,consumer,archive,docc,examples}.log`.

## Demo SDK resource defaults increment — 2026-09-30

The demo now starts with `ManagedCompilerCatalogue.loadBundled()` and
`ManagedSketchCompiler.verifyResources()`. The public verification API checks
assets without source preparation, WebKit startup or a device; it shares the
compiler's busy reservation, propagates cancellation and does not cache bytes.
Build always revalidates. The current SDK catalogue is empty and verification
throws `serviceApprovalPending`; this increment does not ship a compiler service
or trusted production firmware descriptor.

Compiler and catalogue resource sources are explicitly independent. Optional
imports and legacy mode are under Development resources. Source/file changes
expire output and physical-device review; selecting SDK compilation releases the
old imported service capability. Failed SDK loads never choose a development
fallback. Late startup cannot replace two completed development selections;
cancelled/reloaded metadata cannot publish stale choices or readiness. A loaded
catalogue never selects a descriptor/device or grants upload review automatically.

`Tools/ManagedWASM/VerifyDemoDefaults.swift` exercises these gates using the actual
empty/pending resources plus SDK-validated synthetic metadata and deliberately
late injected callbacks. The injected verifier only exercises host state: an
actual Build still reaches the default SDK verifier and fails pending, without
an artifact or connection. All fixtures are test-only NEVER DEPLOY inputs. The
standalone harness needs the current SwiftPM resource bundle beside its executable;
the reproducible build/run command is in `Tools/ManagedWASM/README.md`.

Validation passes: 149 discovered macOS tests in sixteen suites (141 executed,
eight opt-in tests skipped), all eight actual macOS WebKit/WASI test functions
separately (9.457 seconds), and 141 iOS 27.0 Simulator tests in fifteen suites
(1.612 seconds). The actual-runtime tests include explicit-service verification
and busy rejection. Five demo harnesses pass: default sources, real-WASM catalogue
builds, real-WASM legacy compatibility, saved associations and device-operation
coordination. The catalogue harness explicitly renews review after replacing its
compiler file; it then rejects a stale durable journal before loading that file
or connecting. Ordinary tests also verify cancelled resource checks release the
reservation before a fresh attempt.

Unsigned demo builds pass for macOS, generic iOS Simulator and generic iOS device.
The existing AppIntents extraction warning remains. DocC generation and the
focused updated BundledCompilerResources Swift example typecheck pass. The
example uses a workspace-local module cache; Xcode validation requires its normal
cache/service access. Initial test assertion and harness fixture/bundle issues
were corrected before the final passing runs; no UI inspection was used.

Reproduce the package/runtime checks with `swift test` and
`FIRMINGOKIT_WASM_MODULE="$PWD/.build/managed-wasm/compiler-bounded.wasm" swift test
--filter ManagedWebKitCompilerTests`. Platform and DocC commands are at the start
of this document; controller build commands are in `Tools/ManagedWASM/README.md`.
Logs are `.build/demo-default-{package-tests,runtime,ios-tests}.log`,
`demo-default-{defaults,catalogue,legacy,association,coordination}.log`,
`demo-default-{macos,simulator,device,docc,examples}.log`.

Runtime/recipe/service and packaged asset bytes remain unchanged. Unchanged
JavaScript/WASI, separate-consumer, archive and complete-image journal checks were
not repeated. All 38 ArduinoKit and eight Firmingo selected compiler-reference
files still match their recorded hashes and pinned committed bytes; neither
checkout was written or built. No hardware connection, upload, reset or firmware
write occurred. Service redistribution/provenance review, trusted production
descriptors, signed sandbox/minimum-OS/physical iPad execution, UI/accessibility
and hardware qualification remain open. Exact source hashes and validation limits
are recorded in [demo-default-resources-experiment.json](demo-default-resources-experiment.json).
