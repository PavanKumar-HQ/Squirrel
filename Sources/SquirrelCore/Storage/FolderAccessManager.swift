import Foundation
import os

/// Status of an authorized directory bookmark.
public enum FolderAccessStatus: String, Codable, Sendable, CaseIterable {
    case valid = "Authorized"
    case stale = "Stale (Refreshed)"
    case notFound = "Folder Moved or Deleted"
    case permissionRestricted = "Permission Restricted"
    case revoked = "Revoked"

    public var iconName: String {
        switch self {
        case .valid: return "checkmark.circle.fill"
        case .stale: return "arrow.triangle.2.circlepath.circle.fill"
        case .notFound: return "exclamationmark.triangle.fill"
        case .permissionRestricted: return "lock.shield.fill"
        case .revoked: return "xmark.circle.fill"
        }
    }
}

/// Persistent record of a user-authorized directory bookmark.
public struct AuthorizedFolderRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var bookmarkData: Data
    public var resolvedPath: String
    public let displayName: String
    public let authorizedDate: Date
    public var lastAccessedDate: Date?
    public var isSecurityScoped: Bool
    public var status: FolderAccessStatus

    public init(
        id: UUID = UUID(),
        bookmarkData: Data,
        resolvedPath: String,
        displayName: String,
        authorizedDate: Date = Date(),
        lastAccessedDate: Date? = nil,
        isSecurityScoped: Bool,
        status: FolderAccessStatus = .valid
    ) {
        self.id = id
        self.bookmarkData = bookmarkData
        self.resolvedPath = resolvedPath
        self.displayName = displayName
        self.authorizedDate = authorizedDate
        self.lastAccessedDate = lastAccessedDate
        self.isSecurityScoped = isSecurityScoped
        self.status = status
    }
}

/// Safe wrapper guaranteeing balanced start/stop of security-scoped resource access.
public final class FolderAccessScope: Sendable {
    public let url: URL
    public let isSecurityScoped: Bool
    private let didStart: Bool
    private let isStopped = OSAllocatedUnfairLock(initialState: false)

    public init(url: URL, isSecurityScoped: Bool) {
        self.url = url
        self.isSecurityScoped = isSecurityScoped
        if isSecurityScoped {
            self.didStart = url.startAccessingSecurityScopedResource()
        } else {
            self.didStart = true
        }
    }

    public func stop() {
        isStopped.withLock { stopped in
            guard !stopped else { return }
            stopped = true
            if isSecurityScoped && didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    deinit {
        stop()
    }
}

/// Errors occurring during folder access management.
public enum FolderAccessError: LocalizedError, Sendable {
    case bookmarkCreationFailed(String)
    case bookmarkResolutionFailed(String)
    case pathNotFound(String)
    case permissionDenied(String)
    case recordNotFound

    public var errorDescription: String? {
        switch self {
        case .bookmarkCreationFailed(let msg):
            return "Failed to create security-scoped bookmark: \(msg)"
        case .bookmarkResolutionFailed(let msg):
            return "Failed to resolve saved bookmark: \(msg)"
        case .pathNotFound(let path):
            return "Directory at path no longer exists: \(path)"
        case .permissionDenied(let path):
            return "Read permission restricted by macOS for directory: \(path)"
        case .recordNotFound:
            return "Authorization record not found."
        }
    }
}

/// Centralized manager for persistent security-scoped and standard folder authorization.
public final class FolderAccessManager: @unchecked Sendable {
    public static let shared = FolderAccessManager()

    private let manifestURL: URL
    private let lock = NSLock()
    private var records: [AuthorizedFolderRecord] = []

    public init(customManifestURL: URL? = nil) {
        if let custom = customManifestURL {
            self.manifestURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let squirrelDir = appSupport.appendingPathComponent("Squirrel", isDirectory: true)
            try? FileManager.default.createDirectory(at: squirrelDir, withIntermediateDirectories: true)
            self.manifestURL = squirrelDir.appendingPathComponent("authorized_folders.json")
        }
        loadRecords()
    }

    // MARK: - Persistence

    private func loadRecords() {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            self.records = []
            return
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            self.records = try JSONDecoder().decode([AuthorizedFolderRecord].self, from: data)
        } catch {
            self.records = []
        }
    }

    private func saveRecords() {
        // Must be called with lock held
        do {
            let dir = manifestURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: manifestURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        } catch {
            // Log or ignore
        }
    }

    // MARK: - Query & Records

    public func getRecords() -> [AuthorizedFolderRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    public func findRecord(byId id: UUID) -> AuthorizedFolderRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records.first { $0.id == id }
    }

    private func normalizePath(for url: URL) -> String {
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    public func findRecord(for url: URL) -> AuthorizedFolderRecord? {
        lock.lock()
        defer { lock.unlock() }
        let targetPath = normalizePath(for: url)
        
        // Exact match first
        if let exact = records.first(where: { $0.resolvedPath == targetPath && $0.status != .revoked }) {
            return exact
        }
        
        // Parent folder match (access to parent grants access to descendant)
        return records.first(where: {
            guard $0.status != .revoked else { return false }
            let parentPrefix = $0.resolvedPath.hasSuffix("/") ? $0.resolvedPath : "\($0.resolvedPath)/"
            return targetPath.hasPrefix(parentPrefix)
        })
    }

    public func hasValidAuthorization(for url: URL) -> Bool {
        guard let record = findRecord(for: url) else { return false }
        return record.status == .valid || record.status == .stale
    }

    // MARK: - Authorization Lifecycle

    /// Grants and persists authorization for a user-selected folder URL.
    @discardableResult
    public func grantAccess(for url: URL) throws -> AuthorizedFolderRecord {
        lock.lock()
        defer { lock.unlock() }

        let standardizedURL = url.standardizedFileURL
        let canonicalPath = normalizePath(for: standardizedURL)
        let displayName = standardizedURL.lastPathComponent.isEmpty ? standardizedURL.path : standardizedURL.lastPathComponent

        var bookmarkData: Data
        var isSecurityScoped = false

        // Attempt 1: Security-scoped bookmark (required for App Sandbox)
        do {
            bookmarkData = try standardizedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [.isDirectoryKey, .pathKey],
                relativeTo: nil
            )
            isSecurityScoped = true
        } catch {
            // Attempt 2: Standard persistent bookmark (for native un-sandboxed execution)
            do {
                bookmarkData = try standardizedURL.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: [.isDirectoryKey, .pathKey],
                    relativeTo: nil
                )
                isSecurityScoped = false
            } catch let creationErr {
                throw FolderAccessError.bookmarkCreationFailed(creationErr.localizedDescription)
            }
        }

        // Check if record already exists for this path
        if let existingIdx = records.firstIndex(where: { $0.resolvedPath == canonicalPath }) {
            var updated = records[existingIdx]
            updated.bookmarkData = bookmarkData
            updated.isSecurityScoped = isSecurityScoped
            updated.lastAccessedDate = Date()
            updated.status = .valid
            records[existingIdx] = updated
            saveRecords()
            return updated
        } else {
            let record = AuthorizedFolderRecord(
                bookmarkData: bookmarkData,
                resolvedPath: canonicalPath,
                displayName: displayName,
                authorizedDate: Date(),
                lastAccessedDate: Date(),
                isSecurityScoped: isSecurityScoped,
                status: .valid
            )
            records.append(record)
            saveRecords()
            return record
        }
    }

    /// Resolves an authorization record into an active access scope.
    public func resolveAccess(for record: AuthorizedFolderRecord) throws -> (URL, FolderAccessScope) {
        var isStale = false
        var resolvedURL: URL?

        if record.isSecurityScoped {
            do {
                resolvedURL = try URL(
                    resolvingBookmarkData: record.bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } catch {
                // Fallback to standard resolution
                resolvedURL = try? URL(
                    resolvingBookmarkData: record.bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            }
        } else {
            resolvedURL = try? URL(
                resolvingBookmarkData: record.bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }

        guard let validURL = resolvedURL else {
            updateRecordStatus(id: record.id, status: .notFound)
            throw FolderAccessError.bookmarkResolutionFailed("Could not resolve stored bookmark data.")
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: validURL.path) else {
            updateRecordStatus(id: record.id, status: .notFound)
            throw FolderAccessError.pathNotFound(validURL.path)
        }

        guard fm.isReadableFile(atPath: validURL.path) else {
            updateRecordStatus(id: record.id, status: .permissionRestricted)
            throw FolderAccessError.permissionDenied(validURL.path)
        }

        // If stale, refresh bookmark
        if isStale {
            refreshStaleBookmark(id: record.id, url: validURL, isSecurityScoped: record.isSecurityScoped)
        } else if record.status != .valid {
            updateRecordStatus(id: record.id, status: .valid)
        }

        let scope = FolderAccessScope(url: validURL, isSecurityScoped: record.isSecurityScoped)
        return (validURL, scope)
    }

    /// Executes an async operation with balanced security-scoped resource access.
    public func withAccess<T>(to record: AuthorizedFolderRecord, operation: (URL) async throws -> T) async throws -> T {
        let (url, scope) = try resolveAccess(for: record)
        defer {
            scope.stop()
        }
        updateLastAccessed(id: record.id)
        return try await operation(url)
    }

    /// Executes an async operation across multiple URLs, wrapping any authorized folders in balanced access scopes.
    public func withAccess<T>(to urls: [URL], operation: ([URL]) async throws -> T) async throws -> T {
        var scopes: [FolderAccessScope] = []
        defer {
            for scope in scopes.reversed() {
                scope.stop()
            }
        }

        var preparedURLs: [URL] = []
        for url in urls {
            if let record = findRecord(for: url), let (resolved, scope) = try? resolveAccess(for: record) {
                scopes.append(scope)
                preparedURLs.append(resolved)
                updateLastAccessed(id: record.id)
            } else {
                preparedURLs.append(url)
            }
        }

        return try await operation(preparedURLs)
    }

    public func revokeAccess(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = records.firstIndex(where: { $0.id == id }) {
            records[idx].status = .revoked
            saveRecords()
        }
    }

    public func removeRecord(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll { $0.id == id }
        saveRecords()
    }

    public func refreshAllStatuses() {
        lock.lock()
        let currentRecords = records
        lock.unlock()

        let fm = FileManager.default
        for record in currentRecords {
            guard record.status != .revoked else { continue }
            
            var isStale = false
            let resolved: URL?
            if record.isSecurityScoped {
                resolved = (try? URL(resolvingBookmarkData: record.bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)) ??
                           (try? URL(resolvingBookmarkData: record.bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale))
            } else {
                resolved = try? URL(resolvingBookmarkData: record.bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            }

            guard let url = resolved, fm.fileExists(atPath: url.path) else {
                updateRecordStatus(id: record.id, status: .notFound)
                continue
            }

            guard fm.isReadableFile(atPath: url.path) else {
                updateRecordStatus(id: record.id, status: .permissionRestricted)
                continue
            }

            if isStale {
                refreshStaleBookmark(id: record.id, url: url, isSecurityScoped: record.isSecurityScoped)
            } else {
                updateRecordStatus(id: record.id, status: .valid)
            }
        }
    }

    private func updateRecordStatus(id: UUID, status: FolderAccessStatus) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = records.firstIndex(where: { $0.id == id }) {
            records[idx].status = status
            saveRecords()
        }
    }

    private func updateLastAccessed(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = records.firstIndex(where: { $0.id == id }) {
            records[idx].lastAccessedDate = Date()
            saveRecords()
        }
    }

    private func refreshStaleBookmark(id: UUID, url: URL, isSecurityScoped: Bool) {
        let options: URL.BookmarkCreationOptions = isSecurityScoped ? .withSecurityScope : []
        if let newBookmark = try? url.bookmarkData(options: options, includingResourceValuesForKeys: [.isDirectoryKey, .pathKey], relativeTo: nil) {
            lock.lock()
            defer { lock.unlock() }
            if let idx = records.firstIndex(where: { $0.id == id }) {
                records[idx].bookmarkData = newBookmark
                records[idx].status = .stale
                records[idx].lastAccessedDate = Date()
                saveRecords()
            }
        }
    }
}
