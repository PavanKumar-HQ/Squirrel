import Foundation
import CryptoKit

/// Multi-stage content-based duplicate file detector with full content confirmation.
public actor DuplicateDetector {
    private var isCancelled = false

    public init() {}

    public func cancel() {
        isCancelled = true
    }

    /// Discovers exact duplicate files among given candidate items with full content confirmation.
    public func findDuplicates(
        items: [StorageItem],
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [DuplicateGroup] {
        isCancelled = false

        // Step 1: Filter regular, readable files with size > 0 (exclude symlinks and directories)
        let eligible = items.filter { !$0.isDirectory && !$0.isSymbolicLink && $0.logicalSize > 0 && $0.isReadable }

        // Step 2: Group by exact logical size
        var sizeGroups: [Int64: [StorageItem]] = [:]
        for item in eligible {
            sizeGroups[item.logicalSize, default: []].append(item)
        }

        // Keep only size clusters with at least 2 files
        let candidateClusters = sizeGroups.values.filter { $0.count > 1 }
        progressHandler?("Analyzing \(candidateClusters.count) candidate size clusters...")

        var prefixGroups: [String: [StorageItem]] = [:]

        // Step 3: Prefix cryptographic hash (first 16 KB)
        for cluster in candidateClusters {
            if isCancelled || Task.isCancelled { break }

            for item in cluster {
                if let prefixHash = computePrefixHash(path: item.path, maxBytes: 16 * 1024) {
                    let key = "\(item.logicalSize)_\(prefixHash)"
                    prefixGroups[key, default: []].append(item)
                }
            }
        }

        let prefixClusters = prefixGroups.values.filter { $0.count > 1 }
        progressHandler?("Computing full SHA-256 on \(prefixClusters.count) candidate collision clusters...")

        // Step 4: Full cryptographic SHA-256 hash
        var fullHashGroups: [String: [StorageItem]] = [:]

        for cluster in prefixClusters {
            if isCancelled || Task.isCancelled { break }

            for item in cluster {
                progressHandler?("Hashing \(item.name)...")
                if let fullHash = computeFullSHA256(path: item.path) {
                    let key = "\(item.logicalSize)_\(fullHash)"
                    fullHashGroups[key, default: []].append(item)
                }
            }
        }

        // Step 5: Final Content Verification (Byte-by-byte confirmation)
        var verifiedGroups: [DuplicateGroup] = []

        for (key, files) in fullHashGroups where files.count > 1 {
            if isCancelled || Task.isCancelled { break }

            let hashOnly = key.components(separatedBy: "_").dropFirst().joined(separator: "_")
            let size = files.first?.logicalSize ?? 0

            // Verify full content equality between the primary file and other candidates
            guard let primary = files.first else { continue }
            var confirmedFiles: [StorageItem] = [primary]

            for candidate in files.dropFirst() {
                // Confirm 100% full content match
                if FileManager.default.contentsEqual(atPath: primary.path, andPath: candidate.path) {
                    confirmedFiles.append(candidate)
                }
            }

            guard confirmedFiles.count > 1 else { continue }

            // Determine recommended keep: sort by modification date ascending (oldest original is primary)
            let sortedFiles = confirmedFiles.sorted { ($0.modificationDate ?? Date.distantPast) < ($1.modificationDate ?? Date.distantPast) }

            var members: [DuplicateMember] = []
            for (index, file) in sortedFiles.enumerated() {
                let isKeep = (index == 0)
                let reason = isKeep ? "Original copy based on earliest modification date" : "Duplicate copy"
                members.append(DuplicateMember(
                    path: file.path,
                    fileName: file.name,
                    size: file.logicalSize,
                    allocatedSize: file.allocatedSize,
                    modificationDate: file.modificationDate,
                    creationDate: file.modificationDate,
                    isRecommendedToKeep: isKeep,
                    keepReason: reason
                ))
            }

            let group = DuplicateGroup(
                sha256Hash: hashOnly,
                fileSize: size,
                files: members
            )
            verifiedGroups.append(group)
        }

        // Sort largest reclaimable space first
        return verifiedGroups.sorted { $0.potentialReclaimableBytes > $1.potentialReclaimableBytes }
    }

    private func computePrefixHash(path: String, maxBytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maxBytes)
        guard !data.isEmpty else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func computeFullSHA256(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024 // 64 KB streaming buffer

        while true {
            let chunk = handle.readData(ofLength: bufferSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
