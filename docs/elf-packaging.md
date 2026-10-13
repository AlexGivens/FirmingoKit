# Shared supplied-ELF conversion — 2026-10-12

Both `ManagedELFConverter.convert` overloads now delegate ELF validation and FMS1
production to Firmingo-Compiler's isolated service-free worker. Public async APIs,
filenames, capsule/report bytes and schema-one native receipt meanings are retained.
This conversion does not run a compiler or authorize upload.

Legacy provenance still accepts bounded caller-declared recipe/compiler/toolchain
identities. Offline conversion still requires the selected descriptor's exact
recipe identifier/hash; SDK catalogue selection remains pinned. The shared compiler
uses a separate `package_elf` request/declared-packaging-v1 receipt; its real build
pins are unchanged. Declarations do not prove assets or source-to-code association.
Public `compilerReceiptJSON` remains nil for supplied ELF.

Swift captures prepared source/selection, keeps device identity out of portable
input, loads verified source resources and supplies bounded canonical ELF base64
as a data argument to a private WebKit page. The shared worker retains the strict
52-byte–2-MiB stateless Nano ELF subset. Native decoding checks closed fields,
correlation, source/generated/target identities, declarations, ELF/capsule hashes,
input receipt identity and report. Independent native capsule/deployment validators,
associations, capability checks, upload rules and journals remain in Swift.

`ManagedELFImage.swift` and `ManagedELFPackage.swift` are removed. Their original
hashes/byte counts and migrated parser-test responsibilities are in
[the retirement inventory](elf-packaging-retirement.json), at SDK commit
`5465792737054d00302f4f3ad9f51d3734dee034`. Public API/receipt/cancellation and
deployment-boundary tests remain; historical evidence is retained.

Conversion now requires verified shared source resources and WebKit, without a
compiler service. Missing/corrupt resources and host/cleanup failures are explicit;
there is no native parser fallback. Native loading and worker deadlines,
cancellation/disposal and fresh-operation behavior apply. Error categories are
retained; detailed parser wording may differ. Structural packaging does not prove
code authenticity, useful behavior or hardware qualification.

## Identities and actual checks

Source-only export: 50 records, SHA-256
`93f149a454b1fc1c60ea21775b7b860e99b1a4031f8c810fb1f5de3bc18c4fd4`.
SDK runtime manifest:
`d6c7458d085e43d069bda0a16b1e2ed3931c51528118c3ecba862c08dc36cadc`.
Pending eight-role inventory:
`0758bebfdb81c920bab244e31a2d9b4b49aa1d4d697796d1e366f8ee3d7c5ed7`.
The 416780-byte host embeds compiler sources and its classic service-free worker.
No binary is included; the default catalogue stays empty and service review pending.

On macOS arm64 / Xcode 27.0 / Swift 6.4 / Node 22.12.0:

- `node Tools/ManagedWASM/run-validation.mjs <explicit-pinned-service>` passes 152
  tests in 18 suites, including nine actual WebKit/WASM cases; 34 fixture files and
  resource inventory checks pass.
- Existing offline Python receipt goldens pass. The independent legacy input digest
  remains `cf9d3b07f04a8566ca5c63481225681df707e752bbf8eac06bd4ededc65d668a`.
  Arbitrary legacy provenance, repeated identities, UInt64.max and code bounds pass.
- New packaging adapter tests verify actual service-free WebKit output, 21 rejected
  native mutations, malformed/full-image ELF, native deadline and fresh conversion.
  Legacy/offline cancellation and deployment-boundary tests pass.
- A separate `swift run --package-path .build/compiler-resource-consumer ResourceConsumer`
  discovers resources, prepares and converts the non-executable fixture with
  arbitrary legacy provenance, no service and no sibling compiler lookup.
- Unsigned generic iOS Simulator/device and native macOS DocC builds pass with no
  reported warnings; no physical/signed-host execution is inferred.

Compiler checks pass 108 fast cases (one optional memory skip), 4000/5000 JSON/ELF
mutations, eight actual Node/WASM cases and nine Chrome cases. Service-absent Chrome
passes three checks including actual packaging workers and skips six compiler cases.
Source-export recreation compares every byte.

The first full SDK run exposed an outdated expected inventory digest and a test
expecting a wire error for malformed deployment reports. The deliberate resource
change updates the golden; the report mutation now expects existing
`ManagedUploadError` validation. The subsequent full run passes. Logs use ignored
`.build/declared-packaging-*.log` in both checkouts.

CI uses the SDK/consumer production entries; no SDK GitHub run is claimed because
its provisioned Apple runner is absent. Signed/minimum-OS, physical iOS/iPadOS,
trusted resident exports, service provenance/distribution and board deployment
remain open. No firmware executable or device operation changed.

Portable APIs/schemas and the developer command are in
[the Compiler guide](https://github.com/AlexGivens/Firmingo-Compiler/blob/main/docs/declared-elf-packaging.md).

## Commit and CI record — 2026-10-13

The tested SDK adapter is committed at `9e42b255dafd15cab7e4e1bd86ca8c0c470d1253` and the shared compiler
at `9eef0f82b397cd6642d226fc057f8a23eacbc72f`. Both are pushed to main.
[Compiler run 38359879060](https://github.com/AlexGivens/Firmingo-Compiler/actions/runs/38359879060)
has six inspected successful jobs: 108 contract passes/one optional memory skip on
both hosts, 4000/5000 mutation passes and three service-absent browser passes,
including declared packaging. Eight actual runtime cases and six browser compiler
cases explicitly skip there. Log artifacts were finalized. SDK GitHub inspection
confirms zero self-hosted runners and zero workflow runs, so no SDK CI pass is claimed.
The ordinary local SDK run reports 152 tests with its nine actual compiler-service
cases explicitly skipped; service-free conversion remains exercised and passes.
