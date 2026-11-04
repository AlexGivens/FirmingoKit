# Workbench managed report corpus

These are original app-owned reports, checked paired replies and native Codex MCP
submission/report envelopes from the selected build-11 iPad workflow. They are
parser evidence, not instructions to operate a device. Exact byte counts/digests,
producer identities, request scope and expected failed/unknown outcomes are in
[the qualification ledger](../workbench-managed-ipad-qualification.json).

`Tools/Workbench/test-mcp.py` revalidates the corpus through the production report
checker without a listener, app, compiler execution or board. It rejects scope
changes and preserves the original local refusal and bootChanged uncertainty.
The two extracted capsule files are actual fixed SDK/WASM outputs, independently
accepted by Firmware's native FMS2 validator. Their sources/pins remain in
`Demo/WorkbenchSupport/Sources/FirmingoWorkbenchCore/Resources/ManagedQualification`.
They are specific to the reviewed experimental Nano resident; this corpus is not
a general firmware distribution or a claim of production support. The native
checker did not execute ARM code. See the ledger for physical behavior evidence.

Historical failures, reports and host identities are immutable data. Add new run
files and ledger entries for fresh qualification instead of overwriting them.
