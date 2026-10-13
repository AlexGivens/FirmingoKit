# Firmingo demo instructions

The root AGENTS.md remains authoritative for SDK boundaries and reference safety.
This is a separate document-based macOS/iOS/iPadOS host consuming the local package.

The user disabled visual inspection. Do not inspect the running UI or screenshots,
and do not request permissions to restore that capability. Use source review,
controller harnesses and builds; retain honest UI/accessibility qualification limits.

- Keep Swift compiler hosting, protocol, device ownership, upload, and firmware
  lifecycle logic in FirmingoKit. Portable compiler execution, preprocessing,
  recipes, packaging, diagnostics, and static metadata belong to Firmingo-Compiler;
  consume them through SDK APIs. The demo owns documents, source selection, and UI.
- Follow docs/demo-design.md. Expose only implemented SDK operations; explain
  unavailable workflows without false success, simulated progress, or fallback builds.
- Implement the accepted bundled-resource flow described in ../docs/compiler-catalogue.md
  when that scope is requested. Board/profile/firmware-build choices and availability
  must come from SDK catalogue APIs. The compiler produces static resources/recipe
  compatibility; the SDK loads them and checks device deployment. Existing bytes
  remain SDK-local until the migration in ../docs/compiler-migration.md passes.
  SDK-filtered selection and offline Build now work with
  SDK-owned default metadata loading/resource verification or explicitly imported,
  hash-verified development catalogues. The shipped catalogue is empty and compiler
  review is pending; never add synthetic default entries to remove those limits.
- Normal offline Build must not require compiler-file import, a connected board,
  fabricated device identity, or confirmation that an unconnected board runs an image.
  Default SDK loading now exists; keep compiler/catalogue imports and legacy mode
  in the optional Development resources path, with explicit independent providers.
- Before Run, present the real device's firmware association and missing/mismatched
  evidence; bundled metadata alone never establishes installed-image identity.
  Preserve current revision checks, durable context, one commit, uncertainty and
  cross-window guards. Keep unsupported Pico managed Build/Run unavailable.
- The catalogue path uses a build-board selection independent of device/endpoint
  settings. Do not require device review for offline Build. Keep the legacy combined
  record flow as an explicit compatibility mode; do not silently fall back to it
  when a catalogue or association import fails. Failed SDK loading never falls
  back to a previously imported file. Provider changes release unused service
  capabilities and expire output/review; SDK setup readiness is an observation
  and every build must independently verify again. Anchor/board/descriptor/mode changes
  expire selection/output as appropriate; imported evidence never grants review.
- Use native document/window/toolbar/navigation conventions, a resizable macOS
  editor/status split near two-thirds/one-third, and compact-screen adaptations.
- Keep presentation state and UI work on the main actor; cancel window-owned tasks
  when dismissed, and reject stale results from earlier documents or selections.
- Use semantic colors, meaningful accessibility labels/state, keyboard navigation,
  scalable text, non-color status cues, and reduced-motion support. VoiceOver,
  light/dark/increased contrast, focus and compact layouts still require host
  qualification; the user has disabled agent visual inspection.
- Serial display uses bounded, batched presentation with visible truncation;
  this must not alter the SDK's exact-byte delivery contract or flood VoiceOver.
- Firmware installation/reinstallation recovery is separate from managed Run.
  Present the exact SDK plan and uncertainty; execution requires explicit user action.
- No default-Arduino compilation or restoration feature belongs in this demo.
- Do not add iCloud, Spotlight, notifications, or shortcuts without accepted scope.
- Declare macOS 14/iOS 17 minimums and Swift 6 concurrency semantics; build both
  platforms and document signing/permissions separately from device qualification.
- Document every named declaration using triple-slash comments, as in root guidance.
