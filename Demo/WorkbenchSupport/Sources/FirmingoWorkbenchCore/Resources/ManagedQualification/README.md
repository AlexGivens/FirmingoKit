# Fixed Workbench FMS2 qualification inputs

These three resources are data/source for the app-owned test driver, not a
production catalogue promotion, compiler binary or installable firmware image.
The SDK and portable compiler remain responsible for actual compilation and
validation. Repository GPL-3.0 terms apply; no third-party license is replaced.

- `catalogue.json`: exact imported Compiler catalogue SHA-256
  `8b8f1432d40b42502acca728083e5045f09ed493014bbde1786d3fa8aeed13cd`.
  Firmware source/build facts derive from `97be7bbbe29ef1d18ec886ae6eea1a2d41905869`,
  export manifest `90911f7d3684dab4123d36b9a018805cc36ae58cb197c318fe720cb18d434a65`.
  It is the same metadata used by `Validation/NanoHost/NanoCandidate.swift` and
  the recorded `docs/nano-fms2-preparation.json` workflow.
- `state-a.ino`: unchanged `Validation/NanoHost/state-a.ino`, SHA-256
  `d29fd4a8d813140b89a801e244bf87cd40b4e17ba7a795a70dc64fec3084e0e3`.
- `state-b.ino`: unchanged `Validation/NanoHost/state-b.ino`, SHA-256
  `9576804970569a7df57e40a071d4c26fce0907fbe3f312af81ecf146466971f0`.

SDK driver code checks these pins and the historical independently validated
544/548-byte capsule digests before any device connection. The fixed stateful
sources support the existing command-2 binary console test. Metadata/compilation
never establish installed-image attestation or authorize deployment.
