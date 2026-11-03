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
