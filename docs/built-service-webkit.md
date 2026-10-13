# Source-built compiler maintenance hosting — 2026-10-13

FirmingoKit now owns a minimal native macOS WebKit host for Firmingo-Compiler's
explicit development-service qualification. Portable checks, recipes, WASI,
packaging, candidate anchors and output validation remain compiler-owned. The
Swift tool hosts one fixed, awaited test promise from an exact numeric loopback
origin, with a nonpersistent invisible view, isolated content rules, closed
navigation, bounded main-frame messages and a 120-second deadline.

On macOS 27.0 (26A428), arm64, Xcode 27.0 (27A266a), Apple Swift 6.4.0.34.1,
`VerifyBuiltServiceWebKit` builds with Swift 6/ApproachableConcurrency, the macOS 14
deployment target and warnings as errors. Its real address checks accept one
origin and reject ten variants without WebKit execution. The normal SDK validation
entry point also passes (152 test functions, including nine unavailable-service
skips). No production SDK source, resource, manifest, catalogue or pin changes.

Actual opt-in execution uses the 101,194,565-byte source-built development service
with SHA-256 `a7648688ae9e349304c576804367b66b68b22185060a847a2e292675329ca493`.
All nine standard-worker checks pass, including two sketches, three rejected
unsupported builds, repeat/reentry, integrity rejection, busy/cancellation,
deadline/fresh-worker behavior, unchanged production pin rejection and blocked
external requests. GPIO and console capsules are 316/392 bytes. Their ELF/capsule
bytes match Node and Chrome exactly, and the actual firmware validator accepts
the selected CI API `0x10022c9c` while rejecting historical `0x10022ca0`.

Two preliminary runs of the autonomously started hidden page reached the overall
deadline; the second recorded seven successful cases before deadline recovery
stalled. No artifacts were published. Matching the SDK host's existing pattern of
explicitly awaiting the page promise passes all nine checks without increasing
deadlines. This observation supports the native host lifetime choice; it does not
identify a WebKit engine defect. The compiler repository records complete compact
identities and actual commands in `docs/evidence/built-service-web.md` and `.json`.

Instructions are in [the hosting tool guide](../Tools/ManagedWASM/README.md).
The manual SDK workflow now compiles the host and runs address checks; no subsequent
GitHub run is claimed without a provisioned runner. iOS builds and DocC are not
rerun for this macOS-only maintenance tool, which does not enter the package.
Public SDK/private-scheme qualification of the new asset, signed/minimum-OS hosts,
physical iOS/iPadOS, package promotion, custom-source licensing and distribution
remain open. This tool does not bypass consumer pins or establish device execution.
