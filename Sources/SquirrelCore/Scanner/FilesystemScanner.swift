import Foundation
import Darwin

/// Progress update published during filesystem scan operations.
public struct ScanProgress: Sendable, Equatable {
    public let currentPath: String
    public let itemsScannedCount: Int
    public let bytesScannedTotal: Int64
    public let currentCategory: String
    public let isComplete: Bool

    public init(
        currentPath: String = "",
        itemsScannedCount: Int = 0,
        bytesScannedTotal: Int64 = 0,
        currentCategory: String = "",
        isComplete: Bool = false
    ) {
        self.currentPath = currentPath
        self.itemsScannedCount = itemsScannedCount
        self.bytesScannedTotal = bytesScannedTotal
        self.currentCategory = currentCategory
        self.isComplete = isComplete
    }
}

/// Inaccessible directory or file encountered due to permissions or SIP.
public struct InaccessibleLocation: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let path: String
    public let reason: String

    public init(id: UUID = UUID(), path: String, reason: String) {
        self.id = id
        self.path = path
        self.reason = reason
    }
}

/// Aggregate scan result containing discovered items, findings, and diagnostic metadata.
public struct ScanResult: Sendable {
    public let items: [StorageItem]
    public let categoryTotals: [StorageCategory: Int64]
    public let allocatedCategoryTotals: [StorageCategory: Int64]
    public let totalLogicalBytes: Int64
    public let totalAllocatedBytes: Int64
    public let inaccessibleLocations: [InaccessibleLocation]
    public let scanDurationSeconds: TimeInterval
    public let completedNormally: Bool

    public init(
        items: [StorageItem],
        categoryTotals: [StorageCategory: Int64],
        allocatedCategoryTotals: [StorageCategory: Int64],
        totalLogicalBytes: Int64,
        totalAllocatedBytes: Int64,
        inaccessibleLocations: [InaccessibleLocation],
        scanDurationSeconds: TimeInterval,
        completedNormally: Bool
    ) {
        self.items = items
        self.categoryTotals = categoryTotals
        self.allocatedCategoryTotals = allocatedCategoryTotals
        self.totalLogicalBytes = totalLogicalBytes
        self.totalAllocatedBytes = totalAllocatedBytes
        self.inaccessibleLocations = inaccessibleLocations
        self.scanDurationSeconds = scanDurationSeconds
        self.completedNormally = completedNormally
    }
}

/// Actor responsible for performing safe, on-demand traversal and measurements.
public actor FilesystemScanner {
    private var isCancelled = false
    private var scannedInodes = Set<String>()

    public init() {}

    public func cancel() {
        isCancelled = true
    }

    /// Scans specified directories with cooperative cancellation and progress streaming.
    public func scan(
        roots: [URL],
        progressHandler: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        isCancelled = false
        scannedInodes.removeAll()

        let startTime = Date()
        var discoveredItems: [StorageItem] = []
        var inaccessible: [InaccessibleLocation] = []
        var totalLogical: Int64 = 0
        var totalAllocated: Int64 = 0
        var categoryMap: [StorageCategory: Int64] = [:]
        var allocatedCategoryMap: [StorageCategory: Int64] = [:]

        var itemCount = 0

        for root in roots {
            if isCancelled || Task.isCancelled { break }

            guard FileManager.default.fileExists(atPath: root.path) else {
                inaccessible.append(InaccessibleLocation(path: root.path, reason: "Path does not exist"))
                continue
            }

            // Check readability of the root
            guard FileManager.default.isReadableFile(atPath: root.path) else {
                inaccessible.append(InaccessibleLocation(path: root.path, reason: "Permission denied (TCC / read access)"))
                continue
            }

            await scanDirectory(
                url: root,
                rootURL: root,
                discoveredItems: &discoveredItems,
                inaccessible: &inaccessible,
                itemCount: &itemCount,
                totalLogical: &totalLogical,
                totalAllocated: &totalAllocated,
                progressHandler: progressHandler
            )
        }

        // Categorize totals
        for item in discoveredItems {
            let cat = determineCategory(for: item)
            categoryMap[cat, default: 0] += item.logicalSize
            allocatedCategoryMap[cat, default: 0] += item.allocatedSize
        }

        let duration = Date().timeIntervalSince(startTime)
        let completed = !isCancelled && !Task.isCancelled

        progressHandler?(ScanProgress(
            currentPath: "Scan completed",
            itemsScannedCount: itemCount,
            bytesScannedTotal: totalLogical,
            currentCategory: "",
            isComplete: true
        ))

        return ScanResult(
            items: discoveredItems,
            categoryTotals: categoryMap,
            allocatedCategoryTotals: allocatedCategoryMap,
            totalLogicalBytes: totalLogical,
            totalAllocatedBytes: totalAllocated,
            inaccessibleLocations: inaccessible,
            scanDurationSeconds: duration,
            completedNormally: completed
        )
    }

    private func scanDirectory(
        url: URL,
        rootURL: URL,
        discoveredItems: inout [StorageItem],
        inaccessible: inout [InaccessibleLocation],
        itemCount: inout Int,
        totalLogical: inout Int64,
        totalAllocated: inout Int64,
        progressHandler: (@Sendable (ScanProgress) -> Void)?
    ) async {
        if isCancelled || Task.isCancelled { return }

        // Protect against symlink traversal escaping root
        var isSymlink = false
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let type = attrs?[.type] as? FileAttributeType, type == .typeSymbolicLink {
                isSymlink = true
            }
        }

        // If it's a symlink pointing outside or a cycle, do not traverse into it
        if isSymlink {
            return
        }

        let resourceKeys: Set<URLResourceKey> = [
            .nameKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .isReadableKey,
            .isWritableKey
        ]

        let artifactDirNames: Set<String> = [
            "node_modules", ".next", ".turbo", ".nuxt", ".output",
            "target", "build", "dist", "venv", ".venv", ".pytest_cache",
            ".mypy_cache", ".ruff_cache", "DerivedData", "Pods", ".build",
            ".gradle", ".cxx", ".dart_tool", ".zig-cache", "zig-out"
        ]

        var enumErrors: [InaccessibleLocation] = []
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { errURL, err in
                enumErrors.append(InaccessibleLocation(path: errURL.path, reason: err.localizedDescription))
                return true
            }
        )

        guard let fileEnumerator = enumerator else {
            inaccessible.append(InaccessibleLocation(path: url.path, reason: "Could not open directory enumerator"))
            return
        }

        var lastProgressDate = Date()
        while let nextObj = fileEnumerator.nextObject() {
            guard let fileURL = nextObj as? URL else { continue }
            if isCancelled || Task.isCancelled { break }

            itemCount += 1
            if itemCount % 25 == 0 {
                await Task.yield()
                if isCancelled || Task.isCancelled { break }
            }

            let now = Date()
            if now.timeIntervalSince(lastProgressDate) >= 0.1 {
                lastProgressDate = now
                let currentTotal = totalLogical
                let count = itemCount
                let currentP = fileURL.path
                progressHandler?(ScanProgress(
                    currentPath: currentP,
                    itemsScannedCount: count,
                    bytesScannedTotal: currentTotal,
                    currentCategory: "Analyzing...",
                    isComplete: false
                ))
                // Cooperative yield
                await Task.yield()
            }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
                let isDirectory = resourceValues.isDirectory ?? false
                let isLink = resourceValues.isSymbolicLink ?? false

                // Do not follow symlinks
                if isLink {
                    fileEnumerator.skipDescendants()
                    continue
                }

                // Query POSIX stat for accurate inode and hard link tracking
                var statBuf = stat()
                let statResult = lstat(fileURL.path, &statBuf)
                guard statResult == 0 else {
                    // Disappearing file (ENOENT) during scan is safely skipped; other errors are recorded
                    if errno != ENOENT {
                        inaccessible.append(InaccessibleLocation(path: fileURL.path, reason: "lstat error: \(String(cString: strerror(errno)))"))
                    }
                    continue
                }

                let inodeKey = "\(statBuf.st_dev):\(statBuf.st_ino)"
                let isHardLinkDuplicate = scannedInodes.contains(inodeKey)
                scannedInodes.insert(inodeKey)

                // High-efficiency artifact directory aggregation:
                // Treat heavy regenerable build/dependency folders as single cohesive units
                if isDirectory && artifactDirNames.contains(fileURL.lastPathComponent) {
                    fileEnumerator.skipDescendants()
                    let (dirLogical, dirAllocated) = Self.calculateDirectorySizes(at: fileURL)
                    totalLogical += dirLogical
                    totalAllocated += dirAllocated

                    let item = StorageItem(
                        url: fileURL,
                        path: fileURL.path,
                        name: resourceValues.name ?? fileURL.lastPathComponent,
                        logicalSize: dirLogical,
                        allocatedSize: dirAllocated,
                        isDirectory: true,
                        isSymbolicLink: false,
                        deviceId: statBuf.st_dev,
                        inode: statBuf.st_ino,
                        modificationDate: resourceValues.contentModificationDate,
                        isReadable: resourceValues.isReadable ?? true,
                        isWritable: resourceValues.isWritable ?? true
                    )
                    discoveredItems.append(item)
                    continue
                }

                let logicalSize = Int64(resourceValues.fileSize ?? 0)
                let posixAllocatedSize = Int64(statBuf.st_blocks) * 512
                let allocatedSize = posixAllocatedSize > 0 ? posixAllocatedSize : Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? Int(logicalSize))

                // If hard link was already counted, do not inflate aggregate size
                if !isHardLinkDuplicate && !isDirectory {
                    totalLogical += logicalSize
                    totalAllocated += allocatedSize
                }

                let item = StorageItem(
                    url: fileURL,
                    path: fileURL.path,
                    name: resourceValues.name ?? fileURL.lastPathComponent,
                    logicalSize: logicalSize,
                    allocatedSize: allocatedSize,
                    isDirectory: isDirectory,
                    isSymbolicLink: isLink,
                    deviceId: statBuf.st_dev,
                    inode: statBuf.st_ino,
                    modificationDate: resourceValues.contentModificationDate,
                    isReadable: resourceValues.isReadable ?? true,
                    isWritable: resourceValues.isWritable ?? true
                )

                discoveredItems.append(item)
            } catch {
                inaccessible.append(InaccessibleLocation(path: fileURL.path, reason: error.localizedDescription))
            }
        }

        if !enumErrors.isEmpty {
            inaccessible.append(contentsOf: enumErrors)
        }
    }

    public static func calculateDirectorySizes(at url: URL) -> (logical: Int64, allocated: Int64) {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return (0, 0) }

        var logSize: Int64 = 0
        var allocSize: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if let vals = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                let s = Int64(vals.fileSize ?? 0)
                let a = Int64(vals.totalFileAllocatedSize ?? Int(s))
                logSize += s
                allocSize += a
            }
        }
        return (logSize, allocSize)
    }

    private func determineCategory(for item: StorageItem) -> StorageCategory {
        return ClassificationRules.shared.determineCategory(for: item)
    }
}
