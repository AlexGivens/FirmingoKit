# FirmingoKit

FirmingoKit is a Swift package for host apps working with microcontrollers that
run Firmingo firmware. This is an early implementation, not a complete SDK or a
hardware-qualified release.

[Self-contained SDK preparation](docs/compiler-package-provisioning.md) binds
the reviewed compiler to one exact experimental Nano catalogue entry. Prepared
packages support default API use; Git source retains explicit missing-binary behavior.

The [compiler qualification host](docs/compiler-host-qualification.md) passes
actual development-signed macOS sandbox and recorded physical iPad/iPhone checks
with prepared resources. The separate [Nano qualification host](docs/nano-hardware-qualification.md)
now has scoped iPadOS 27.0.1 and iOS 27.0 two-sketch managed-deployment passes,
including exact console bytes and manual GPIO transitions. Other boards, minimum OS and broader
USB/Internet/power-loss qualification remain separate work.

[Initial connection readiness](docs/connection-readiness.md) explains bounded
local-network permission/path waiting and explicit retry after timeout, without
reconnecting an established session or replaying a command.
[Signed read-only results](docs/connection-readiness-qualification.json) record
iPhone first-prompt success and an iPad timeout followed by a successful explicit
retry. [Further USB/routing checks](docs/nano-usb-readonly-checks.md) remain
separately selected and counted.

The agreed repository split assigns preprocessing, WASM execution, board recipes,
ELF/capsule packaging, compiler diagnostics, and static build metadata to
**Firmingo-Compiler**. FirmingoKit owns the Swift compiler facade/web host, device
communication, installation, uploads, device associations, and deployment checks.
**Firmingo** owns device firmware and its resident/protocol contracts. The compiler build facade now delegates to the pinned Firmingo-Compiler package
through a tested macOS WebKit adapter; compatibility preparation/conversion APIs remain;
[the migration inventory](docs/compiler-migration.md) records that transition.

The implemented public operations are **FMGO protocol-one inspection, a live
channel-one serial session, and experimental Nano managed upload**. Connections use an explicitly selected numeric TCP endpoint,
send hello once, and validate the selected board. A session also requires the
expected application or UART backend, explicitly acquires the console channel,
exchanges exact bytes, and releases ownership on close. Framing and JSON validation
are tested against pinned firmware vectors; session behavior is tested with a fake
peer. Managed upload accepts independently built, validated FMS1 capsules with
exact host-known resident binding, stages them in RAM, requires an explicit one-shot
commit, and supports saved-record reconciliation. Complete-firmware local acquisition,
release/UF2 validation, and artifact preflight are also implemented. Experimental macOS ROM programming, one-shot execution, persistable records, and
fresh-hello verification are implemented. Experimental local WASM compilation is implemented with an explicitly supplied
reviewed service; its scoped paired-source distribution review is complete, while
hosted delivery and qualified updates remain pending. No SDK complete-firmware
programming/sandbox pair is hardware-qualified. The scoped Nano/iPad/iPhone managed-upload
result is recorded separately above; an advertisement alone is insufficient to
start an upload.

Offline single-file source preparation and strict stateless Nano ELF-to-FMS1
packaging are available, with source diagnostics and revision/build receipts.
The separate experimental `ManagedSketchCompiler` compiles through an internal
WebKit/WASI worker and returns validated capsules for the exact source revision.
Preparation/packaging alone do not establish source-to-code or hardware compatibility. See [compiler details](docs/compiler.md).

The [managed WASM development workflow](Tools/ManagedWASM/README.md) integrates
Firmingo-Compiler's shared service/recipe/worker through the SDK WebKit adapter.
An explicitly prepared SDK supplies reviewed compiler resources and paired
source/notices; Git source has no binary. Signed/physical compiler hosting and
the scoped Nano managed workflow have separate evidence linked above. The demo
and complete-firmware programming remain separate qualification targets.

The accepted next direction is a [bundled compiler and firmware catalogue](docs/compiler-catalogue.md)
produced by Firmingo-Compiler from verified Firmingo exports and consumed through
FirmingoKit's Swift APIs. Host apps will select supported board/profile/firmware-build
targets and compile offline using approved versioned package resources; deployment will
separately require a real device association. The demo will consume these same
APIs, with file imports retained as an optional advanced path. Bounded catalogue
metadata, immutable firmware-build descriptors and separate persisted device
associations are implemented, along with experimental device-independent compiler
inputs, artifacts and receipts. Default SDK resource-loading APIs now verify a
bounded package inventory and an intentionally empty catalogue; the default compiler
reports pending service review. Production descriptors and approved service packaging
remain open. The demo starts with SDK catalogue/resource checks and reports the
shipped empty catalogue/pending compiler. Explicit verified development providers
and legacy compatibility remain under Development resources; actual development
compilation still requires a selected service and exact metadata. Device review
remains separate from offline Build. Tasks
are in TODO section 7.1.

```swift
import Foundation
import FirmingoKit

let endpoint = try FirmingoEndpoint(address: "192.168.77.1", port: 7420)
let device = try await FirmingoInspector.inspect(
    at: endpoint,
    expectedBoard: .nanoRP2040Connect
)
print(device.deviceID, device.channels, device.targets)

let session = try await FirmingoSession.connect(
    to: endpoint,
    expectedBoard: .nanoRP2040Connect,
    expectedBackend: .application
)
try await session.openConsole()
let reader = Task {
    for try await bytes in session.serialBytes {
        print(bytes as NSData) // Host interpretation; SDK preserves opaque bytes.
    }
}
try await session.sendSerial(Data("hello\n".utf8))
let status = try await session.serialStatus()
print(status.pendingToBackend)
try await session.closeConsole()
await session.disconnect()
_ = try await reader.value
```

Select the actual board. An IP address and self-reported firmware version do not
prove board or installed-image identity; device/boot IDs are self-reported and
unauthenticated in this development protocol. Inspection acquires no serial channel.
A session has one pull consumer and a bounded 4096-byte receive queue; a stalled
consumer closes the connection after 30 seconds. Control requests have five-second
deadlines. `sendSerial` completion means local transport acceptance, not sketch
consumption. A failed partial write is reported as uncertain; no bytes are replayed.

`Package.swift` declares macOS 14 and iOS/iPadOS 17 minimums. Current Xcode builds
and simulator tests do not qualify these minimum runtime versions or any hardware.
The first boards under consideration are Nano RP2040 Connect and Raspberry Pi Pico,
with different firmware artifacts and qualification status. The Nano experiment's
managed target has an experimental SDK uploader for independently built capsules;
the experimental local WASM compiler requires an explicitly supplied reviewed service. Pico has no advertised managed target.

The separate native demo at [Demo/FirmingoDemo.xcodeproj](Demo/FirmingoDemo.xcodeproj)
opens and saves `.ino` documents, presents an editor/status layout, performs
explicit device inspection, and offers a live SDK-backed console with bounded
hex/UTF-8 presentation. Build compiles a current document snapshot; Run builds,
stages, persists context, commits once and offers outcome reconciliation. Select
the reviewed compiler service and import/confirm trusted exact resident metadata
first. Failed, cancelled or edited revisions cannot be deployed. The demo does not implement Arduino restoration; host developers
own any such optional workflow outside this package.

Document windows share a device-operation guard. Deployment rechecks saved managed
context, and stale review/clear requests preserve newer transactions for review.
Pending or unreadable managed context blocks Run and firmware replacement until
an explicit review/clear; offline Build remains available.

**Prepare Firmingo Installation** reviews an explicitly selected trusted release
manifest and UF2 through the SDK. It presents image provenance, affected flash,
board-specific physical steps, and recovery/verification limits while disconnected.
Reviewing a plan performs no device operation. On macOS, the user separately
selects and confirms the physical ROM target, prepares it, and requests installation.
The demo persists operation records before write permission and restores review
context after restart; it never resumes or retries a write automatically. iOS/iPadOS
uses the guided external-computer transfer route. These are experimental APIs with
no actual-board installation or signed-sandbox qualification.

Run `swift test` and `python3 Tools/verify-fixtures.py` from this checkout.
See [development checks](docs/development.md), [firmware compatibility](docs/firmware-compatibility.md),
[compiler status](docs/compiler.md), [demo design](docs/demo-design.md),
[experimental managed upload](docs/managed-upload.md),
[complete-firmware preflight](docs/firmware-lifecycle.md), and
[the implementation checklist](TODO.md) for exact scope and remaining work.
No sibling checkout is needed for a normal build or test.

The [shared compiler adapter](docs/compiler-adapter.md) records its imported package,
receipt compatibility and local tests. Signed sandbox/physical iOS and hardware
qualification, actual resident metadata and service distribution remain open.

Both public preparation overloads now use the shared compiler worker without a
WASM service; [service-free preparation](docs/service-free-preparation.md) records
package identities, compatibility and actual checks.

## License

FirmingoKit is licensed under the [GNU General Public License version 3](LICENSE)
(`GPL-3.0-only`), matching Firmingo-Compiler. Third-party components and imported
fixtures retain their accompanying licenses and notices.
