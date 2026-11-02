import Foundation
import Testing
import FirmingoKit
@testable import FirmingoWorkbenchCore

/// Test-controlled clock and evidence; these synthetic fixtures never establish runtime or scene qualification.
@MainActor private final class ExerciseContext {
    /// Monotonic test seconds advanced explicitly at an injected boundary.
    var seconds = 0.0
    /// Last snapshot acknowledged by the injected journal.
    var evidence: WorkbenchExerciseEvidence?
    /// Rejects a progress save before cancellation/fresh work.
    var refuseInterruptedSave = false
    /// Captures acknowledged evidence or fails its durable gate.
    func save(_ value: WorkbenchExerciseEvidence) throws {
        if refuseInterruptedSave && value.startedSeconds != nil { throw WorkbenchFailure("Injected journal failure.") }
        evidence = value
    }
}

/// Explicit non-executable artifacts and scripted typed SDK failures, used only for orchestration tests.
@MainActor private final class ExerciseBackend: WorkbenchCompilerBackend {
    /// Calls observed at the real orchestration boundary.
    var inputs: [WorkbenchCompilerInput] = []
    /// Test clock shared with the owner.
    let context: ExerciseContext
    /// Deadline request advances the synthetic clock by this amount before typed timeout.
    var timeoutSeconds = 60.0
    /// Models a pending call which ignores cancellation and returns bytes; it must never qualify.
    var ignoresCancellation = false
    /// Whether the synthetic pending request is active when verifyResources is called.
    private var active = false
    /// Constructs no actual compiler or device state.
    init(_ context: ExerciseContext) { self.context = context }
    /// Not used by direct exercise tests; no deployable descriptor is fabricated.
    func catalogue() async throws -> WorkbenchCatalogue { throw WorkbenchFailure("Fixture has no catalogue.") }
    /// Only typed busy is accepted for an overlapping call.
    func verifyResources() async throws {
        if active { throw ManagedCompilerError.busy }
    }
    /// Models a completed baseline, then controlled first-source timeout/cancellation, then a known fresh response.
    func compile(_ input: WorkbenchCompilerInput, buildID: String, probe: WorkbenchCompilerProbe) async throws -> WorkbenchReport.Artifact {
        inputs.append(input)
        probe.record(.verifying); probe.record(.compiling)
        if input == .deadline {
            context.seconds += timeoutSeconds
            throw ManagedCompilerError.timedOut
        }
        if inputs.count == 2 && input == .gpio {
            active = true; defer { active = false }
            while !Task.isCancelled { await Task.yield() }
            if !ignoresCancellation { throw CancellationError() }
        }
        return .init(name: input.rawValue + ".fms", sha256: input.expectedSHA256 ?? "fixture",
            bytes: Data("non-executable orchestration fixture".utf8), receiptJSON: Data("{}".utf8), wasmLinearMemoryBytes: 1024)
    }
}

/// Independent expected hashes catch fixture generation drift before real SDK admission.
@Test func generatedWorkloadsMatchLegacyEvidence() throws {
    #expect(try WorkbenchWorkload.source(deadline: false).utf8.count == 227505)
    #expect(try WorkbenchWorkload.source(deadline: true).utf8.count == 227646)
}

/// Synchronous callback capture keeps ordering across producer threads and rejects overflow explicitly.
@Test func compilerProbeIsBoundedAndThreadSafe() async throws {
    let probe = WorkbenchCompilerProbe()
    await withTaskGroup(of: Void.self) { tasks in
        for _ in 0..<8 { tasks.addTask { probe.record(.compiling) } }
    }
    let points = try probe.snapshot()
    #expect(points.count == 8)
    #expect(zip(points, points.dropFirst()).allSatisfy { $0.seconds <= $1.seconds })
    probe.record(.packaging)
    #expect(throws: WorkbenchFailure.self) { try probe.snapshot() }
}

/// Launch-only hosts block every real scene case before catalogue/resource work.
@Test @MainActor func sceneScenariosRequireAnInteractiveHost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let context = ExerciseContext(), backend = ExerciseBackend(ExerciseContext())
    let engine = WorkbenchScenarioEngine(backend: backend, store: WorkbenchFileRunStore(directory: root))
    for scenario in WorkbenchScenario.all where scenario.requiresSceneTransitions {
        let request = try WorkbenchRequest(operation: .run, scenarioID: scenario.id, firmwareBuildID: WorkbenchCompilerInput.buildID)
        #expect(try await engine.run(request).status == .blocked)
    }
    #expect(context.evidence == nil && backend.inputs.isEmpty)
}

/// Actual timeout is distinguished from a too-early typed fixture, and no fresh work follows invalid evidence.
@Test @MainActor func earlyTypedTimeoutCannotQualifyProductionDeadline() async throws {
    let context = ExerciseContext(), backend = ExerciseBackend(ExerciseContext())
    backend.timeoutSeconds = 0
    let owner = WorkbenchCompilerExercise(kind: "compiler.deadline", backend: backend, buildID: WorkbenchCompilerInput.buildID,
        scene: "unknown", observesScenes: false, now: { context.seconds }, save: context.save,
        emit: { _, _, _ in })
    await #expect(throws: WorkbenchFailure.self) { try await owner.run() }
    #expect(backend.inputs == [.gpio, .deadline])
    #expect(context.evidence?.outcome == "timedOut")
    #expect(context.evidence?.freshStartedSeconds == nil)
}

/// A rejected durable interruption boundary prevents the SDK deadline request itself.
@Test @MainActor func interruptedJournalFailurePreventsLaterSDKWork() async throws {
    let context = ExerciseContext(), backend = ExerciseBackend(ExerciseContext()); context.refuseInterruptedSave = true
    let owner = WorkbenchCompilerExercise(kind: "compiler.deadline", backend: backend, buildID: WorkbenchCompilerInput.buildID,
        scene: "unknown", observesScenes: false, now: { context.seconds }, save: context.save,
        emit: { _, _, _ in })
    await #expect(throws: WorkbenchFailure.self) { try await owner.run() }
    #expect(backend.inputs == [.gpio])
}

/// Even a backend returning bytes after cancellation fails; no artifact/fresh call may replace settlement.
@Test @MainActor func returnedBytesCannotSubstituteForCancellation() async throws {
    let context = ExerciseContext(), backend = ExerciseBackend(ExerciseContext()); backend.ignoresCancellation = true
    let origin = ProcessInfo.processInfo.systemUptime
    let owner = WorkbenchCompilerExercise(kind: "compiler.cancellation", backend: backend, buildID: WorkbenchCompilerInput.buildID,
        scene: "unknown", observesScenes: false, now: { ProcessInfo.processInfo.systemUptime - origin }, save: context.save,
        emit: { _, _, _ in })
    await #expect(throws: WorkbenchFailure.self) { try await owner.run() }
    #expect(context.evidence?.outcome == "artifactReturned")
    #expect(context.evidence?.busyObserved == true)
    #expect(backend.inputs == [.gpio, .gpio])
}

/// Synthetic scene delivery exercises the production ordering rule; this is not a real background transition.
@Test @MainActor func idleLifecycleRequiresARealOrderedIntervalFromItsAdapter() async throws {
    for short in [true, false] {
        let context = ExerciseContext(), backend = ExerciseBackend(ExerciseContext())
        var owner: WorkbenchCompilerExercise?
        owner = WorkbenchCompilerExercise(kind: "host.lifecycle", backend: backend, buildID: WorkbenchCompilerInput.buildID,
            scene: "active", observesScenes: true, now: { context.seconds }, save: context.save,
            emit: { phase, _, _ in
                if phase == "waiting-for-background" {
                    owner?.recordScene("inactive"); owner?.recordScene("background")
                    context.seconds += short ? 1 : 5; owner?.recordScene("active")
                }
            })
        let exercise = try #require(owner)
        if short { await #expect(throws: WorkbenchFailure.self) { try await exercise.run() } }
        else { try await exercise.run() }
        #expect(backend.inputs == (short ? [.gpio] : [.gpio, .console]))
        owner = nil
    }
}
