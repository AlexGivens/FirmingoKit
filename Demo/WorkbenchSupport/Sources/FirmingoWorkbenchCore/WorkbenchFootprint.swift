import Foundation
import Darwin

/// Reads only the running Workbench process; unavailable kernel measurements fail explicitly.
enum WorkbenchFootprint {
    /// Returns TASK_VM_INFO phys_footprint bytes, excluding WebKit child processes.
    static func bytes() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        guard let offset = MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint) else {
            throw WorkbenchFailure("Self-process footprint field unavailable.")
        }
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS, Int(count) >= (offset + MemoryLayout<UInt64>.size) / MemoryLayout<integer_t>.size,
              info.phys_footprint > 0 else { throw WorkbenchFailure("Self-process footprint measurement failed (kernel \(result)).") }
        return info.phys_footprint
    }
}
