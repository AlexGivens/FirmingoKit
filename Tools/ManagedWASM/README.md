# SDK compiler hosting and validation tools

Current service/notice/source pins and actual private-origin/fresh-consumer checks
are in [reviewed delivery integration](../../docs/compiler-delivery.md). No binary
is bundled; licensing review is scoped to the exact source-built service.

FirmingoKit wraps the version-one Firmingo-Compiler package. Portable preprocessing,
WASI execution/workspaces, workers, recipes, ELF/capsule packaging, service maintenance
and Node compiler tests are owned by Firmingo-Compiler. The SDK's former standalone
Node compiler and recipe/vendor copies are retired; exact original paths, hashes
and commit are recorded in [retirement inventory](../../docs/compiler-retirement.json).
Historical commands/evidence remain in their dated documents and can be recovered
at that commit; they are not the current development workflow.

The public Swift preprocessing and supplied-ELF conversion APIs remain available
for compatibility. Independent capsule/report/device/deployment validation remains
SDK work. See [shared adapter](../../docs/compiler-adapter.md) and
[retirement evidence](../../docs/compiler-retirement.md).

## SDK validation

Use Node 22.12.0 and the SDK's Xcode 27.0/Swift 6.4 toolchain:

```sh
node Tools/ManagedWASM/run-validation.mjs --help
node Tools/ManagedWASM/run-validation.mjs
node Tools/ManagedWASM/run-validation.mjs path/to/explicit-compiler-bounded.wasm
```

This command checks fixture integrity, committed resource inventory and the full
Swift suite. The first form with no service explicitly skips nine actual WebKit
cases. It ignores ambient service settings: only the optional argument selects a
local service. It performs no compiler-memory transformation, standalone Node
compilation, sibling checkout lookup, downloads or device operations. Subcommand
failure, signal or timeout produces a failing exit status. The SDK CI package job
uses this same entry point; Apple build/DocC jobs remain separate.

The entry point also runs ten qualification generator/runner/stress/lifecycle-report
fixtures and macOS host source type-checking, without compiler assets or an app
launch. The iOS CI build compiles optimized qualification-host objects against
the built SDK using `check-compiler-host.py --ios-products BUILT_IOS_PRODUCTS`.
No app linking, signing or physical execution occurs in that source check.
For explicit signed physical repeated-build and interrupted-run procedures, see
[host qualification](../../docs/compiler-host-qualification.md). The standalone
report checker is `python3 -I -S -B Tools/ManagedWASM/check-compiler-stress.py --help`.
The opt-in idle scene-transition checker is `check-compiler-lifecycle.py --help`;
it requires the exact launch PID and generated host context. Parser fixtures do
not establish physical background/foreground behavior.
`check-active-compiler-lifecycle.py --help` checks the separate explicit host-policy
test: cancel a pending SDK call on inactivity, observe background/return, then
admit a fresh known build. Manual start and actual cancellation settlement are
required; a canceled task returning an artifact fails the check.
Add `--worker` to that checker only for `--qualification-worker-lifecycle` runs:
schema 5 requires the pinned compile-time workload, measured preflight window and
the first source-compilation notification. Verification and entry-wrapper
cancellations cannot satisfy that mode.

Compiler-side commands are `tools/dev.mjs test`, `test-runtime <explicit-service>`,
`build <request> <explicit-service> <new-output-directory>`, and
`bound-service <explicit-original> <new-development-directory>` in that repository.
They are never invoked implicitly by SDK or consumer builds.

## Explicit package maintenance

`PortableHostBridge.js` is only the native WebKit adapter. It uses imported compiler
code for builds, preparation and service-free supplied-ELF packaging; it does not parse ELF or produce capsules. To intentionally import a reviewed source
export, select its directory and independently trusted manifest SHA-256:

```sh
node Tools/ManagedWASM/stage-sdk-runtime.mjs path/to/export TRUSTED_MANIFEST_SHA256
python3 Tools/ManagedWASM/update-resource-inventory.py
python3 Tools/ManagedWASM/update-resource-inventory.py --check
```

Staging checks bounded files, exact hashes/roles and script syntax, then creates the
SDK page/source/notices/runtime manifest. It does not fetch a service or approve
its distribution. Import service/source notice documents separately with
`stage-sdk-service-review.mjs <paired-delivery> <trusted-manifest-sha256>`; this
verifies all payloads before copying four documents, never the binary/archive.
Review the printed identities and deliberately update compiled-in
runtime/package/inventory anchors when changing imported bytes; these commands do
not update Swift anchors automatically. Normal builds use committed resources only.

## Independent SDK capsule validation

`VerifyCapsules.swift` now reads explicit capsule, report and resident-binding files.
It verifies the real SDK deployment parser without repackaging an ELF or generating
receipts. Bounded regular-file inputs are required. It never connects or uploads:

```sh
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -parse-as-library -target arm64-apple-macos14.0 -I .build/out/Products/Debug \
  Tools/ManagedWASM/VerifyCapsules.swift .build/out/Products/Debug/FirmingoKit.o \
  -o .build/managed-wasm/verify-capsules
.build/managed-wasm/verify-capsules path/to/capsule.fms path/to/report.json path/to/resident-binding.json
```

Adjust module/object paths for another Xcode layout. `VerifyWebKit.swift` embeds
three synthetic test sketches and accepts one explicit service path; it no longer
needs old Node-generated files. It tests actual SDK/WebKit compilation and syntax
errors. A command-line host must receive the current SwiftPM resource bundle next
to its executable; normal app consumers receive it automatically. Prefer the Swift
Testing suite for routine checks. `VerifyDemoBuild.swift`, `VerifyDemoCatalogue.swift`
and `VerifyDemoDefaults.swift` remain host-controller checks; they do not connect
or deploy, and their original commands/evidence remain in `docs/development.md`.

`make-resource-consumer.py` creates a separate local SwiftPM consumer under `.build/`
for bundle discovery, service-free preparation/ELF conversion and optional explicit-service compilation; `verify-resource-archive.py`
checks an explicitly selected unsigned demo archive's current resources. Archive,
signed sandbox and physical-device checks must be recorded separately when run.

All compiler test bindings are synthetic and their capsules must never reach
hardware. The exact source-built service/source/notice delivery is reviewed. Verified production resident exports,
signed/minimum-OS and physical iOS/iPadOS execution, and hardware deployment remain
open. Removing duplicate tools establishes ownership, not those capabilities.

## Explicit source-built asset qualification host

`VerifyBuiltServiceWebKit.swift` is a maintenance-only native host for the compiler
repository's fixed standard-worker checks. It does not import the SDK module or
change its public service acceptance. Build with Xcode 27.0/Swift 6.4:

```sh
mkdir -p .build/owned-service-webkit
xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
  -warnings-as-errors -parse-as-library \
  -module-cache-path .build/owned-service-webkit/cache -target arm64-apple-macos14.0 \
  Tools/ManagedWASM/VerifyBuiltServiceWebKit.swift \
  -o .build/owned-service-webkit/VerifyBuiltServiceWebKit
.build/owned-service-webkit/VerifyBuiltServiceWebKit --check-inputs
```

The real address checks accept one exact numeric loopback origin and reject ten
external/ambiguous variants without launching WebKit. To run actual compilation,
explicitly pass this executable to Firmingo-Compiler's `test-built-webkit`, along
with its candidate service, trusted digest, selected resident descriptor and new
output directory. The compiler tool supplies the ephemeral origin and report path;
no ordinary build searches sibling checkouts. Direct host syntax is
`VerifyBuiltServiceWebKit http://127.0.0.1:PORT/ new-report.json`, with an existing
output parent and a new `policy` subdirectory. The compiler driver cleans its
isolated temporary policy/report directory after success or failure.

The host never displays a window or inspects UI. It bounds navigation, resources,
progress/report messages and lifetime, and explicitly awaits the fixed page
operation. The compiler caller independently checks results before publishing
ELF/capsule files. This is macOS HTTP-loopback maintenance evidence, separate from
public SDK/private-scheme, signed sandbox, minimum-OS and physical iOS/iPadOS
qualification. No device is connected or changed. The manual SDK CI definition
compiles this tool and runs `--check-inputs`; it deliberately does not fetch a WASM
candidate or depend on a sibling compiler checkout.
