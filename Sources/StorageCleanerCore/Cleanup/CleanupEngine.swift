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

/// Result summary of a cleanup execution run.
public struct CleanupSummary: Sendable, Codable, Equatable {
    public let itemsProcessedCount: Int
    public let itemsSucceededCount: Int
    public let itemsFailedCount: Int
    public let totalBytesReclaimed: Int64
    public let failedItems: [String: String] // path : reason

    public init(
        itemsProcessedCount: Int,
        itemsSucceededCount: Int,
        itemsFailedCount: Int,
        totalBytesReclaimed: Int64,
        failedItems: [String: String]
    ) {
        self.itemsProcessedCount = itemsProcessedCount
        self.itemsSucceededCount = itemsSucceededCount
        self.itemsFailedCount = itemsFailedCount
        self.totalBytesReclaimed = totalBytesReclaimed
        self.failedItems = failedItems
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
        progressHandler: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async -> CleanupSummary {
        // Enforce batch safety policy: only batch-eligible categories with .safeToClean eligibility
        let eligible = findings.filter { $0.category.isBatchCleanEligible && $0.eligibility == .safeToClean }
        return await executeItems(findings: eligible, progressHandler: progressHandler)
    }

    /// Executes cleanup on explicitly selected individual findings.
    public func executeSelected(
        findings: [Finding],
        progressHandler: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async -> CleanupSummary {
        return await executeItems(findings: findings, progressHandler: progressHandler)
    }

    /// Deletes specific duplicate copies selected by user.
    public func deleteDuplicateCopies(
        members: [DuplicateMember],
        progressHandler: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async -> CleanupSummary {
        isCancelled = false
        var succeeded = 0
        var failed = 0
        var bytesReclaimed: Int64 = 0
        var failedDict: [String: String] = [:]

        let total = members.count

        for (idx, member) in members.enumerated() {
            if isCancelled || Task.isCancelled { break }

            progressHandler?(CleanupProgress(
                completedCount: idx,
                totalCount: total,
                currentItemName: member.fileName,
                bytesReclaimedSoFar: bytesReclaimed,
                isComplete: false
            ))

            // Revalidate
            let validation = SafetyValidator.validate(path: member.path)
            switch validation {
            case .failed(let reason):
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
            case .passed:
                do {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: member.path), resultingItemURL: &resultingURL)
                    succeeded += 1
                    bytesReclaimed += member.allocatedSize
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
            bytesReclaimedSoFar: bytesReclaimed,
            isComplete: true
        ))

        return CleanupSummary(
            itemsProcessedCount: succeeded + failed,
            itemsSucceededCount: succeeded,
            itemsFailedCount: failed,
            totalBytesReclaimed: bytesReclaimed,
            failedItems: failedDict
        )
    }

    private func executeItems(
        findings: [Finding],
        progressHandler: (@Sendable (CleanupProgress) -> Void)?
    ) async -> CleanupSummary {
        isCancelled = false
        var succeeded = 0
        var failed = 0
        var bytesReclaimed: Int64 = 0
        var failedDict: [String: String] = [:]

        let total = findings.count

        for (idx, finding) in findings.enumerated() {
            if isCancelled || Task.isCancelled { break }

            let url = URL(fileURLWithPath: finding.path)
            progressHandler?(CleanupProgress(
                completedCount: idx,
                totalCount: total,
                currentItemName: url.lastPathComponent,
                bytesReclaimedSoFar: bytesReclaimed,
                isComplete: false
            ))

            // Step 1: Pre-flight Safety Validation
            let validation = SafetyValidator.validate(path: finding.path)
            guard case .passed = validation else {
                if case .failed(let reason) = validation {
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
                continue
            }

            // Step 2: Execute based on approved recovery method
            do {
                switch finding.recoveryMethod {
                case .macOSTrash:
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                    succeeded += 1
                    bytesReclaimed += finding.allocatedSize
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
                    bytesReclaimed += finding.allocatedSize
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
                    bytesReclaimed += finding.allocatedSize
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
            bytesReclaimedSoFar: bytesReclaimed,
            isComplete: true
        ))

        return CleanupSummary(
            itemsProcessedCount: succeeded + failed,
            itemsSucceededCount: succeeded,
            itemsFailedCount: failed,
            totalBytesReclaimed: bytesReclaimed,
            failedItems: failedDict
        )
    }

    private func actionTypeFor(method: RecoveryMethod) -> JournalActionType {
        switch method {
        case .macOSTrash: return .movedToTrash
        case .managedQuarantine: return .movedToQuarantine
        case .directRemoval: return .directRemoved
        }
    }
}
