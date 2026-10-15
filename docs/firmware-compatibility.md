# Firmware compatibility

Current explicit FMS2 compiler/upload support and refreshed package identities: [stateful adoption](stateful-adoption.md). Older records below retain their original qualification scope.

## Selected contract

FirmingoKit pins Firmingo commit `f17fdf0301256ba48270230cbf213126e70aa8d0` (FMGO major 1).
Reference files and imported fixtures were read from that committed snapshot on
2026-09-29. Working copies matched their committed bytes. The only local Firmingo
change observed was `AGENTS.md`; it is provisional guidance, outside the protocol
snapshot. Neither reference checkout was modified or built.

The fixture manifest is `Tests/FirmingoKitTests/Fixtures/provenance.json`. It records
upstream paths, byte counts, SHA-256 hashes, and all contract files consumed in this
increment. `Tools/verify-fixtures.py` verifies the local resources without a sibling
checkout. The original Firmingo GPLv3 license is retained with these imported
vectors; no firmware implementation code was copied into the SDK.

## Implemented scope

The separate [Nano qualification host](nano-hardware-qualification.md) now has
scoped hardware evidence for exact Firmware `e0a79d1…`, descriptor `c44d25ef…`,
prepared SDK `4edc6aa…` and signed host build 3 on iPadOS 27.0.1 and iOS 27.0.
Console and GPIO each pass verified RAM stage, one host commit attempt and fresh
boot-confirmed reconciliation; exact 256-byte console echo and manual D13
off-to-on transitions are recorded independently. Earlier failed attempts remain
visible. This does not qualify the complete-firmware installation backend,
broader board/OS/USB matrices, Internet routing, timing, power loss or rollback.

Short-lived TCP hello inspection and a persistent channel-one serial session,
explicit board/optional device-ID matching, bounded terminal-error framing,
strict response JSON and identity/capability validation. A live session additionally
requires the expected application/UART backend, correlates requests, acquires and
releases ownership, preserves binary bytes, and reports status counters. Its sole
reader buffers at most 4096 serial bytes with a bounded backpressure wait; control
requests and incomplete frames have five-second deadlines. Inspection always
closes and acquires no channel. Hello offers 4096 bytes by omitting
`max_payload`, as defined by the firmware default. Unknown additive result fields
are ignored; new backends, protocol majors, auth modes, or changed known limits
require a reviewed contract update. Codec payload negotiation supports 512–65536
peer offers capped at 4096; the public inspector currently uses only 4096.

Release application/UART profiles advertise no targets. Nano `0.1.0-m9exp1`
advertises `nano-managed-v1`, 4096-byte capsules, 1024-byte chunk data, and
`physical-d2-gnd` authorization. The SDK implements local FMS1/report validation,
staging, explicit one-shot commit, abort, and fresh-session saved-record
reconciliation for that exact target. Offline source preparation and strict stateless
ELF-to-FMS1 packaging and experimental SDK WebKit/WASI compilation through the
shared Compiler package are implemented. An explicitly prepared SDK supplies the
reviewed service and exact experimental Nano catalogue; the source checkout has
no compiler binary. Hosted binary distribution remains pending. Synthetic fixture capsules are
non-executable parser inputs and must never be uploaded. There is no Pico managed
target. Application baud controls and device reset are unsupported by firmware.

Hello identifies the board/backend, not an exact ELF or UF2. Identity is
self-reported over unauthenticated development TCP. A firmware version string
cannot supply the exact resident binding required by a managed build. Bonjour
discovery is absent; numeric endpoints must be explicitly selected.

The accepted [bundled catalogue design](compiler-catalogue.md) adds future
compiler-owned assets/recipes and immutable firmware-build descriptors consumed
through SDK APIs. Ownership revised on 2026-10-12 is recorded in
[the migration inventory](compiler-migration.md); current executable resources
still live in FirmingoKit. Static build metadata remains
separate from real per-device associations. It does not change the selected wire
contract or qualification matrix. A bundled descriptor cannot attest installed
ELF/UF2 bytes or enable Pico managed upload; deployment retains fresh capability
and exact resident-association checks. Implementation and evidence remain open.

## SDK support and qualification

Compiler-only host evidence was updated on 2026-10-14: a development-signed
macOS 27.0 sandbox host and a signed iOS app on iPad Pro (11-inch,
3rd generation), iPadOS 27.0.1, and iPhone 15 Pro Max, iOS 27.0, each pass six
actual checks. Physical iPad/iPhone results use the identical signed app and cover
two launches each. Both
exported capsules match desktop vectors and independent firmware validation for
experimental static build `c44d25ef…`; they are not associated with an installed
board. [Host qualification](compiler-host-qualification.md) records exact inputs,
signing, reports and measured limits. Earlier increment records below retain their
historical scope.

| Workflow | Nano/macOS | Nano/iOS+iPadOS | Pico/macOS | Pico/iOS+iPadOS |
| --- | --- | --- | --- | --- |
| Hello inspection | Implemented; Nano fixture/fake-peer tested | Implemented; Nano fixture tested in simulator | API builds; no Pico hello fixture tested | API builds; no Pico hello fixture tested |
| Serial sessions / console | Implemented; Nano fixture/fake-peer tested, no hardware | API and fake-peer tests run in simulator; no device test | API builds; no Pico live test | API builds; no Pico live test |
| Complete-image artifact preflight | Implemented; local synthetic/observed-image validation | Implemented; simulator tests, no physical file-access qualification | Implemented; separate release mapping and observed-image validation | Implemented; simulator tests, no physical file-access qualification |
| Firmingo first installation | Experimental macOS ROM executor; no hardware/sandbox qualification | Direct backend unavailable; guided computer route | Experimental macOS ROM executor; no hardware/sandbox qualification | Direct backend unavailable; guided computer route |
| Firmingo updates / interruption recovery | Persisted records/new explicit reinstall implemented; physical recovery and updates unqualified | Context/hello APIs; computer required to transfer | Persisted records/new explicit reinstall implemented; physical recovery and updates unqualified | Context/hello APIs; computer required to transfer |
| Local WASM managed compilation | Six checks pass in a signed sandbox Release host on macOS 27.0, prepared reviewed service and exact experimental Nano descriptor; no board deployment | Six checks pass twice on physical iPad Pro/iPadOS 27.0.1 and iPhone 15 Pro Max/iOS 27.0 with the same signed Release app; no installed resident/execution evidence | Blocked: no firmware managed target | Blocked: no firmware managed target |
| Managed upload | Experimental implementation; fixtures/fake peers, no hardware | Experimental API/fake-peer tests in simulator; no device qualification | Unsupported firmware combination | Unsupported firmware combination |
| Board hardware qualification of SDK workflows | None | None | None | None |

Build settings target macOS 14 and iOS/iPadOS 17. Current-SDK builds and simulator
tests do not qualify minimum-OS execution, networking permission behavior, USB
access, firmware installation, sketch behavior, or other physical model/OS combinations. Historical
firmware harness evidence is not FirmingoKit evidence.

## Acceptance for this increment

- Independent fixtures match framing at every header/payload split and bytewise/coalesced reads.
- Malformed headers fail before payload collection; decoders remain terminal.
- JSON lexical/schema errors and mismatched identity/correlation prevent a successful inspection.
- Cancellation, deadline, EOF, and rejection close the transport; no reconnect/replay.
- Fake-peer session tests cover ownership rejection, exact/interleaved bytes,
  partial writes, status counters, backpressure, cancellation, and fresh sessions.
- Managed tests check independent begin/chunk/finish/commit vectors, artifact/report
  rejection, exact chunk offsets, one commit, lost replies, failed success envelopes,
  cancelled/timed-out commits, and changed/superseded transaction identity.
- Installation tests cover target/lease/one-shot gates, durable-storage failures,
  partial writes, cancellation, pending-session rejection, saved context and hello
  mismatch without hardware. The native transfer loop is tested with memory writers.
- Package/demo build on Apple SDKs, and deterministic tests run without boards or live networking.
- Compiler-input tests cover bounded immutable revisions, facade-only directives,
  original diagnostic positions and cancellation. Independently hand-authored ELF
  layouts package to the pinned capsule vector and reject malformed tables, loads,
  symbols and nonstateless memory. This is not compiler or hardware execution evidence.

The full first release requires the install → connect → build → upload → confirm
behavior → console → update/recover gates in TODO.md. It is not achieved by this
increment. Nano and Pico recipes, exact-image artifacts, real WASM execution, and
dedicated physical-host/board evidence remain required.

The detailed API and trust boundary are in [managed upload](managed-upload.md).
Complete-image local acquisition, strict unsigned `0.1.0` schema-one release/UF2
validation, and artifact installation-plan review are described in
[firmware lifecycle](firmware-lifecycle.md). This does not establish physical
physical-model identification or qualified installation. Experimental macOS
execution uses explicit host physical confirmation and attachment revalidation,
ordered durable records and one-shot tokens; fresh-hello matching is not exact-image
attestation. Native programming and signed-sandbox behavior remain unqualified.
Additional image/ABI/build/harness reference hashes for this increment are in the
fixture provenance manifest. They were read from the same pinned committed snapshot;
no moving working-tree protocol changes were adopted.

Managed compiler format/linker/facade references are separately recorded in
`compiler-firmware-reference.json`; `compiler-reference.json` pins the ArduinoKit
reference. `compiler-observed.json` identifies provisional ignored GCC outputs
used only for an SDK-local packaging comparison. See [compiler status](compiler.md)
for the narrower API boundary and remaining actual WASM recipe/runtime work.

The experimental development workflow now compiles two stateless Nano sketches
through the real WASI service and validates their ELF/FMS1 locally. Its independent
recipe, isolated Node worker tests and exact identities are recorded in
`compiler-wasm-experiment.json`. The test bindings are synthetic and outputs must
not reach hardware. This does not establish a bundled SDK WebKit compiler,
resident execution, physical iPad or board qualification; Pico remains unsupported.

## Contract reference SHA-256

| Upstream file | SHA-256 |
| --- | --- |
| `docs/protocol.md` | `bea85fa390bb2d072dd8fdf8f845262f2d76f37334bee6c3e9319699dfdf611f` |
| `docs/integration/managed-sketch-sdk.md` | `d6a91790f4b3cef751ca57416acd3e99bb04163f1a0995cb2ce12d2596367bc8` |
| `docs/boards.md` | `56808e196d6edb3e4540399808bf6aebeec3600e58c1a988099cd89348fc69f9` |
| `docs/releasing.md` | `14344d4ddfd59a8eb0ff170d4a4e12ad93f0bdfea9349de3c56a7c43bb46be6a` |
| `docs/development.md` | `a7e38dd375e824403c5b57f018e4ab13e04f21bc532b7546a9cde85cd858379d` |
| `boards/nano_rp2040_connect/baseline.json` | `227cf02f03d35fa36b227fd32be1c5e784f35f89c0be18387e683a42c3c2a23a` |
| `boards/raspberry_pi_pico/baseline.json` | `81acae1b02676f3939cb676de37f36627dc2ed2aae0360b2b8ee148986030335` |
| `src/core/protocol.h` | `567095d2bccd32c9567269a08de51829b6b4d6363bfdd294615498970016fa04` |
| `src/core/protocol.cpp` | `d6cc26fd08340302a45d71277e86c43310e9f4ef8e656977f77bb5f530adb1f0` |
| `src/core/json.h` | `4e02c851c8baf68051ea7b34ebc940492e187e0696f255a0c62eb3fbca75f257` |
| `src/core/json.cpp` | `55f9c37253a1a7f60f19dfcfbd4705117045e74a0f6fb6d5fed35883dd0cfb56` |
| `src/core/session.h` | `97323f38b93d06e4aedfcc689f82bfda6601a9f2ea7ac825e27d83fb20a24665` |
| `src/core/session.cpp` | `b9d88edf3da86eb56a9a593fd8d5f4fc2a6d0cd9cdc01ad7a614cb9039b8126d` |
| `src/core/session_upload.cpp` | `aa7602e1b5278569a3c689a4c9de04887ed49548a261ad7a1b9cd4191c7fadbe` |

The 2026-09-30 SDK compiler increment adds real offline macOS WebKit execution,
verified independent host/worker/recipe/shim packaging, strict native bridge checks,
and demo Build/Run integration with explicit imported resident metadata and saved
managed-upload context. The service stays an external explicitly selected capability
pending redistribution licensing; the ordinary package does not embed it. Real
compiler/controller tests never connect, use synthetic resident metadata and
produce outputs that must never reach hardware. Compilation and structural capsule
validation do not promote any hardware support, installed-image identity, physical
iOS/iPadOS execution or executable resident-ABI qualification. Evidence is in
`compiler-webkit-experiment.json`; exact setup is in `Tools/ManagedWASM/README.md`.
