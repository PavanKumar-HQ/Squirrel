import Foundation

/// Safety classification for a cleanup candidate.
public enum CleanupEligibility: String, Codable, Sendable, CaseIterable {
    case safeToClean = "Safe to Clean"
    case reviewRecommended = "Review Recommended"
    case keep = "Keep / Not Recommended"
}

/// Risk level associated with removing a candidate item.
public enum RiskLevel: String, Codable, Sendable {
    case low = "Low Risk"
    case medium = "Medium Risk"
    case high = "High Risk"
}

/// Mechanism used to safely handle deletion/recovery.
public enum RecoveryMethod: String, Codable, Sendable {
    case macOSTrash = "macOS Trash"
    case managedQuarantine = "Managed Quarantine"
    case directRemoval = "Direct Removal"
}

/// A structured finding with full traceable evidence.
public struct Finding: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let category: StorageCategory
    public let title: String
    public let path: String
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let modificationDate: Date?
    public let ruleId: String
    public let ruleDescription: String
    public let evidence: [String]
    public let eligibility: CleanupEligibility
    public let riskLevel: RiskLevel
    public let recoveryMethod: RecoveryMethod
    public let estimatedReclaimableBytes: Int64
    public let consequencesExplanation: String
    public let exclusionReason: String?

    public init(
        id: UUID = UUID(),
        category: StorageCategory,
        title: String,
        path: String,
        logicalSize: Int64,
        allocatedSize: Int64,
        modificationDate: Date? = nil,
        ruleId: String,
        ruleDescription: String,
        evidence: [String],
        eligibility: CleanupEligibility,
        riskLevel: RiskLevel,
        recoveryMethod: RecoveryMethod,
        estimatedReclaimableBytes: Int64,
        consequencesExplanation: String = "Safe removal",
        exclusionReason: String? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.path = path
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.modificationDate = modificationDate
        self.ruleId = ruleId
        self.ruleDescription = ruleDescription
        self.evidence = evidence
        self.eligibility = eligibility
        self.riskLevel = riskLevel
        self.recoveryMethod = recoveryMethod
        self.estimatedReclaimableBytes = estimatedReclaimableBytes
        self.consequencesExplanation = consequencesExplanation
        self.exclusionReason = exclusionReason
    }
}
