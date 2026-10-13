# Shared service-free preparation — 2026-10-12

Both public `ManagedSketchPreprocessor.prepare` overloads now delegate lexical
preparation to Firmingo-Compiler through an isolated private WebKit worker.
The SDK's duplicate Swift scanner/masks are removed. Public request/prepared types,
source/revision identity, generated-input layout/hashes, line mapping and existing
receipt schemas retain their meaning. Independent supplied-ELF conversion and
SDK deployment validators remain unchanged in this increment.

Preparation needs the verified SDK source package and a working WebKit host, but
needs no WASM service, service approval, device, source upload or native compiler.
The private origin exposes only the page for this operation: there is no service
resource to fetch. Loading still verifies the pending eight-role inventory; it
does not approve distribution or populate the empty production catalogue. Missing/
corrupt resources and host/cleanup failures now surface explicitly through the
existing async throwing API. Host apps never receive a view or worker object.

## Ownership and limits

Firmingo-Compiler adds `PreparationController.prepare(request,{signal})`, a default
module-worker entry and a classic-worker source export. One controller admits one
operation, without a queue/cache/retry. The captured request's deadline is at most
60 seconds. Cancellation, deadline and worker failure terminate the worker before
settlement; stale/malformed/substituted output fails. The parent recomputes the
expected preparation with the same portable production function and compares each
output field. This does not execute a compiler or establish C++ syntax/ABI validity.

The SDK uses that controller through its trusted Blob-worker adapter. The native
page lifecycle, loading-through-disposal deadline and two-second cleanup watchdog
are shared with compilation. Native parsing checks closed fields, correlation,
request/source/generated hashes, bounded translation unit and line/BOM metadata
before exposing a prepared Swift value. No Swift lexical reimplementation remains.
First-line diagnostic byte columns now include an original three-byte BOM; the
existing portable policy also owns diagnostic text. Source normalization preserves
original identity while separately identifying generated input. Both overloads
preserve UInt64.max through the existing lossless revision token.

Standalone ELF conversion remains a compatibility path: its legacy provenance API
accepts declared recipes beyond the compiler's pinned recipe contract. Migrating
that behavior requires an explicit portable declared-provenance design rather than
silently changing old receipts or weakening the recipe rules. Independent capsule/
report/device validation will remain SDK-owned.

## Imported identities

The updated source-only development export has 49 source records and includes
`preparation-worker.js` alongside compiler/compile-worker/resources/notices/source
archive. Interface one, service ABI two, recipe and service pins are unchanged.

| Identity | SHA-256 |
| --- | --- |
| Compiler source package | `65c40e9f33a6ae2838f19c3a1597d4094374fec827df790c5a72c7480792b3a5` |
| SDK runtime manifest | `edba580f8c47fbe4b7a74b97d57d5e5fb4a3630d5b5d16ce69ad518c0389ae7b` |
| Pending SDK resource inventory | `0ca0c5a50b32674d9656112fbcd22dca82adca79897ff4e5366e86b27301e258` |

The staged page is 376042 bytes. Runtime provenance consequently changes with this
package; original historical receipts and previously recorded package identities
are not rewritten. Export recreation compares every file byte-for-byte from the
shipped maintenance/source inputs. No service binary is added or redistributed.

## Actual local results

- Existing Swift preparation suite: ten tests pass, including exact independent
  source/generated hash vectors, lexical/digit/raw-string masks, line endings,
  unsupported directives, diagnostic limits and early cancellation.
- Full SDK suite with the explicit local service: 153 reported tests in 17 suites
  pass, including all nine actual WebKit compile/link cases. The service-free
  preparation tests include legacy/offline parity, UInt64.max, first-line BOM,
  nine altered-result rejections, deadline/fresh preparation and cancelled caller.
- SDK iOS Simulator/device builds and native DocC pass without documentation warnings. The separate SwiftPM consumer compiles
  the known Blink vector with an explicit service and also prepares source with
  no service. Pending default compiler loading still fails as specified.
- Compiler fast tests: 94 pass, one actual memory-maintenance case explicitly
  skips. Four new actual Node-worker/controller tests cover source/error parity,
  busy/cancellation/deadline, stale/altered replies, disposal ownership/failure
  and fresh operations. Eight real Node/WASM cases pass.
- Chrome service-absent run: three browser cases pass, six actual compiler cases
  skip. Its first case now exercises real module-worker preparation, unsupported
  source, busy/cancellation/deadline/fresh operations without a service.
- Fixture checks remain 34 unchanged SDK files; deterministic resource inventory
  and compiler source-export recreation pass.

SDK reruns use `node Tools/ManagedWASM/run-validation.mjs [explicit-service]`,
`swift test --filter ManagedPreparationAdapterTests`, the existing generic iOS
build destinations, native DocC, and the generated resource consumer. Compiler
reruns use `tools/dev.mjs test|check|test-runtime|test-web`. Ordinary SDK tests now
exercise the real service-free WebKit preparation worker; no binary is required.
CI uses these production paths, with compiler cases without a service explicitly
skipped. Workflow definitions have no verified GitHub run; actionlint was unavailable.

Logs are SDK `.build/shared-preparation-{tests,sdk,sdk-runtime,ios-simulator,ios-device,consumer,consumer-no-service,docc}.log`
and compiler `.build/shared-preparation-{contracts,check,runtime,chrome}.log`.
The earlier no-service full run reported 152 tests before adding the BOM case;
that case is included in the final 153-test explicit-service run.
No hardware, upload, signed sandbox/minimum-OS or physical iOS/iPadOS qualification
is established. All selected residents are synthetic, never deployment inputs.
