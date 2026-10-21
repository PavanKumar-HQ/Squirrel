import Foundation
import CryptoKit

/// Metadata record for a file placed in managed quarantine.
public struct QuarantineRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let originalPath: String
    public let quarantinedFileName: String
    public let timestamp: Date
    public let fileSize: Int64
    public let sha256: String
    public let permissions: UInt16

    public init(
        id: String = UUID().uuidString,
        originalPath: String,
        quarantinedFileName: String,
        timestamp: Date = Date(),
        fileSize: Int64,
        sha256: String,
        permissions: UInt16
    ) {
        self.id = id
        self.originalPath = originalPath
        self.quarantinedFileName = quarantinedFileName
        self.timestamp = timestamp
        self.fileSize = fileSize
        self.sha256 = sha256
        self.permissions = permissions
    }
}

/// Actor managing quarantine storage, manifests, and safe restoration.
public actor QuarantineManager {
    private let quarantineDir: URL
    private let manifestURL: URL
    private var records: [QuarantineRecord] = []

    public init(customBaseDir: URL? = nil) {
        let base: URL
        if let customBaseDir = customBaseDir {
            base = customBaseDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            base = appSupport.appendingPathComponent("Squirrel", isDirectory: true)
        }
        self.quarantineDir = base.appendingPathComponent("Quarantine", isDirectory: true)
        self.manifestURL = quarantineDir.appendingPathComponent("quarantine_manifest.json")

        try? FileManager.default.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
        // Set directory permissions to 0700 (owner only)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: quarantineDir.path)

        // Load manifest synchronously in init
        if let data = try? Data(contentsOf: manifestURL),
           let loaded = try? JSONDecoder().decode([QuarantineRecord].self, from: data) {
            self.records = loaded
        }
    }

    /// Moves a file to quarantine and logs its manifest entry.
    public func quarantineFile(at path: String) throws -> QuarantineRecord {
        guard FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "QuarantineError", code: 404, userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(path)"])
        }

        let sourceURL = URL(fileURLWithPath: path)
        let fileData = (try? Data(contentsOf: sourceURL)) ?? Data()
        let digest = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int64) ?? Int64(fileData.count)
        let permissions = (attrs[.posixPermissions] as? UInt16) ?? 0o644

        let recordId = UUID().uuidString
        let safeExt = sourceURL.pathExtension.isEmpty ? "" : ".\(sourceURL.pathExtension)"
        let targetFileName = "\(recordId)\(safeExt)"
        let targetURL = quarantineDir.appendingPathComponent(targetFileName)

        // Atomic move
        try FileManager.default.moveItem(at: sourceURL, to: targetURL)

        let record = QuarantineRecord(
            id: recordId,
            originalPath: path,
            quarantinedFileName: targetFileName,
            timestamp: Date(),
            fileSize: size,
            sha256: digest,
            permissions: permissions
        )

        records.append(record)
        try saveManifest()
        return record
    }

    /// Restores a quarantined file back to its original location, resolving collisions if necessary.
    public func restoreFile(recordId: String) throws -> String {
        guard let index = records.firstIndex(where: { $0.id == recordId }) else {
            throw NSError(domain: "QuarantineError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Quarantine record not found for ID: \(recordId)"])
        }

        let record = records[index]
        let quarantinedURL = quarantineDir.appendingPathComponent(record.quarantinedFileName)

        guard FileManager.default.fileExists(atPath: quarantinedURL.path) else {
            throw NSError(domain: "QuarantineError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Quarantined archive file missing from storage."])
        }

        // Determine destination URL
        var destURL = URL(fileURLWithPath: record.originalPath)
        let originalDir = destURL.deletingLastPathComponent()

        // Ensure parent directory exists
        try FileManager.default.createDirectory(at: originalDir, withIntermediateDirectories: true)

        // Collision check
        if FileManager.default.fileExists(atPath: destURL.path) {
            let baseName = destURL.deletingPathExtension().lastPathComponent
            let ext = destURL.pathExtension.isEmpty ? "" : ".\(destURL.pathExtension)"
            let newName = "\(baseName)_restored_\(Int(Date().timeIntervalSince1970))\(ext)"
            destURL = originalDir.appendingPathComponent(newName)
        }

        try FileManager.default.moveItem(at: quarantinedURL, to: destURL)

        // Restore original permissions
        try? FileManager.default.setAttributes([.posixPermissions: record.permissions], ofItemAtPath: destURL.path)

        // Remove from active records
        records.remove(at: index)
        try saveManifest()

        return destURL.path
    }

    public func getRecords() -> [QuarantineRecord] {
        return records
    }

    private func saveManifest() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: manifestURL, options: .atomic)
    }
}
