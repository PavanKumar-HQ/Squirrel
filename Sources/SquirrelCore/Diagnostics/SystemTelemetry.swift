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

/// Live macOS system-wide RAM metrics captured directly via Darwin host_statistics64.
public struct SystemRAMMetrics: Sendable, Codable, Equatable {
    public let freeBytes: Int64
    public let activeBytes: Int64
    public let inactiveBytes: Int64
    public let wiredBytes: Int64
    public let compressedBytes: Int64
    public let totalPhysicalRAMBytes: Int64
    public let memoryPressure: String // "Normal", "Warning", "Critical"

    public var usedBytes: Int64 {
        activeBytes + wiredBytes + compressedBytes
    }

    public init(
        freeBytes: Int64 = 0,
        activeBytes: Int64 = 0,
        inactiveBytes: Int64 = 0,
        wiredBytes: Int64 = 0,
        compressedBytes: Int64 = 0,
        totalPhysicalRAMBytes: Int64 = 0,
        memoryPressure: String = "Normal"
    ) {
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.totalPhysicalRAMBytes = totalPhysicalRAMBytes
        self.memoryPressure = memoryPressure
    }
}

/// Live Apple Silicon thermal sentinel metrics.
public struct ThermalMetrics: Sendable, Codable, Equatable {
    public let thermalStateRaw: Int
    public let stateName: String
    public let advice: String
    public let isCoolAndSafe: Bool

    public init(
        thermalStateRaw: Int = 0,
        stateName: String = "Nominal",
        advice: String = "Cool & efficient. Zero thermal throttling.",
        isCoolAndSafe: Bool = true
    ) {
        self.thermalStateRaw = thermalStateRaw
        self.stateName = stateName
        self.advice = advice
        self.isCoolAndSafe = isCoolAndSafe
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

    /// Captures Darwin kernel host VM memory metrics.
    public static func captureSystemRAMMetrics() -> SystemRAMMetrics {
        #if canImport(Darwin)
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return SystemRAMMetrics()
        }

        let pageSize = Int64(vm_kernel_page_size)
        let freeBytes = Int64(vmStats.free_count) * pageSize
        let activeBytes = Int64(vmStats.active_count) * pageSize
        let inactiveBytes = Int64(vmStats.inactive_count) * pageSize
        let wiredBytes = Int64(vmStats.wire_count) * pageSize
        let compressedBytes = Int64(vmStats.compressor_page_count) * pageSize
        let totalRAM = Int64(ProcessInfo.processInfo.physicalMemory)

        // Calculate approximate pressure level
        let availableMemory = freeBytes + inactiveBytes
        let pressure: String
        if availableMemory < 500 * 1024 * 1024 {
            pressure = "Critical"
        } else if availableMemory < 1500 * 1024 * 1024 {
            pressure = "Warning"
        } else {
            pressure = "Normal"
        }

        return SystemRAMMetrics(
            freeBytes: freeBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            totalPhysicalRAMBytes: totalRAM,
            memoryPressure: pressure
        )
        #else
        return SystemRAMMetrics()
        #endif
    }

    /// Captures Apple Silicon thermal status.
    public static func captureThermalMetrics() -> ThermalMetrics {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal:
            return ThermalMetrics(
                thermalStateRaw: 0,
                stateName: "Nominal",
                advice: "Cool & efficient. Zero thermal throttling.",
                isCoolAndSafe: true
            )
        case .fair:
            return ThermalMetrics(
                thermalStateRaw: 1,
                stateName: "Fair",
                advice: "Slightly elevated temperature. Performance is normal.",
                isCoolAndSafe: true
            )
        case .serious:
            return ThermalMetrics(
                thermalStateRaw: 2,
                stateName: "Serious",
                advice: "High heat detected. Fanless throttling active to protect hardware.",
                isCoolAndSafe: false
            )
        case .critical:
            return ThermalMetrics(
                thermalStateRaw: 3,
                stateName: "Critical",
                advice: "Critical heat. System throttling heavily. Allow Mac to rest.",
                isCoolAndSafe: false
            )
        @unknown default:
            return ThermalMetrics()
        }
    }
}
