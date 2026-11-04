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
cases. Five new Swift cases cover closed versioned selection, compiler-independent
execution, exact bytes/boot/cleanup, failed persistence and background cancellation.
The real demo coordination harness passed active-operation exclusion, pending
transaction inspection and blocked console writes alongside its existing guards.
It now runs from `run-validation.mjs` through `check-device-coordination.py`.

Complete unsigned Release Workbench builds passed on macOS, iOS device and iOS
Simulator. Pinned official modern/legacy MCP clients passed local Unix-socket
interoperability using archived compiler reports with adapter 0.2.0. The initial
sandboxed socket/build attempts were blocked; successful reruns used the normal
local socket/Xcode environment. No compiler asset or firmware source changed.
CI definitions cover the new fixtures/coordination entry point and platform builds;
no remote CI success is claimed. Native UI/accessibility inspection remains
disabled. Fresh signed-app/Nano MCP qualification is pending, so historical Nano
passes do not qualify this new path. Legacy hardware hosts remain available.
