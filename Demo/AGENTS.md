# Firmingo demo instructions

Current consolidation: [shared Workbench engine and CLI](../docs/workbench-consolidation.md).
Use `WorkbenchSupport` for app-owned scenario orchestration and the shared registry;
manual and CLI actions must invoke that same engine. Keep no-replay run IDs,
bounded evidence, honest blocked results and public-SDK boundaries. Lifecycle scenarios now use aggregate real mobile app scenes and the shared
engine; launch-only CLI cannot synthesize them. Preserve the legacy hosts until
equivalent evidence exists. Selected inspection and fixed binary console scenarios
now use schema-two requests/reports and public SDK APIs; see
[device scenario scope](../docs/workbench-device-scenarios.md). Upload/recovery
migration now has separate schema-three managed phases; see
[managed scope](../docs/workbench-managed-scenarios.md). Signed build 11 now has
scoped Nano/iPad managed replacement, abort/disconnect, saved-context restart and
RAM-only power-cycle evidence in
[the ledger](../docs/workbench-managed-ipad-qualification.json). Restored commit
authority is refused; bootChanged remains unknown, and explicit retirement releases
only the no-commit host context. The matching iPhone build-11 matrix now completes through direct desktop MCP;
[its ledger](../docs/workbench-managed-iphone-qualification.json) retains two initial
inspection failures and the explicit reconnect needed to expose Ethernet, alongside
the later managed results. Clean attachment and real fault/reply-loss/ROM migration
remain unqualified.
The identical signed build 10 passes selected Nano
inspection/raw binary console through MCP on the physical iPhone and iPad; broader
combinations remain separately unqualified. FMS2 command-2 exact echo passes in
the selected build-11 iPad and iPhone managed workflows. Build 12 adds the
initialized-state and counter probe. The selected iPhone passed it on two boots
per variant. See the [State A ledger](../docs/workbench-iphone-state-qualification.json)
and [State B ledger](../docs/workbench-iphone-state-b-qualification.json).
The canonical scheme/product is FirmingoWorkbench; preserve the stable app bundle
identity instead of creating another binary identity for each phase.

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

Paired control uses the app-owned dispatcher/engine and explicit outbound pinned
TLS invitations; normal launch stays disconnected. Keep sequence deduplication,
producer/run correlation, foreground admission and a visible disconnect control.
No paired command may inject scenes, arbitrary paths/source/service URLs or device
write authority beyond an explicitly selected fixed binary probe or separately
authorized schema-three managed stage/one-shot commit. Device checks
require exact endpoint/board/identity; console additionally checks a separately
observed boot before any byte write. Preserve shared deployment leases and no
automatic retries. See [paired controller](../docs/workbench-paired-controller.md).
