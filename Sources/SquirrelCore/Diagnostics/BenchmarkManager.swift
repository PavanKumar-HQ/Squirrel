import Foundation

/// Performance record for a single filesystem scan execution.
public struct ScanPerformanceRecord: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let targetDescription: String
    public let itemCount: Int
    public let totalLogicalBytes: Int64
    public let durationSeconds: TimeInterval
    public let throughputItemsPerSec: Double
    public let throughputMBPerSec: Double
    public let startPhysicalFootprint: Int64
    public let peakPhysicalFootprint: Int64
    public let completedNormally: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        targetDescription: String,
        itemCount: Int,
        totalLogicalBytes: Int64,
        durationSeconds: TimeInterval,
        startPhysicalFootprint: Int64,
        peakPhysicalFootprint: Int64,
        completedNormally: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.targetDescription = targetDescription
        self.itemCount = itemCount
        self.totalLogicalBytes = totalLogicalBytes
        self.durationSeconds = max(0.0001, durationSeconds)
        self.throughputItemsPerSec = Double(itemCount) / self.durationSeconds
        self.throughputMBPerSec = (Double(totalLogicalBytes) / (1024.0 * 1024.0)) / self.durationSeconds
        self.startPhysicalFootprint = startPhysicalFootprint
        self.peakPhysicalFootprint = peakPhysicalFootprint
        self.completedNormally = completedNormally
    }
}

/// Comparison between cold-cache and warm-cache traversals on a controlled directory fixture.
public struct BenchmarkComparison: Sendable, Codable, Equatable {
    public let testTarget: String
    public let itemCount: Int
    public let totalBytes: Int64
    public let coldDurationSeconds: TimeInterval
    public let warmDurationSeconds: TimeInterval
    public let coldItemsPerSec: Double
    public let warmItemsPerSec: Double
    public let warmSpeedupFactor: Double
    public let memoryFootprintBytes: Int64
    public let timestamp: Date

    public init(
        testTarget: String,
        itemCount: Int,
        totalBytes: Int64,
        coldDurationSeconds: TimeInterval,
        warmDurationSeconds: TimeInterval,
        coldItemsPerSec: Double,
        warmItemsPerSec: Double,
        warmSpeedupFactor: Double,
        memoryFootprintBytes: Int64,
        timestamp: Date = Date()
    ) {
        self.testTarget = testTarget
        self.itemCount = itemCount
        self.totalBytes = totalBytes
        self.coldDurationSeconds = coldDurationSeconds
        self.warmDurationSeconds = warmDurationSeconds
        self.coldItemsPerSec = coldItemsPerSec
        self.warmItemsPerSec = warmItemsPerSec
        self.warmSpeedupFactor = warmSpeedupFactor
        self.memoryFootprintBytes = memoryFootprintBytes
        self.timestamp = timestamp
    }
}

/// Manager responsible for persisting and querying real benchmark and efficiency metrics.
public final class BenchmarkManager: @unchecked Sendable {
    public static let shared = BenchmarkManager()

    private let storageURL: URL
    private let queue = DispatchQueue(label: "com.squirrel.benchmarks", qos: .utility)
    private var cachedRecords: [ScanPerformanceRecord] = []
    private var lastControlledBenchmark: BenchmarkComparison?

    public init(customStorageURL: URL? = nil) {
        if let custom = customStorageURL {
            self.storageURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let dir = appSupport.appendingPathComponent("Squirrel", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("benchmarks.json")
        }
        loadRecords()
    }

    private func loadRecords() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let records = try JSONDecoder().decode([ScanPerformanceRecord].self, from: data)
            self.cachedRecords = records
        } catch {
            self.cachedRecords = []
        }
    }

    public func recordScan(_ record: ScanPerformanceRecord) {
        queue.async {
            self.cachedRecords.append(record)
            if self.cachedRecords.count > 100 {
                self.cachedRecords.removeFirst(self.cachedRecords.count - 100)
            }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(self.cachedRecords)
                try data.write(to: self.storageURL, options: .atomic)
            } catch {
                // Non-fatal
            }
        }
    }

    public func getRecentRecords() -> [ScanPerformanceRecord] {
        return queue.sync {
            return self.cachedRecords.reversed()
        }
    }

    public func getLastBenchmarkComparison() -> BenchmarkComparison? {
        return queue.sync {
            return self.lastControlledBenchmark
        }
    }

    public func setLastBenchmarkComparison(_ comparison: BenchmarkComparison) {
        queue.async {
            self.lastControlledBenchmark = comparison
        }
    }
}
