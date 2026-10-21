import Foundation
#if canImport(Darwin)
import Darwin.Mach
#endif

/// Live Darwin kernel telemetry for process memory and CPU utilization.
public struct ProcessTelemetry: Sendable, Codable, Equatable {
    /// Physical footprint in bytes (the memory metric used by macOS Activity Monitor & Instruments).
    public let physicalFootprint: Int64
    /// Resident memory size (RSS) in bytes.
    public let residentSize: Int64
    /// Total cumulative user CPU time in microseconds.
    public let userCPUTimeMicroseconds: UInt64
    /// Total cumulative system/kernel CPU time in microseconds.
    public let systemCPUTimeMicroseconds: UInt64
    /// Timestamp when measurement was taken.
    public let timestamp: Date

    public init(
        physicalFootprint: Int64 = 0,
        residentSize: Int64 = 0,
        userCPUTimeMicroseconds: UInt64 = 0,
        systemCPUTimeMicroseconds: UInt64 = 0,
        timestamp: Date = Date()
    ) {
        self.physicalFootprint = physicalFootprint
        self.residentSize = residentSize
        self.userCPUTimeMicroseconds = userCPUTimeMicroseconds
        self.systemCPUTimeMicroseconds = systemCPUTimeMicroseconds
        self.timestamp = timestamp
    }
}

/// Provides real-time macOS process and hardware efficiency telemetry.
public struct SystemTelemetry: Sendable {
    public static func captureCurrentProcessTelemetry() -> ProcessTelemetry {
        #if canImport(Darwin)
        var physFootprint: Int64 = 0
        var resident: Int64 = 0
        var userCPU: UInt64 = 0
        var sysCPU: UInt64 = 0

        // 1. Task VM Info (Physical footprint & RSS)
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            physFootprint = Int64(vmInfo.phys_footprint)
            resident = Int64(vmInfo.resident_size)
        }

        // 2. Task Threads (User & System CPU time)
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let threadResult = task_threads(mach_task_self_, &threadList, &threadCount)
        if threadResult == KERN_SUCCESS, let threads = threadList {
            for i in 0..<Int(threadCount) {
                var info = thread_basic_info()
                var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
                let kr = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                        thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                    }
                }
                if kr == KERN_SUCCESS {
                    userCPU += UInt64(info.user_time.seconds) * 1_000_000 + UInt64(info.user_time.microseconds)
                    sysCPU += UInt64(info.system_time.seconds) * 1_000_000 + UInt64(info.system_time.microseconds)
                }
            }
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threads)),
                vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size))
            )
        }

        return ProcessTelemetry(
            physicalFootprint: physFootprint,
            residentSize: resident,
            userCPUTimeMicroseconds: userCPU,
            systemCPUTimeMicroseconds: sysCPU,
            timestamp: Date()
        )
        #else
        return ProcessTelemetry()
        #endif
    }
}
