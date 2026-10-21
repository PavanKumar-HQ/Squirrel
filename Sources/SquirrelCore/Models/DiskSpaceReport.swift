import Foundation

/// Accurate representation of volume storage space reported by macOS APFS/HFS+ APIs.
public struct VolumeSpace: Codable, Sendable, Equatable {
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let importantAvailableCapacity: Int64
    public let opportunisticAvailableCapacity: Int64
    public let usedSpace: Int64
    public let volumeName: String
    public let mountPoint: String
    public let measurementSource: String

    public init(
        totalCapacity: Int64,
        availableCapacity: Int64,
        importantAvailableCapacity: Int64,
        opportunisticAvailableCapacity: Int64,
        usedSpace: Int64,
        volumeName: String,
        mountPoint: String,
        measurementSource: String = "Foundation URLResourceValues (APFS)"
    ) {
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.importantAvailableCapacity = importantAvailableCapacity
        self.opportunisticAvailableCapacity = opportunisticAvailableCapacity
        self.usedSpace = usedSpace
        self.volumeName = volumeName
        self.mountPoint = mountPoint
        self.measurementSource = measurementSource
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
            let available = Int64(values.volumeAvailableCapacity ?? 0)
            let important = values.volumeAvailableCapacityForImportantUsage ?? available
            let opportunistic = values.volumeAvailableCapacityForOpportunisticUsage ?? available
            let used = max(0, total - available)
            let name = values.volumeLocalizedName ?? "Macintosh HD"

            return VolumeSpace(
                totalCapacity: total,
                availableCapacity: available,
                importantAvailableCapacity: important,
                opportunisticAvailableCapacity: opportunistic,
                usedSpace: used,
                volumeName: name,
                mountPoint: url.path,
                measurementSource: "Foundation URLResourceValues (APFS)"
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
                    volumeName: url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent,
                    mountPoint: url.path,
                    measurementSource: "Darwin POSIX statvfs"
                )
            }
            return VolumeSpace(
                totalCapacity: 0,
                availableCapacity: 0,
                importantAvailableCapacity: 0,
                opportunisticAvailableCapacity: 0,
                usedSpace: 0,
                volumeName: "Unknown",
                mountPoint: url.path,
                measurementSource: "Unavailable"
            )
        }
    }
}
