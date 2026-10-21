import Foundation

/// Action performed on a filesystem item.
public enum JournalActionType: String, Codable, Sendable {
    case movedToTrash = "Moved to Trash"
    case movedToQuarantine = "Moved to Quarantine"
    case directRemoved = "Directly Removed"
    case restoredFromQuarantine = "Restored from Quarantine"
}

/// Execution outcome of an operation.
public enum JournalStatus: String, Codable, Sendable {
    case success = "Success"
    case failed = "Failed"
    case restored = "Restored"
}

/// An entry in the cleanup operation journal.
public struct JournalEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let originalPath: String
    public let sanitizedName: String
    public let actionType: JournalActionType
    public let status: JournalStatus
    public let bytesReclaimed: Int64
    public let recoveryMethod: RecoveryMethod
    public let quarantineId: String?
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        originalPath: String,
        sanitizedName: String,
        actionType: JournalActionType,
        status: JournalStatus,
        bytesReclaimed: Int64,
        recoveryMethod: RecoveryMethod,
        quarantineId: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalPath = originalPath
        self.sanitizedName = sanitizedName
        self.actionType = actionType
        self.status = status
        self.bytesReclaimed = bytesReclaimed
        self.recoveryMethod = recoveryMethod
        self.quarantineId = quarantineId
        self.errorMessage = errorMessage
    }
}

/// Persistent journal manager for operation logs.
public final class JournalManager: @unchecked Sendable {
    public static let shared = JournalManager()
    private let storageURL: URL
    private let queue = DispatchQueue(label: "com.storagecleaner.journal", qos: .utility)
    private var entries: [JournalEntry] = []

    public init(customStorageURL: URL? = nil) {
        if let customStorageURL = customStorageURL {
            self.storageURL = customStorageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent("Squirrel", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.storageURL = appDir.appendingPathComponent("operation_journal.json")
        }
        load()
    }

    public func record(_ entry: JournalEntry) {
        queue.sync {
            entries.insert(entry, at: 0)
            save()
        }
    }

    public func getEntries() -> [JournalEntry] {
        queue.sync { entries }
    }

    public func updateStatus(entryId: UUID, newStatus: JournalStatus, errorMessage: String? = nil) {
        queue.sync {
            if let index = entries.firstIndex(where: { $0.id == entryId }) {
                let old = entries[index]
                entries[index] = JournalEntry(
                    id: old.id,
                    timestamp: old.timestamp,
                    originalPath: old.originalPath,
                    sanitizedName: old.sanitizedName,
                    actionType: old.actionType,
                    status: newStatus,
                    bytesReclaimed: old.bytesReclaimed,
                    recoveryMethod: old.recoveryMethod,
                    quarantineId: old.quarantineId,
                    errorMessage: errorMessage ?? old.errorMessage
                )
                save()
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([JournalEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Log locally without crash
        }
    }
}
