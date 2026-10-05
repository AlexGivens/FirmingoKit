# Firmware requests for the FirmingoKit packaged compiler workflow

Prepared 2026-09-30 against Firmingo commit
`f17fdf0301256ba48270230cbf213126e70aa8d0`. This is a request for the firmware
maintainer, not a claim that these deliverables exist or are qualified. No firmware
files were changed, firmware tools run, or hardware accessed from FirmingoKit.

## Copyable request to the firmware agent

Please provide the following firmware-side deliverables, in priority order, to
support FirmingoKit's SDK-owned catalogue and local WASM compiler. Start with the
experimental Nano RP2040 Connect application backend and `nano-managed-v1`.
Inspect existing implementations before adding features; reuse or extend them
where they already satisfy the requirement. Keep experimental and measured
hardware support separate. Compilation and SDK resource staging remain owned by
FirmingoKit; do not implement a second host compiler in Firmingo.

### 1. Export one exact managed-capable firmware build

Add an explicit, non-flashing export command for a selected existing build, or
extend the current handoff tooling. The existing contract ZIP deliberately has
no ELF, UF2 or executable module; it cannot supply the SDK catalogue's build facts.
The ordinary beta release also does not establish a managed target.

Include:

- The exact resident ELF and supported complete installation UF2; distinguish
  resident-only and composite images if both are provided.
- Original resident/composite build reports, a versioned manifest with file byte
  counts/SHA-256, full source commit, relevant source hashes, pinned build inputs,
  toolchain/core versions and reproducible commands.
- Actual board, application backend, firmware version, resident ABI, API table
  symbol/address/size, upload target ID, capsule format and size/chunk limits.
- The matching ABI/facade/linker/image contract, licenses/redistribution terms,
  and references to evidence for this exact build.

Derive ELF identity and API symbol from actual files. Verify report/artifact/source
consistency before exporting; reject absent files, mismatched reports, wrong board
or version, partial builds and ambiguous image selection. Record provisional local
changes explicitly or require a committed source snapshot. Export to a new
destination, without connecting, flashing or publishing. Test corrupted/mismatched
inputs, duplicate/unsafe archive paths and reproducible output where supported.

Acceptance: the SDK can independently verify the archive and derive a real
descriptor without dummy hashes, sample API addresses or a live device. Firmware
exports native build facts; FirmingoKit adds its own compatible recipe identity
and catalogue content ID. Do not copy synthetic SDK fixture values into releases.

### 2. Publish a versioned managed ABI and image compatibility contract

Consolidate the current ABI/image/facade/linker requirements into a checksummed,
versioned handoff: struct layout and calling convention; supported functions and
pin mappings; flash slot and memory bounds; entry point rules; alignment, digest
and reserved-byte validation; forbidden writable globals, runtime helpers and
libraries; cooperative setup/loop return requirements; physical authorization.

Define which firmware changes preserve module compatibility, which require a new
descriptor or ABI/format version, and what old installed modules experience after
a firmware update. Explain exactly what each UF2 hash identifies and what changes
after a managed slot update. Keep the stable resident binding distinct from the
initial composite's whole-image digest; do not imply the latter still describes
current flash after uploading another sketch.

Acceptance: documentation, implementation and vectors agree; mismatched ABI,
address, entry points, bounds and capsule integrity have deterministic rejection
tests. Preserve existing compatible protocol behavior or explicitly version a
change and provide an SDK migration handoff before relying on it.

### 3. Qualify SDK-produced Clang/LLD capsules against that resident

Accept independently supplied FirmingoKit artifacts and receipts for this exact
resident. First add offline contract/validation checks; when hardware operations
are separately authorized, execute two supported sketches through FMGO and verify
LED/timing and exact console behavior, replacement, startup and cold replug.
Compare the SDK Clang/LLD path with the existing GCC proof rather than treating GCC
evidence as Clang qualification. Cover the exposed facade calls and record limits
of any calls or pins not exercised.

Acceptance: retain exact resident, source, module, report and toolchain hashes plus
test results. Exercise wrong ABI/API-address inputs and the SDK's independent
resident-hash mismatch gate before slot writes; do not claim the capsule format
alone attests to an exact resident ELF.
Structural validation, `installed`, `boot_confirmed` and useful sketch behavior
are separate outcomes. Do not change firmware merely to accept a malformed SDK
artifact; report any genuine SDK/firmware incompatibility for coordinated repair.

### 4. Validate the Nano FMGO connection path on physical iPad

When equipment and authorization are available, qualify the exact managed image
with the intended iPad/cable/hub and application network backend. Record iPadOS,
board revision, firmware hash, addressing, authorization denial/success, exact
console bytes, reconnect, two uploads, sleep/wake, cold attachment and simultaneous
Internet access. Diagnose firmware DHCP/NCM/session issues and provide log-based
evidence. Existing local-only or older firmware evidence is not this qualification.

Acceptance: document supported combinations and unresolved limitations. The SDK
still performs local compilation; the firmware does not need a compiler. Do not
require screenshots or UI inspection for this handoff.

### 5. Close interrupted-operation and installation-contract gaps

Extend existing tests/evidence for authorization withdrawal, disconnects, lost
commit replies, reboot, superseded transaction records, nonreturning sketches and
interrupted erase/write. Physical power-cut tests need separately authorized board
access. State flash regions/data affected, resident/sketch survival, which outcomes
remain unknown, and the exact supported Firmingo reinstall/recovery procedure.

Acceptance: transaction state, `slot_touched`, readback and startup semantics stay
consistent with the protocol. Never imply a lost response authorizes commit
replay, a file copy proves installation, or interrupted flashing guarantees
rollback. Provide corruption/error/interruption vectors that SDK tests can consume.
Keep complete Firmingo installation separate from managed upload. Do not add
Arduino restoration requirements or assets.

### 6. Define future identity and board work without blocking the Nano export

Assess an additive self-reported resident build ID or capability fingerprint that
maps to the exported metadata. If useful, propose its schema and compatibility
tests before implementing it. Use a non-circular build identifier rather than
requiring an ELF to embed its own final SHA-256. Such reporting can detect obvious
mismatches; it is not cryptographic image attestation and does not replace trusted
installation or explicit existing-device evidence.

Keep Pico managed support unavailable until it has its own resident layout,
ABI/recipe, capability advertisement and board-specific evidence. Do not advertise
Nano managed capability merely because both boards use RP2040. Pico porting,
broader Arduino libraries and larger/stateful modules are later milestones.

## Requested return package

Return the source commit, export command, checksummed artifact bundle, contract
version, validation results and remaining blockers. Mark each board/profile/platform
result as implemented, experimental, qualified, unsupported or blocked. Provide
machine-readable provenance and human-readable limitations. Do not publish, flash
or perform destructive tests solely because this request describes those future
qualification tasks; obtain the applicable explicit hardware/release authorization.

The first acceptance milestone is a verified Nano resident export that FirmingoKit
can turn into one experimental catalogue entry. Compiler-service redistribution
and SDK packaging are separate FirmingoKit/ArduinoKit-owner tasks; the firmware
agent is not being asked to resolve ownership of that service.

## Reference snapshot

The selected compiler-contract hashes remain recorded in
[compiler-firmware-reference.json](compiler-firmware-reference.json). In particular,
the managed SDK integration guide's SHA-256 is
`d6a91790f4b3cef751ca57416acd3e99bb04163f1a0995cb2ce12d2596367bc8`.
The current firmware guide already covers FMGO upload/reconciliation, physical
authorization, constrained GCC proof builds and a protocol-only contract exporter;
the requests above extend and qualify those foundations.

The accepted SDK design and acceptance order are in
[compiler-catalogue.md](compiler-catalogue.md). This handoff does not change the
pinned SDK protocol, introduce a new firmware operation, qualify hardware, or
authorize writes to the reference checkout.
