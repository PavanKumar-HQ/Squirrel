import Foundation

/// Represents a single file member in a duplicate group.
public struct DuplicateMember: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let path: String
    public let fileName: String
    public let size: Int64
    public let allocatedSize: Int64
    public let modificationDate: Date?
    public let creationDate: Date?
    public let isRecommendedToKeep: Bool
    public let keepReason: String?

    public init(
        id: UUID = UUID(),
        path: String,
        fileName: String,
        size: Int64,
        allocatedSize: Int64,
        modificationDate: Date?,
        creationDate: Date?,
        isRecommendedToKeep: Bool = false,
        keepReason: String? = nil
    ) {
        self.id = id
        self.path = path
        self.fileName = fileName
        self.size = size
        self.allocatedSize = allocatedSize
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.isRecommendedToKeep = isRecommendedToKeep
        self.keepReason = keepReason
    }
}

/// Represents a set of files with identical cryptographic content hash.
public struct DuplicateGroup: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let sha256Hash: String
    public let fileSize: Int64
    public let files: [DuplicateMember]
    public let potentialReclaimableBytes: Int64

    public init(
        id: UUID = UUID(),
        sha256Hash: String,
        fileSize: Int64,
        files: [DuplicateMember]
    ) {
        self.id = id
        self.sha256Hash = sha256Hash
        self.fileSize = fileSize
        self.files = files
        // If there are N copies of size S, keeping 1 copy means reclaiming (N - 1) * S bytes.
        self.potentialReclaimableBytes = files.count > 1 ? Int64(files.count - 1) * fileSize : 0
    }
}
