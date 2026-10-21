import Foundation

/// Represents a raw filesystem node discovered during traversal.
public struct StorageItem: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let url: URL
    public let path: String
    public let name: String
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let deviceId: dev_t
    public let inode: ino_t
    public let modificationDate: Date?
    public let isReadable: Bool
    public let isWritable: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        path: String,
        name: String,
        logicalSize: Int64,
        allocatedSize: Int64,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        deviceId: dev_t,
        inode: ino_t,
        modificationDate: Date?,
        isReadable: Bool,
        isWritable: Bool
    ) {
        self.id = id
        self.url = url
        self.path = path
        self.name = name
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.deviceId = deviceId
        self.inode = inode
        self.modificationDate = modificationDate
        self.isReadable = isReadable
        self.isWritable = isWritable
    }
}
