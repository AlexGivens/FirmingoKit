import FirmingoKit
import Observation
import Foundation

/// Owns one cancellable inspection or live console and bounded presentation state per document window.
@MainActor @Observable
final class WorkbenchModel {
    /// Current explicit host board selection.
    var board: FirmingoBoard = .nanoRP2040Connect
    /// Numeric endpoint entered by the user; not inferred device identity.
    var address = "192.168.77.1"
    /// Editable TCP port, validated before calling the SDK.
    var port = "7420"
    /// Explicit application/UART backend expectation used before channel acquisition.
    var backend: FirmingoDevice.Backend = .application
    /// Latest hello snapshot, always from a connection already closed by the SDK.
    private(set) var device: FirmingoDevice?
    /// Human-readable state with explicit disconnected/inspection semantics.
    private(set) var status = "Disconnected. Inspect a selected device to read its capabilities."
    /// Prevents repeated commands and edits to target selection during inspection.
    private(set) var isInspecting = false
    /// Connection work in progress after an explicit host action.
    private(set) var isConnecting = false
    /// Current SDK session while channel ownership is acknowledged.
    private(set) var session: FirmingoSession?
    /// UTF-8 input selected by the host; newline conversion is never implicit.
    var consoleInput = ""
    /// How the host displays opaque SDK bytes; hex is lossless, UTF-8 may replace invalid sequences.
    var displayMode: ConsoleDisplayMode = .hex
    /// Last 16 KiB of received bytes for display only; the SDK stream itself does not truncate.
    private(set) var transcript = Data()
    /// Visible count of bytes dropped from the bounded host display.
    private(set) var truncatedBytes = 0
    /// Short reason for the latest console operation outcome.
    private(set) var consoleStatus = "No console is open."
    /// Owned operation cancelled when its window or sheet leaves the screen.
    private var task: Task<Void, Never>?
    /// Owned connection attempt, canceled if the selection changes or window closes.
    private var connectionTask: Task<Void, Never>?
    /// The sole lossless SDK byte consumer.
    private var readerTask: Task<Void, Never>?
    /// Coalesces display updates without changing SDK byte delivery.
    private var flushTask: Task<Void, Never>?
    /// Bounded staging for one UI update.
    private var pendingDisplay = Data()
    /// Rejects stale completion from an earlier cancelled inspection.
    private var generation = UUID()
    /// Rejects a late result from a superseded connection attempt.
    private var connectionGeneration = UUID()
    /// Prevents this window from starting communication while its explicit firmware operation runs.
    private(set) var isProgrammingFirmware = false

    /// Reserves this window against inspection, console acquisition and complete-firmware writes during managed Run.
    var isManagedOperation = false

    /// Display choices that never alter bytes crossing the SDK boundary.
    enum ConsoleDisplayMode: String, CaseIterable, Identifiable {
        /// Exact hexadecimal bytes separated by spaces.
        case hex = "Hex bytes"
        /// Decodes UTF-8, replacing invalid sequences for presentation only.
        case utf8 = "UTF-8 text"
        /// Stable picker identity.
        var id: String { rawValue }
    }

    /// Renders the bounded host transcript according to the explicit display setting.
    var displayedTranscript: String {
        switch displayMode {
        case .hex: transcript.map { String(format: "%02x", $0) }.joined(separator: " ")
        case .utf8: String(decoding: transcript, as: UTF8.self)
        }
    }

    /// Starts a fresh inspection only after an explicit user action.
    func inspect() {
        guard !isInspecting, !isProgrammingFirmware, !isManagedOperation else { return }
        guard let number = UInt16(port), number != 0 else {
            status = "Enter a port from 1 through 65535."
            return
        }
        let endpoint: FirmingoEndpoint
        do { endpoint = try FirmingoEndpoint(address: address, port: number) }
        catch { status = error.localizedDescription; return }
        let selectedBoard = board
        let token = UUID()
        generation = token
        device = nil
        isInspecting = true
        status = "Inspecting \(selectedBoard.displayName)…"
        task = Task { [weak self] in
            do {
                let result = try await FirmingoInspector.inspect(at: endpoint, expectedBoard: selectedBoard)
                guard let self, generation == token else { return }
                device = result
                status = "Inspection complete. Connection closed; no console ownership acquired."
                isInspecting = false
                task = nil
            } catch {
                guard let self, generation == token else { return }
                status = error is CancellationError ? "Inspection cancelled. Disconnected." : error.localizedDescription
                isInspecting = false
                task = nil
            }
        }
    }

    /// Cancels owned work and prevents a late result from changing presentation state.
    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        if isInspecting { status = "Inspection cancelled. Disconnected." }
        isInspecting = false
    }

    /// Starts a fresh connection and explicitly acquires channel one.
    func connectConsole(expectedDeviceID: String? = nil) {
        guard !isConnecting, session == nil, !isInspecting, !isProgrammingFirmware, !isManagedOperation else { return }
        guard let number = UInt16(port), number != 0 else {
            consoleStatus = "Enter a port from 1 through 65535."
            return
        }
        let endpoint: FirmingoEndpoint
        do { endpoint = try FirmingoEndpoint(address: address, port: number) }
        catch { consoleStatus = error.localizedDescription; return }
        let selectedBoard = board
        let selectedBackend = backend
        let token = UUID()
        connectionGeneration = token
        isConnecting = true
        transcript = Data()
        pendingDisplay = Data()
        truncatedBytes = 0
        consoleStatus = "Connecting to \(selectedBoard.displayName)…"
        connectionTask = Task { [weak self] in
            do {
                let connection = try await FirmingoSession.connect(to: endpoint,
                                                                   expectedBoard: selectedBoard,
                                                                   expectedBackend: selectedBackend, expectedDeviceID: expectedDeviceID)
                guard let self, connectionGeneration == token else {
                    await connection.disconnect()
                    return
                }
                do { try await connection.openConsole() }
                catch {
                    await connection.disconnect()
                    throw error
                }
                guard connectionGeneration == token else {
                    await connection.disconnect()
                    return
                }
                session = connection
                device = connection.device
                isConnecting = false
                connectionTask = nil
                status = "Connected to \(connection.device.deviceID). Channel one acquired."
                consoleStatus = "Console open. Sending only confirms local transport acceptance, not sketch execution."
                readerTask = Task { [weak self] in
                    do {
                        for try await bytes in connection.serialBytes {
                            guard let self, connectionGeneration == token else { break }
                            appendForDisplay(bytes)
                        }
                        guard let self, connectionGeneration == token else { return }
                        flushPending()
                        consoleStatus = "Console closed."
                    } catch {
                        guard let self, connectionGeneration == token else { return }
                        flushPending()
                        consoleStatus = error.localizedDescription
                        session = nil
                        status = "Disconnected."
                    }
                }
            } catch {
                guard let self, connectionGeneration == token else { return }
                isConnecting = false
                connectionTask = nil
                consoleStatus = error is CancellationError ? "Connection cancelled." : error.localizedDescription
                status = "Disconnected."
            }
        }
    }

    /// Sends the entered UTF-8 bytes exactly; clears input only after transport acceptance.
    func sendInput() {
        guard let session, !consoleInput.isEmpty, !isProgrammingFirmware, !isManagedOperation else { return }
        let input = consoleInput
        Task { [weak self] in
            do {
                try await session.sendSerial(Data(input.utf8))
                guard let self else { return }
                if consoleInput == input { consoleInput = "" }
                consoleStatus = "\(input.utf8.count) bytes accepted by local transport. Sketch consumption is unconfirmed."
            } catch {
                self?.consoleStatus = error.localizedDescription
            }
        }
    }

    /// Explicitly releases channel ownership, then closes the underlying connection.
    func disconnectConsole() async {
        connectionGeneration = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        isConnecting = false
        guard let connection = session else {
            consoleStatus = "Disconnected."
            return
        }
        session = nil
        do { try await connection.closeConsole() }
        catch { consoleStatus = error.localizedDescription }
        await connection.disconnect()
        readerTask?.cancel()
        readerTask = nil
        flushPending()
        status = "Disconnected."
        if consoleStatus.contains("Console open") { consoleStatus = "Console closed. Disconnected." }
    }

    /// Stops window-owned activity promptly when native document presentation ends.
    func stopForWindowClose() {
        cancel()
        connectionGeneration = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        readerTask?.cancel()
        readerTask = nil
        if let session { Task { await session.disconnect() } }
        session = nil
        isConnecting = false
        flushTask?.cancel()
        flushTask = nil
        pendingDisplay.removeAll()
    }

    /// Adds a byte chunk to bounded host presentation, scheduling a batched UI update.
    private func appendForDisplay(_ bytes: Data) {
        pendingDisplay.append(bytes)
        if pendingDisplay.count >= 4096 { flushPending(); return }
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
            self?.flushPending()
        }
    }

    /// Moves staged bytes into the 16-KiB transcript and reports any host-only truncation.
    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingDisplay.isEmpty else { return }
        transcript.append(pendingDisplay)
        pendingDisplay.removeAll(keepingCapacity: true)
        if transcript.count > 16_384 {
            let excess = transcript.count - 16_384
            transcript = Data(transcript.dropFirst(excess))
            truncatedBytes += excess
        }
    }

    /// Clears a snapshot when the explicit target selection changes.
    func clearSelection() {
        cancel()
        if session != nil || isConnecting { Task { await disconnectConsole() } }
        device = nil
        status = "Selection changed. Inspect the selected device again."
    }

    /// Hands the current idle session to the SDK for ownership release; cancels pending connection attempts.
    /// The SDK rejects unresolved session work before its writer can run.
    func beginFirmwareOperation() -> [FirmingoSession] {
        isProgrammingFirmware = true
        cancel()
        connectionGeneration = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        isConnecting = false
        return session.map { [$0] } ?? []
    }

    /// Stops any retained connection after success/failure, then allows a new explicit connection request.
    func finishFirmwareOperation() async {
        await disconnectConsole()
        isProgrammingFirmware = false
        device = nil
        status = "Firmware operation ended. Request a fresh inspection to verify the selected endpoint."
    }
}
