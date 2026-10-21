import Foundation

/// Progress status for cleanup execution.
public struct CleanupProgress: Sendable {
    public let completedCount: Int
    public let totalCount: Int
    public let currentItemName: String
    public let bytesReclaimedSoFar: Int64
    public let isComplete: Bool

    public init(
        completedCount: Int = 0,
        totalCount: Int = 0,
        currentItemName: String = "",
        bytesReclaimedSoFar: Int64 = 0,
        isComplete: Bool = false
    ) {
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.currentItemName = currentItemName
        self.bytesReclaimedSoFar = bytesReclaimedSoFar
        self.isComplete = isComplete
    }
}

/// Confidence rating of the post-cleanup storage recovery measurement.
public enum CleanupConfidenceLevel: String, Sendable, Codable, Equatable {
    case verifiedByFilesystem = "Verified by APFS Volume"
    case partiallyVerified = "Partially Reflected in APFS"
    case delayedOrSnapshotRetained = "Delayed Accounting / Snapshot Retained"
    case unverified = "Unverified"
}

/// Comprehensive, evidence-based verification report generated after cleanup execution.
public struct CleanupSummary: Sendable, Codable, Equatable {
    // 1. Candidate Breakdown
    public let candidatesDiscoveredCount: Int
    public let itemsEligibleCount: Int
    public let itemsSkippedCount: Int
    public let itemsSucceededCount: Int
    public let itemsFailedCount: Int

    // 2. The 5 Storage Recovery Metrics
    /// Metric 1: Sum of logical file sizes of eligible items (deduplicated by inode/hard link).
    public let logicalBytesIdentified: Int64
    /// Metric 2: Estimated reclaimable storage accounting for physical block allocation and hard links.
    public let estimatedReclaimableBytes: Int64
    /// Metric 3: Total bytes associated with files successfully processed (trashed, quarantined, or removed).
    public let bytesSuccessfullyProcessed: Int64
    /// Metric 4: Observed filesystem capacity change from live macOS volume APIs (after.available - before.available).
    public let observedCapacityDelta: Int64
    /// Metric 5: Storage recovery supported by post-cleanup filesystem measurement.
    public let verifiedReclaimedBytes: Int64

    // 3. Filesystem Baselines
    public let beforeCapacity: VolumeSpace
    public let afterCapacity: VolumeSpace
    public let observedRawPhysicalDelta: Int64
    public let confidenceLevel: CleanupConfidenceLevel
    public let knownLimitations: [String]

    // 4. Execution Details & Timings
    public let scanDurationSeconds: TimeInterval
    public let cleanupDurationSeconds: TimeInterval
    public let timestamp: Date
    public let failedItems: [String: String] // path : reason
    public let recoveryMethodsUsed: [String: Int] // method name : count

    // Backward-compatibility aliases
    public var itemsProcessedCount: Int { itemsSucceededCount + itemsFailedCount }
    public var totalBytesReclaimed: Int64 { bytesSuccessfullyProcessed }

    public init(
        candidatesDiscoveredCount: Int,
        itemsEligibleCount: Int,
        itemsSkippedCount: Int,
        itemsSucceededCount: Int,
        itemsFailedCount: Int,
        logicalBytesIdentified: Int64,
        estimatedReclaimableBytes: Int64,
        bytesSuccessfullyProcessed: Int64,
        observedCapacityDelta: Int64,
        verifiedReclaimedBytes: Int64,
        beforeCapacity: VolumeSpace,
        afterCapacity: VolumeSpace,
        observedRawPhysicalDelta: Int64,
        confidenceLevel: CleanupConfidenceLevel,
        knownLimitations: [String],
        scanDurationSeconds: TimeInterval,
        cleanupDurationSeconds: TimeInterval,
        timestamp: Date = Date(),
        failedItems: [String: String],
        recoveryMethodsUsed: [String: Int]
    ) {
        self.candidatesDiscoveredCount = candidatesDiscoveredCount
        self.itemsEligibleCount = itemsEligibleCount
        self.itemsSkippedCount = itemsSkippedCount
        self.itemsSucceededCount = itemsSucceededCount
        self.itemsFailedCount = itemsFailedCount
        self.logicalBytesIdentified = logicalBytesIdentified
        self.estimatedReclaimableBytes = estimatedReclaimableBytes
        self.bytesSuccessfullyProcessed = bytesSuccessfullyProcessed
        self.observedCapacityDelta = observedCapacityDelta
        self.verifiedReclaimedBytes = verifiedReclaimedBytes
        self.beforeCapacity = beforeCapacity
        self.afterCapacity = afterCapacity
        self.observedRawPhysicalDelta = observedRawPhysicalDelta
        self.confidenceLevel = confidenceLevel
        self.knownLimitations = knownLimitations
        self.scanDurationSeconds = scanDurationSeconds
        self.cleanupDurationSeconds = cleanupDurationSeconds
        self.timestamp = timestamp
        self.failedItems = failedItems
        self.recoveryMethodsUsed = recoveryMethodsUsed
    }

    /// Convenience initializer for simplified test cases
    public init(
        itemsProcessedCount: Int,
        itemsSucceededCount: Int,
        itemsFailedCount: Int,
        totalBytesReclaimed: Int64,
        failedItems: [String: String]
    ) {
        self.candidatesDiscoveredCount = itemsProcessedCount
        self.itemsEligibleCount = itemsProcessedCount
        self.itemsSkippedCount = 0
        self.itemsSucceededCount = itemsSucceededCount
        self.itemsFailedCount = itemsFailedCount
        self.logicalBytesIdentified = totalBytesReclaimed
        self.estimatedReclaimableBytes = totalBytesReclaimed
        self.bytesSuccessfullyProcessed = totalBytesReclaimed
        self.observedCapacityDelta = totalBytesReclaimed
        self.verifiedReclaimedBytes = totalBytesReclaimed
        let dummyVol = VolumeSpace(
            totalCapacity: 250_000_000_000,
            availableCapacity: 100_000_000_000,
            importantAvailableCapacity: 100_000_000_000,
            opportunisticAvailableCapacity: 100_000_000_000,
            usedSpace: 150_000_000_000,
            volumeName: "Macintosh HD",
            mountPoint: "/"
        )
        self.beforeCapacity = dummyVol
        self.afterCapacity = dummyVol
        self.observedRawPhysicalDelta = totalBytesReclaimed
        self.confidenceLevel = .verifiedByFilesystem
        self.knownLimitations = []
        self.scanDurationSeconds = 0
        self.cleanupDurationSeconds = 0
        self.timestamp = Date()
        self.failedItems = failedItems
        self.recoveryMethodsUsed = ["Direct": itemsSucceededCount]
    }
}

/// Engine that safely executes cleanup actions following strict validation and recovery policies.
public actor CleanupEngine {
    private let quarantineManager: QuarantineManager
    private let journalManager: JournalManager
    private var isCancelled = false

    public init(
        quarantineManager: QuarantineManager = QuarantineManager(),
        journalManager: JournalManager = JournalManager.shared
    ) {
        self.quarantineManager = quarantineManager
        self.journalManager = journalManager
    }

    public func cancel() {
        isCancelled = true
    }

    /// Executes batch safe cleanup for all findings certified as Safe to Clean.
    public func executeSafeBatch(
        findings: [Finding],
        scanDuration: TimeInterval = 0,
        targetVolumeURL: URL = URL(fileURLWithPath: "/"),
        progressHandler: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async -> CleanupSummary {
        let eligible = findings.filter { $0.category.isBatchCleanEligible && $0.eligibility == .safeToClean }
        let skipped = findings.count - eligible.count
        return await executeItems(
            eligibleFindings: eligible,
            candidatesDiscoveredCount: findings.count,
            itemsSkippedCount: skipped,
            scanDuration: scanDuration,
            targetVolumeURL: targetVolumeURL,
            progressHandler: progressHandler
        )
    }

    /// Executes cleanup on explicitly selected individual findings.
    public func executeSelected(
        findings: [Finding],
        allDiscoveredCount: Int? = nil,
        scanDuration: TimeInterval = 0,
        targetVolumeURL: URL = URL(fileURLWithPath: "/"),
        progressHandler: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async -> CleanupSummary {
        let totalDiscovered = allDiscoveredCount ?? findings.count
        let skipped = max(0, totalDiscovered - findings.count)
        return await executeItems(
            eligibleFindings: findings,
            candidatesDiscoveredCount: totalDiscovered,
            itemsSkippedCount: skipped,
            scanDuration: scanDuration,
            targetVolumeURL: targetVolumeURL,
            progressHandler: progressHandler
        )
    }

    /// Deletes specific duplicate copies selected by user.
    public func deleteDuplicateCopies(
        members: [DuplicateMember],
        totalCandidateCopiesCount: Int? = nil,
        scanDuration: TimeInterval = 0,
        targetVolumeURL: URL = URL(fileURLWithPath: "/"),
        progressHandler: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async -> CleanupSummary {
        isCancelled = false
        let cleanupStartTime = Date()
        let beforeCapacity = VolumeSpace.queryVolume(at: targetVolumeURL)

        var succeeded = 0
        var failed = 0
        var bytesProcessed: Int64 = 0
        var failedDict: [String: String] = [:]
        var methodsCount: [String: Int] = [:]

        // Deduplicate logical & estimated sizes by inode
        var uniqueInodes = Set<String>()
        var logicalIdentified: Int64 = 0
        var estimatedReclaimable: Int64 = 0

        for m in members {
            var statBuf = stat()
            if lstat(m.path, &statBuf) == 0 {
                let key = "\(statBuf.st_dev):\(statBuf.st_ino)"
                if !uniqueInodes.contains(key) {
                    uniqueInodes.insert(key)
                    logicalIdentified += m.size
                    estimatedReclaimable += m.allocatedSize
                }
            } else {
                logicalIdentified += m.size
                estimatedReclaimable += m.allocatedSize
            }
        }

        var cleanedAncestorPaths = Set<String>()
        let sortedMembers = members.sorted { $0.path.count < $1.path.count }
        let total = sortedMembers.count

        for (idx, member) in sortedMembers.enumerated() {
            if isCancelled || Task.isCancelled { break }

            progressHandler?(CleanupProgress(
                completedCount: idx,
                totalCount: total,
                currentItemName: member.fileName,
                bytesReclaimedSoFar: bytesProcessed,
                isComplete: false
            ))

            // Check if this duplicate was already removed along with an ancestor directory
            if isDescendantOfAny(path: member.path, ancestors: cleanedAncestorPaths) {
                succeeded += 1
                methodsCount["macOSTrash", default: 0] += 1
                journalManager.record(JournalEntry(
                    originalPath: member.path,
                    sanitizedName: member.fileName,
                    actionType: .movedToTrash,
                    status: .success,
                    bytesReclaimed: 0,
                    recoveryMethod: .macOSTrash
                ))
                continue
            }

            // Revalidate immediately before destructive action
            let validation = SafetyValidator.validate(path: member.path)
            switch validation {
            case .failed(let reason):
                if isDescendantOfAny(path: member.path, ancestors: cleanedAncestorPaths) {
                    succeeded += 1
                    methodsCount["macOSTrash", default: 0] += 1
                    journalManager.record(JournalEntry(
                        originalPath: member.path,
                        sanitizedName: member.fileName,
                        actionType: .movedToTrash,
                        status: .success,
                        bytesReclaimed: 0,
                        recoveryMethod: .macOSTrash
                    ))
                } else {
                    failed += 1
                    failedDict[member.path] = reason
                    journalManager.record(JournalEntry(
                        originalPath: member.path,
                        sanitizedName: member.fileName,
                        actionType: .movedToTrash,
                        status: .failed,
                        bytesReclaimed: 0,
                        recoveryMethod: .macOSTrash,
                        errorMessage: reason
                    ))
                }
            case .passed:
                do {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: member.path), resultingItemURL: &resultingURL)
                    succeeded += 1
                    bytesProcessed += member.allocatedSize
                    methodsCount["macOSTrash", default: 0] += 1
                    cleanedAncestorPaths.insert(member.path)
                    journalManager.record(JournalEntry(
                        originalPath: member.path,
                        sanitizedName: member.fileName,
                        actionType: .movedToTrash,
                        status: .success,
                        bytesReclaimed: member.allocatedSize,
                        recoveryMethod: .macOSTrash
                    ))
                } catch {
                    failed += 1
                    failedDict[member.path] = error.localizedDescription
                    journalManager.record(JournalEntry(
                        originalPath: member.path,
                        sanitizedName: member.fileName,
                        actionType: .movedToTrash,
                        status: .failed,
                        bytesReclaimed: 0,
                        recoveryMethod: .macOSTrash,
                        errorMessage: error.localizedDescription
                    ))
                }
            }
        }

        progressHandler?(CleanupProgress(
            completedCount: total,
            totalCount: total,
            currentItemName: "Complete",
            bytesReclaimedSoFar: bytesProcessed,
            isComplete: true
        ))

        let cleanupDuration = Date().timeIntervalSince(cleanupStartTime)
        let afterCapacity = VolumeSpace.queryVolume(at: targetVolumeURL)
        let observedDelta = afterCapacity.availableCapacity - beforeCapacity.availableCapacity
        let observedRawDelta = afterCapacity.rawAvailableCapacity - beforeCapacity.rawAvailableCapacity

        let verifiedReclaimed: Int64
        let confidence: CleanupConfidenceLevel
        if observedDelta >= bytesProcessed && bytesProcessed > 0 {
            verifiedReclaimed = bytesProcessed
            confidence = .verifiedByFilesystem
        } else if observedDelta > 0 {
            verifiedReclaimed = min(bytesProcessed, observedDelta)
            confidence = .partiallyVerified
        } else if bytesProcessed > 0 {
            verifiedReclaimed = 0
            confidence = .delayedOrSnapshotRetained
        } else {
            verifiedReclaimed = 0
            confidence = .unverified
        }

        var limitations: [String] = []
        limitations.append("Duplicate files were moved to macOS Trash to allow instant user undo if needed.")
        limitations.append("Storage is fully reclaimed when Trash is emptied.")
        if afterCapacity.purgeableSpace > 0 {
            limitations.append("macOS System Settings Available Storage includes purgeable files managed asynchronously by the OS.")
        }

        let totalDiscovered = totalCandidateCopiesCount ?? members.count
        let skippedCount = max(0, totalDiscovered - members.count)

        return CleanupSummary(
            candidatesDiscoveredCount: totalDiscovered,
            itemsEligibleCount: members.count,
            itemsSkippedCount: skippedCount,
            itemsSucceededCount: succeeded,
            itemsFailedCount: failed,
            logicalBytesIdentified: logicalIdentified,
            estimatedReclaimableBytes: estimatedReclaimable,
            bytesSuccessfullyProcessed: bytesProcessed,
            observedCapacityDelta: observedDelta,
            verifiedReclaimedBytes: verifiedReclaimed,
            beforeCapacity: beforeCapacity,
            afterCapacity: afterCapacity,
            observedRawPhysicalDelta: observedRawDelta,
            confidenceLevel: confidence,
            knownLimitations: limitations,
            scanDurationSeconds: scanDuration,
            cleanupDurationSeconds: cleanupDuration,
            failedItems: failedDict,
            recoveryMethodsUsed: methodsCount
        )
    }

    private func executeItems(
        eligibleFindings: [Finding],
        candidatesDiscoveredCount: Int,
        itemsSkippedCount: Int,
        scanDuration: TimeInterval,
        targetVolumeURL: URL,
        progressHandler: (@Sendable (CleanupProgress) -> Void)?
    ) async -> CleanupSummary {
        isCancelled = false
        let cleanupStartTime = Date()
        let beforeCapacity = VolumeSpace.queryVolume(at: targetVolumeURL)

        var succeeded = 0
        var failed = 0
        var bytesProcessed: Int64 = 0
        var failedDict: [String: String] = [:]
        var methodsCount: [String: Int] = [:]

        // Deduplicate logical & estimated sizes by inode
        var uniqueInodes = Set<String>()
        var logicalIdentified: Int64 = 0
        var estimatedReclaimable: Int64 = 0

        for f in eligibleFindings {
            var statBuf = stat()
            if lstat(f.path, &statBuf) == 0 {
                let key = "\(statBuf.st_dev):\(statBuf.st_ino)"
                if !uniqueInodes.contains(key) {
                    uniqueInodes.insert(key)
                    logicalIdentified += f.logicalSize
                    estimatedReclaimable += f.estimatedReclaimableBytes
                }
            } else {
                logicalIdentified += f.logicalSize
                estimatedReclaimable += f.estimatedReclaimableBytes
            }
        }

        // Sort by path length ascending so parent folders are processed before nested child contents
        let sorted = eligibleFindings.sorted { $0.path.count < $1.path.count }
        var cleanedAncestorPaths = Set<String>()
        let total = sorted.count

        for (idx, finding) in sorted.enumerated() {
            if isCancelled || Task.isCancelled { break }

            let url = URL(fileURLWithPath: finding.path)
            progressHandler?(CleanupProgress(
                completedCount: idx,
                totalCount: total,
                currentItemName: url.lastPathComponent,
                bytesReclaimedSoFar: bytesProcessed,
                isComplete: false
            ))

            // Check if this item's container was already trashed/cleaned in this batch
            if isDescendantOfAny(path: finding.path, ancestors: cleanedAncestorPaths) {
                succeeded += 1
                methodsCount[actionStringFor(method: finding.recoveryMethod), default: 0] += 1
                journalManager.record(JournalEntry(
                    originalPath: finding.path,
                    sanitizedName: url.lastPathComponent,
                    actionType: actionTypeFor(method: finding.recoveryMethod),
                    status: .success,
                    bytesReclaimed: 0,
                    recoveryMethod: finding.recoveryMethod
                ))
                continue
            }

            // Step 1: Pre-flight Safety Validation (TOCTOU defense)
            let validation = SafetyValidator.validate(path: finding.path)
            guard case .passed = validation else {
                if case .failed(let reason) = validation {
                    if isDescendantOfAny(path: finding.path, ancestors: cleanedAncestorPaths) {
                        succeeded += 1
                        methodsCount[actionStringFor(method: finding.recoveryMethod), default: 0] += 1
                        journalManager.record(JournalEntry(
                            originalPath: finding.path,
                            sanitizedName: url.lastPathComponent,
                            actionType: actionTypeFor(method: finding.recoveryMethod),
                            status: .success,
                            bytesReclaimed: 0,
                            recoveryMethod: finding.recoveryMethod
                        ))
                    } else {
                        failed += 1
                        failedDict[finding.path] = reason
                        journalManager.record(JournalEntry(
                            originalPath: finding.path,
                            sanitizedName: url.lastPathComponent,
                            actionType: actionTypeFor(method: finding.recoveryMethod),
                            status: .failed,
                            bytesReclaimed: 0,
                            recoveryMethod: finding.recoveryMethod,
                            errorMessage: reason
                        ))
                    }
                }
                continue
            }

            // Step 2: Execute based on approved recovery method
            do {
                switch finding.recoveryMethod {
                case .macOSTrash:
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                    succeeded += 1
                    bytesProcessed += finding.allocatedSize
                    methodsCount["macOSTrash", default: 0] += 1
                    cleanedAncestorPaths.insert(finding.path)
                    journalManager.record(JournalEntry(
                        originalPath: finding.path,
                        sanitizedName: url.lastPathComponent,
                        actionType: .movedToTrash,
                        status: .success,
                        bytesReclaimed: finding.allocatedSize,
                        recoveryMethod: .macOSTrash
                    ))

                case .managedQuarantine:
                    let record = try await quarantineManager.quarantineFile(at: finding.path)
                    succeeded += 1
                    bytesProcessed += finding.allocatedSize
                    methodsCount["managedQuarantine", default: 0] += 1
                    cleanedAncestorPaths.insert(finding.path)
                    journalManager.record(JournalEntry(
                        originalPath: finding.path,
                        sanitizedName: url.lastPathComponent,
                        actionType: .movedToQuarantine,
                        status: .success,
                        bytesReclaimed: finding.allocatedSize,
                        recoveryMethod: .managedQuarantine,
                        quarantineId: record.id
                    ))

                case .directRemoval:
                    try FileManager.default.removeItem(at: url)
                    succeeded += 1
                    bytesProcessed += finding.allocatedSize
                    methodsCount["directRemoval", default: 0] += 1
                    cleanedAncestorPaths.insert(finding.path)
                    journalManager.record(JournalEntry(
                        originalPath: finding.path,
                        sanitizedName: url.lastPathComponent,
                        actionType: .directRemoved,
                        status: .success,
                        bytesReclaimed: finding.allocatedSize,
                        recoveryMethod: .directRemoval
                    ))
                }
            } catch {
                failed += 1
                failedDict[finding.path] = error.localizedDescription
                journalManager.record(JournalEntry(
                    originalPath: finding.path,
                    sanitizedName: url.lastPathComponent,
                    actionType: actionTypeFor(method: finding.recoveryMethod),
                    status: .failed,
                    bytesReclaimed: 0,
                    recoveryMethod: finding.recoveryMethod,
                    errorMessage: error.localizedDescription
                ))
            }
        }

        progressHandler?(CleanupProgress(
            completedCount: total,
            totalCount: total,
            currentItemName: "Complete",
            bytesReclaimedSoFar: bytesProcessed,
            isComplete: true
        ))

        let cleanupDuration = Date().timeIntervalSince(cleanupStartTime)
        let afterCapacity = VolumeSpace.queryVolume(at: targetVolumeURL)
        let observedDelta = afterCapacity.availableCapacity - beforeCapacity.availableCapacity
        let observedRawDelta = afterCapacity.rawAvailableCapacity - beforeCapacity.rawAvailableCapacity

        let verifiedReclaimed: Int64
        let confidence: CleanupConfidenceLevel
        if observedDelta >= bytesProcessed && bytesProcessed > 0 {
            verifiedReclaimed = bytesProcessed
            confidence = .verifiedByFilesystem
        } else if observedDelta > 0 {
            verifiedReclaimed = min(bytesProcessed, observedDelta)
            confidence = .partiallyVerified
        } else if bytesProcessed > 0 {
            verifiedReclaimed = 0
            confidence = .delayedOrSnapshotRetained
        } else {
            verifiedReclaimed = 0
            confidence = .unverified
        }

        var limitations: [String] = []
        if methodsCount["macOSTrash", default: 0] > 0 {
            limitations.append("Files moved to macOS Trash continue to occupy APFS volume storage until the user empties Trash.")
        }
        if methodsCount["managedQuarantine", default: 0] > 0 {
            limitations.append("Files moved to Managed Quarantine (~/.squirrel/quarantine) remain stored for safe undo and can be restored or purged.")
        }
        if afterCapacity.purgeableSpace > 0 {
            limitations.append("macOS System Settings Available Storage includes \(ByteCountFormatter.string(fromByteCount: afterCapacity.purgeableSpace, countStyle: .file)) of purgeable space managed asynchronously by the OS.")
        }
        limitations.append("APFS container free blocks may be deferred if local APFS snapshots (e.g. Time Machine) retain file extents.")
        if observedDelta <= 0 && bytesProcessed > 0 {
            limitations.append("Concurrent background macOS tasks (system logs, caches, background downloads) wrote to disk during the cleanup window.")
        }

        return CleanupSummary(
            candidatesDiscoveredCount: candidatesDiscoveredCount,
            itemsEligibleCount: eligibleFindings.count,
            itemsSkippedCount: itemsSkippedCount,
            itemsSucceededCount: succeeded,
            itemsFailedCount: failed,
            logicalBytesIdentified: logicalIdentified,
            estimatedReclaimableBytes: estimatedReclaimable,
            bytesSuccessfullyProcessed: bytesProcessed,
            observedCapacityDelta: observedDelta,
            verifiedReclaimedBytes: verifiedReclaimed,
            beforeCapacity: beforeCapacity,
            afterCapacity: afterCapacity,
            observedRawPhysicalDelta: observedRawDelta,
            confidenceLevel: confidence,
            knownLimitations: limitations,
            scanDurationSeconds: scanDuration,
            cleanupDurationSeconds: cleanupDuration,
            failedItems: failedDict,
            recoveryMethodsUsed: methodsCount
        )
    }

    private func isDescendantOfAny(path: String, ancestors: Set<String>) -> Bool {
        for ancestor in ancestors {
            let prefix = ancestor.hasSuffix("/") ? ancestor : "\(ancestor)/"
            if path.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    private func actionTypeFor(method: RecoveryMethod) -> JournalActionType {
        switch method {
        case .macOSTrash: return .movedToTrash
        case .managedQuarantine: return .movedToQuarantine
        case .directRemoval: return .directRemoved
        }
    }

    private func actionStringFor(method: RecoveryMethod) -> String {
        switch method {
        case .macOSTrash: return "macOSTrash"
        case .managedQuarantine: return "managedQuarantine"
        case .directRemoval: return "directRemoval"
        }
    }
}
