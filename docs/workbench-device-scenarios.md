# Workbench device inspection and binary console

Started 2026-11-04. Test Lab, the macOS launch CLI and paired MCP control now
invoke the same two device scenarios through public FirmingoKit APIs. They need
no compiler resources, firmware catalogue selection or resident association.
Managed upload, reset, installation and ROM recovery remain separate workflows.

| Scenario | Required selection | Actual operation |
| --- | --- | --- |
| `device.inspect` | Private IPv4, board ID, stable device ID | Short-lived SDK hello inspection and disconnect; no channel acquisition or payload write. |
| `device.console-binary` | Same selection, separately observed boot ID, fixed probe mode | Fresh identity/backend/boot check, console acquisition, one probe, exact reply comparison, acknowledged close and disconnect. |

Use a board already running a compatible echo application, with REC and upload-arm
jumpers disconnected. `raw-256-v1` sends bytes 0 through 255 once. The explicit
`fms2-command-2-v1` mode sends command byte 2 followed by those same 256 bytes to
the existing stateful qualification sketch. Select its actual application
protocol; this runner never installs a sketch or guesses by sending probes.
Both modes expect exactly bytes 0 through 255. No text decoding, line-ending
conversion or startup-byte filtering is allowed.

The endpoint must be canonical RFC1918 numeric IPv4; the SDK port is fixed at
7420. Board and device identities are explicit, never discovered from an IP.
The SDK currently recognizes Nano RP2040 Connect and Pico selections; selecting
a board does not qualify it. Start physical qualification with the Nano.
Hello reports capabilities and a boot ID, not installed-image attestation.

## Manual use

Open Test Lab in the existing Workbench app. Enter the endpoint, expected board
and stable device ID under **Selected device test**, then run **Inspect selected device**.
Successful inspection copies its boot ID into the selected test fields. Review
the existing application's binary protocol, choose the fixed probe and enable
**Authorize this fixed binary probe**, then run **Exact 256-byte binary console**.
Changing selection, boot or probe expires manual authorization. Input labels,
current run events, actual hello metadata, byte counts and cleanup observations
remain visible. No catalogue load is required for either device scenario.

## CLI and MCP

The existing launch CLI accepts `--device-address`, `--device-board` and
`--device-id` on these scenarios. The console case additionally requires
`--device-boot-id` and `--console-probe`. The paired `command --action run`
accepts the same flags and uses the shared app dispatcher. Use a new run UUID;
query an uncertain command by its original command ID instead of repeating it.

Example MCP inspection submission:

```json
{
  "session_id": "EXPLICIT_SESSION_UUID",
  "command_id": "FRESH_COMMAND_UUID",
  "action": "run",
  "run_id": "FRESH_RUN_UUID",
  "scenario_id": "device.inspect",
  "device_address": "192.168.77.1",
  "device_board": "nano_rp2040_connect",
  "device_id": "5031503337360009"
}
```

Collect the report with the same device selection as expectations on
`workbench_result`. For `device.console-binary`, also supply
`device_boot_id` from that successful inspection and `console_probe` set to one
of the modes above. Probe selection explicitly authorizes that one fixed
application write. Status/cancel commands take only the exact run UUID; they do
not accept device options or replay payloads. No arbitrary bytes, ports, source,
shell, reset or upload command is exposed. [MCP flow](workbench-mcp.md).

`check-codex-device.py --help` documents the opt-in native Codex-host helper.
Supply `--device-address`, `--device-board`, `--device-id` and no build descriptor
for inspection only. Adding `--console-probe raw-256-v1` runs inspection followed
by the console check using its freshly observed boot. It records original host
requests/replies without a model turn or saved chat. Use a new output directory
and an already paired selected app; the helper neither deploys nor pairs it.

## Versioned evidence and failure behavior

Device requests/reports use schema **2**, with a closed nested `device` object:
`address`, `boardID`, `deviceID`, and console-only `bootID` / `consoleProbe`.
Device requests reject `firmwareBuildID`. Schema **1** compiler requests and
reports retain `deviceOperations: false`; hardware options cannot upgrade them.
The outer paired command/result envelope remains version one. Version-two reports
set `deviceOperations: true` and retain the exact selection, self-reported hello,
probe intent, accepted send count, bounded received bytes, first differing byte,
close acknowledgement and completed disconnect. They cannot carry compiler
artifacts or compiler exercise evidence. Both app and controller validate scope
and terminal assertions before publishing/accepting a pass.

Durable admission precedes SDK I/O, and probe intent is saved before sending.
Missing/failed journal gates stop later work. A failed or uncertain send is never
retried; cancellation cannot recall bytes already sent. The SDK owns the initial
five-second connection/hello deadline. Console reading has a separate five-second
absolute limit and retains at most 257 bytes, including partial replies on failure.
SDK cleanup runs on every acquired session. Backgrounding cancels an owned device
run; an inactive permission alert alone does not cancel its original deadline.

The demo's shared operation lease prevents overlap with installation or Run in
another window. Read-only inspection can run while an unresolved managed
transaction exists; the binary write cannot. SDK channel ownership still applies:
a busy channel is an error, never stolen. This is a short fixed integrity check;
it does not measure throughput, detect arbitrarily delayed trailing bytes, prove
electrical behavior or qualify a reconnect/soak/USB-authorization matrix.

## Validation and work log

The ordinary SDK validation passed locally: 166 SDK tests discovered (ten opt-in
runtime cases skipped), eight ROM-host tests, and 30 Workbench tests discovered
(one opt-in TLS case skipped). CLI, paired and MCP fixtures passed 17 / 11 / 17
cases at the implementation checkpoint; a subsequent native corpus fixture brings
MCP coverage to 18 cases. Five new Swift cases cover closed versioned selection, compiler-independent
execution, exact bytes/boot/cleanup, failed persistence and background cancellation.
The real demo coordination harness passed active-operation exclusion, pending
transaction inspection and blocked console writes alongside its existing guards.
It now runs from `run-validation.mjs` through `check-device-coordination.py`.

Complete unsigned Release Workbench builds passed on macOS, iOS device and iOS
Simulator. Pinned official modern/legacy MCP clients passed local Unix-socket
interoperability using archived compiler reports with adapter 0.2.0. The initial
sandboxed socket/build attempts were blocked; successful reruns used the normal
local socket/Xcode environment. No compiler asset or firmware source changed.
The final normal validation entry point, including the integrated coordination
harness, also passed before hardware testing. CI definitions cover the new
fixtures/coordination entry point and platform builds;
no remote CI success is claimed. Native UI/accessibility inspection remains
disabled. Fresh signed-app/Nano MCP qualification is recorded below. Legacy hardware
hosts remain available for unmatched scenarios.


## Physical iPhone and Nano — 2026-11-04

[Exact qualification ledger](workbench-device-qualification.json) retains the
clean SDK commit `fce04293111027983b8c00c1923b4784d92ffc90`, reviewed package
anchor, prepared inventory, signed executable identity and original native MCP
admission/report envelopes. One Workbench build 10 process (PID 36087) on iPhone
15 Pro Max/iOS 27.0.1 (24A446) passed both compiler regressions, selected Nano
inspection and the exact raw binary console check. Mac development/control used
Wi-Fi while the selected Nano occupied the phone's USB port. No Test Lab test
buttons were needed. The user confirmed firmware was unchanged since recovery.

Inspection matched device `5031503337360009`, Nano board ID, protocol 1,
self-reported firmware 0.1.0, application channel, boot `97cff0c9de0cee5f` and no
upload targets. It acquired no console and sent no probe bytes. The separate
console run rechecked that boot, sent 256 bytes once and received every expected
byte exactly, including NUL and values above 0x7f. Close was acknowledged and
SDK disconnect completed. Both first attempts passed without reset, retry,
installation or firmware changes. Prior ROM recovery evidence remains separate;
this hello does not establish a new installed-image hash or attestation.

Native MCP revocation passed afterward, and the owned controller was stopped.
The phone is released and work is paused at the user's request. Eighteen MCP
fixtures pass with archived native request/report scope and byte verification.
iPad/Pico, the FMS2 command-2 mode and physical busy/path-loss/background/deadline
cases are not qualified by this run. Guarded upload/ROM recovery migration and
unmatched legacy-host retirement remain future work.


## Physical iPad follow-up — 2026-11-04

[Separate iPad ledger](workbench-device-ipad-qualification.json) records the
resumed qualification using the identical previously signed build 10 executable
`f587aadf8492e1897b10e74aa476eb8192e690941eb4a33f634e55339f7ca7a1`.
Its clean source remains `fce04293111027983b8c00c1923b4784d92ffc90`; no rebuild,
compiler asset change or firmware change was needed. The 11-inch iPad Pro
(3rd generation), iPadOS 27.0.1 (24A446), was updated/launched over Wi-Fi and
paired with a fresh pinned controller. An initial CoreDevice metadata query
failed before deployment; after the user made the iPad ready, it succeeded.
That host-availability failure was not a Nano test or a passed observation.

The user connected the unchanged Nano with D2/REC disconnected. Native Codex MCP
then ran both scenarios successfully on their first attempts in iPad PID 6417.
Inspection matched stable device `5031503337360009`, protocol 1, application
channel, self-reported firmware 0.1.0 and boot `a748781e607366f1`, with no
advertised upload target. The separate console check required that newly observed
boot, sent bytes 0–255 once, received all 256 exactly and acknowledged close before
SDK disconnect. No Test Lab test buttons, reset, upload or installation were used.
The reports retain the exact reply bytes, original native admission/report
requests and responses, and independent session/run/producer identities.

MCP revocation passed and the owned controller was stopped. The existing Codex
registration now selects its r3 state/evidence paths, preserving all unrelated
settings. Future runs need a fresh controller and pairing. The 18-test MCP suite
passes with both iPhone and iPad corpora, including identical signed input and
independent producer selection. CI already runs this suite through the normal
entry point; no remote CI pass is claimed. No app/SDK source changed in this
follow-up, so builds and unrelated runtime suites were not repeated.

The raw application path now has separate iPhone and iPad evidence. FMS2 command-2
mode, Pico, physical busy/path-loss/background/deadline cases and guarded
upload/ROM migration remain open. Hello is not installed-image attestation;
no fresh flash readback, first-authorization/cold-attachment matrix, Internet
coexistence, throughput, soak, minimum-OS or UI/accessibility result is claimed.
