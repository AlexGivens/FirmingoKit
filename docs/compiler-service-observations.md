# Observed compiler-service behavior

On 2026-09-29, FirmingoKit's SDK-local development runner consumed the actual
ArduinoKit ABI-two WASI service from pinned reference
`0eb3cd1841147dfc7ea25bf076545e38b01601e4`. No reference code/build state was changed.
The original binary identity is recorded in `compiler-wasm-experiment.json`.
These are observed binary behaviors, not proposed firmware changes or changes to
the selected FMGO contract.

For prepared source `void setup() { missingFunction(); }`, the compile export
returned **zero** while its diagnostic buffer contained a frontend error. Blind
status-only orchestration proceeded to wrapper compilation/linking, which failed
because the source object did not exist. The runner now inspects diagnostics at
each phase and treats any error as terminal even with zero status, preserving the
actual status instead of inventing a nonzero return. The real-service regression
asserts that only the source compile phase occurs and no ELF is returned.

The same error reported `/workspace/Sketch.cpp:3:16` although the generated source
contains `#line 1 "Syntax.ino"` and its excerpt shows original line one. The
runner remaps only that exact physical workspace path by subtracting the two
known prefix lines; already source-named presumed locations are left alone.
The real-service regression expects `Syntax.ino`, line 1, column 16.

The service also emits source/caret lines despite the selected no-caret flags.
These unmatched diagnostic lines are retained as notes, not discarded. Compiler
option/diagnostic handling inside the binary needs source/build provenance review
before production qualification. The current defensive host gates do not claim
the service implements every advertised return/location convention correctly.

The reference binary defines wasm32 memory with minimum 384 pages and **no
maximum**. A checksummed maintenance copy adds maximum 4096 pages (256 MiB),
changing only the memory section declaration and its length. Runtime loading
rejects absent/excessive maximums. The original and derivative are separately
identified; all successful/negative worker tests pass using the derivative, and
both produce the same observed ARM ELF/capsule digests. This caps linear memory,
not total JavaScript/JIT/process memory.

The Console recipe also demonstrates LLD's `.text` flags `0x36` after readonly
string sections are folded into executable `.text`; Blink without strings uses
`0x06`. Both retain readonly/executable LOAD mapping and stateless memory.
SDK parsing accepts those two explicit variants and rejects writable/other flags.
The [LLD linker-script policy](https://lld.llvm.org/ELF/linker_script.html) describes
how output sections combine inputs; the exact emitted metadata is established by
these pinned-module observations. General ELF or conventional firmware conversion
is still unsupported.

No sketch, capsule, upload, console or programming operation was executed on a
board. No firmware-agent coordination was sent. At that increment, WebKit and physical iPad execution
remained open. On 2026-09-30, actual SDK macOS WebKit tests reproduced the successful
capsules, mapped syntax errors and passed cancellation/overlap/deadline recovery.
The initial page policy explicitly needed `wasm-unsafe-eval` for WebAssembly
compilation; the staged policy now allows WASM while retaining its private local
resource/worker restrictions. Physical iPad, signed sandbox, minimum OS, hardware
and custom-service redistribution/license qualification remain open. See
`compiler-webkit-experiment.json`.
