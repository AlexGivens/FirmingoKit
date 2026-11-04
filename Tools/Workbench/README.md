# Workbench app controller

Run `python3 -I -S -B Tools/Workbench/workbench.py --help` from the SDK checkout.
The controller invokes one explicitly selected signed Workbench macOS app; it does
not implement a compiler, discover a board, deploy an app or contact a device.
See [usage, protocol and limits](../../docs/workbench-consolidation.md).

Run deterministic CLI fixtures with
`python3 -I -S -B Tools/Workbench/test-workbench.py`.

[Compiler lifetime, deadline, stress and mobile scene scenarios](../../docs/workbench-compiler-scenarios.md) use the same app and command engine.

Validate an explicitly exported mobile lifecycle report with `python3 -I -S -B Tools/Workbench/check-mobile-report.py --help`. This reads only the chosen local report and performs no device/launch operation.

[Paired mobile controller](../../docs/workbench-paired-controller.md) documents
`paired.py serve|pair-device|command|sessions|revoke` and manual invitations.
Run `python3 -I -S -B Tools/Workbench/test-paired.py` for socket-free broker fixtures.


[Thin MCP adapter](../../docs/workbench-mcp.md) documents the tools-only stdio
server, client launch configuration, explicit command/run IDs and validated
report collection. Run `python3 -I -S -B Tools/Workbench/mcp-server.py --help`.
Normal offline coverage is `python3 -I -S -B Tools/Workbench/test-mcp.py`;
`check-mcp-interop.mjs --help` describes the separate opt-in official-client check.
The adapter connects only to an operator-selected existing controller.

[Device inspection and exact binary console](../../docs/workbench-device-scenarios.md)
use the same engine with explicitly selected version-two hardware requests.
Compiler version-one requests remain offline. Normal fixtures do not connect to
hardware. `check-device-coordination.py` exercises the real demo operation guards
after the SDK is built, without opening a socket or loading compiler assets.


`check-codex-device.py --help` describes the explicitly selected live native-Codex
host/iPhone check (Python 3.11+). It uses the registered MCP server and a fresh
pairing, creates no model turn or saved chat, and is never executed by normal CI.
[Measured registration/device result](../../docs/workbench-mcp-iphone.json).
The same helper now also records selected Nano inspection/raw binary console on
[iPhone](../../docs/workbench-device-qualification.json) and
[iPad](../../docs/workbench-device-ipad-qualification.json) with the identical
signed build 10. Offline MCP fixtures revalidate both native request/report corpora.


[Managed FMS2 phases](../../docs/workbench-managed-scenarios.md) use closed
schema-three selections and separate staging, one-shot flash commit and fresh
reconciliation. Use the persistent paired CLI/MCP path for live staging phases;
launch-and-exit automation cannot preserve their session. `managed.restore` reads
saved host context only. The opt-in native helper accepts `--managed-action` and
records non-pass results without replay. Fault/ROM workflows remain specialized.
