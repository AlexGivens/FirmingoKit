# Workbench app controller

Run `python3 -I -S -B Tools/Workbench/workbench.py --help` from the SDK checkout.
The controller invokes one explicitly selected signed Workbench macOS app; it does
not implement a compiler, discover a board, deploy an app or contact a device.
See [usage, protocol and limits](../../docs/workbench-consolidation.md).

Run deterministic CLI fixtures with
`python3 -I -S -B Tools/Workbench/test-workbench.py`.
