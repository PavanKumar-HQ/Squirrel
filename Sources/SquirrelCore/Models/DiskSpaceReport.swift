import Foundation

/// Accurate representation of volume storage space reported by macOS APFS/HFS+ APIs,
/// aligned with Apple System Settings (General > Storage).
public struct VolumeSpace: Codable, Sendable, Equatable {
    /// Total capacity ceiling of the APFS container (e.g. 245.11 GB).
    public let totalCapacity: Int64
    /// Available capacity agreeing with Apple System Settings (includes purgeable space, e.g. 147.53 GB).
    public let availableCapacity: Int64
    /// Documented URLResourceValues volumeAvailableCapacityForImportantUsageKey.
    public let importantAvailableCapacity: Int64
    /// Documented URLResourceValues volumeAvailableCapacityForOpportunisticUsageKey.
    public let opportunisticAvailableCapacity: Int64
    /// Used storage agreeing with Apple System Settings (totalCapacity - availableCapacity, e.g. 97.58 GB).
    public let usedSpace: Int64
    /// Raw unallocated physical container blocks (volumeAvailableCapacityKey, e.g. 126.28 GB).
    public let rawAvailableCapacity: Int64
    /// Raw physical container allocation in use (totalCapacity - rawAvailableCapacity, e.g. 118.83 GB).
    public let rawPhysicalUsedSpace: Int64
    /// Storage purgeable by APFS under storage pressure (importantAvailableCapacity - rawAvailableCapacity, e.g. 21.25 GB).
    public let purgeableSpace: Int64
    /// Localized name of the volume (e.g. "Macintosh HD").
    public let volumeName: String
    /// Mount point of the volume (e.g. "/").
    public let mountPoint: String
    /// Source API used for the measurement.
    public let measurementSource: String
    /// Detailed Apple category audit report (Documents, Apps, Developer, System Data, macOS).
    public var auditReport: AppleStorageAuditReport?

    public init(
        totalCapacity: Int64,
        availableCapacity: Int64,
        importantAvailableCapacity: Int64,
        opportunisticAvailableCapacity: Int64,
        usedSpace: Int64,
        rawAvailableCapacity: Int64 = 0,
        rawPhysicalUsedSpace: Int64 = 0,
        purgeableSpace: Int64 = 0,
        volumeName: String,
        mountPoint: String,
        measurementSource: String = "Foundation URLResourceValues (APFS)",
        auditReport: AppleStorageAuditReport? = nil
    ) {
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.importantAvailableCapacity = importantAvailableCapacity
        self.opportunisticAvailableCapacity = opportunisticAvailableCapacity
        self.usedSpace = usedSpace
        self.rawAvailableCapacity = rawAvailableCapacity == 0 ? availableCapacity : rawAvailableCapacity
        self.rawPhysicalUsedSpace = rawPhysicalUsedSpace == 0 ? usedSpace : rawPhysicalUsedSpace
        self.purgeableSpace = purgeableSpace
        self.volumeName = volumeName
        self.mountPoint = mountPoint
        self.measurementSource = measurementSource
        self.auditReport = auditReport
    }

    /// Queries the actual macOS volume metrics for the primary system root.
    public static func querySystemVolume() -> VolumeSpace {
        return queryVolume(at: URL(fileURLWithPath: "/"))
    }

    /// Queries actual volume metrics for any specified mount point or URL.
    public static func queryVolume(at url: URL) -> VolumeSpace {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityForOpportunisticUsageKey,
                .volumeLocalizedNameKey
            ])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let rawAvailable = Int64(values.volumeAvailableCapacity ?? 0)
            let important = Int64(values.volumeAvailableCapacityForImportantUsage ?? rawAvailable)
            let opportunistic = Int64(values.volumeAvailableCapacityForOpportunisticUsage ?? rawAvailable)

            // System Settings parity:
            // Available is importantAvailableCapacity (accounting for APFS purgeable files)
            // Used is Total - Available
            let available = important > 0 ? important : rawAvailable
            let used = max(0, total - available)
            let purgeable = max(0, important - rawAvailable)
            let rawUsed = max(0, total - rawAvailable)
            let name = values.volumeLocalizedName ?? "Macintosh HD"

            return VolumeSpace(
                totalCapacity: total,
                availableCapacity: available,
                importantAvailableCapacity: important,
                opportunisticAvailableCapacity: opportunistic,
                usedSpace: used,
                rawAvailableCapacity: rawAvailable,
                rawPhysicalUsedSpace: rawUsed,
                purgeableSpace: purgeable,
                volumeName: name,
                mountPoint: url.path,
                measurementSource: "Foundation URLResourceValues (APFS)",
                auditReport: nil
            )
        } catch {
            // Fallback to POSIX statvfs
            var stats = statvfs()
            if statvfs(url.path, &stats) == 0 {
                let blockSize = Int64(stats.f_frsize)
                let total = Int64(stats.f_blocks) * blockSize
                let free = Int64(stats.f_bavail) * blockSize
                let used = max(0, total - free)
                return VolumeSpace(
                    totalCapacity: total,
                    availableCapacity: free,
                    importantAvailableCapacity: free,
                    opportunisticAvailableCapacity: free,
                    usedSpace: used,
                    rawAvailableCapacity: free,
                    rawPhysicalUsedSpace: used,
                    purgeableSpace: 0,
                    volumeName: url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent,
                    mountPoint: url.path,
                    measurementSource: "Darwin POSIX statvfs",
                    auditReport: nil
                )
            }
            return VolumeSpace(
                totalCapacity: 0,
                availableCapacity: 0,
                importantAvailableCapacity: 0,
                opportunisticAvailableCapacity: 0,
                usedSpace: 0,
                rawAvailableCapacity: 0,
                rawPhysicalUsedSpace: 0,
                purgeableSpace: 0,
                volumeName: "Unknown",
                mountPoint: url.path,
                measurementSource: "Unavailable",
                auditReport: nil
            )
        }
    }
}
