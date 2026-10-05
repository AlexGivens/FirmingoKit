import SwiftUI
import FirmingoKit

/// Explicit endpoint selection and read-only hello inspection, reachable without any firmware build.
@MainActor
struct DeviceInspectionView: View {
    /// Window-owned model; the view does not own SDK transport state.
    @Bindable var model: WorkbenchModel
    /// Native sheet dismissal action.
    @Environment(\.dismiss) private var dismiss

    /// A native form with accessible progress and cancellation.
    var body: some View {
        NavigationStack {
            Form {
                Section("Selected device") {
                    Picker("Board", selection: $model.board) {
                        ForEach(FirmingoBoard.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Expected backend", selection: $model.backend) {
                        Text("Application").tag(FirmingoDevice.Backend.application)
                        Text("UART").tag(FirmingoDevice.Backend.uart)
                    }
                    TextField("Numeric IP address", text: $model.address)
                        .autocorrectionDisabled()
                    TextField("TCP port", text: $model.port)
                }
                .disabled(model.isInspecting || model.isConnecting || model.session != nil || model.isManagedOperation)
                Section {
                    Text("Inspection reads hello and then disconnects. The address does not establish device identity.")
                    Text(model.status).textSelection(.enabled)
                    if model.isInspecting {
                        ProgressView("Waiting for hello")
                        Button("Cancel inspection", role: .cancel) { model.cancel() }
                    } else {
                        Button("Inspect selected device") { model.inspect() }.disabled(model.isManagedOperation)
                    }
                    Text(model.consoleStatus).textSelection(.enabled)
                    if model.isConnecting {
                        ProgressView("Connecting to console")
                    } else if model.session == nil {
                        Button("Connect and open console") { model.connectConsole() }
                            .disabled(model.isInspecting || model.isManagedOperation)
                    } else {
                        Button("Close console and disconnect") {
                            Task { await model.disconnectConsole() }
                        }
                    }
                }
            }
            .navigationTitle("Inspect Device")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.cancel(); dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 340)
        #endif
        .onChange(of: model.board) { model.clearSelection() }
        .onChange(of: model.address) { model.clearSelection() }
        .onChange(of: model.port) { model.clearSelection() }
        .onChange(of: model.backend) { model.clearSelection() }
        .onDisappear { model.cancel() }
    }
}
