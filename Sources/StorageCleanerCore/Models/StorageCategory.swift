import Foundation

/// Represents a distinct classification of scanned storage items.
public enum StorageCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case userCaches = "User Caches"
    case systemLogs = "System & App Logs"
    case downloadsAndInstallers = "Downloads & Installers"
    case largeFiles = "Large Files"
    case duplicates = "Exact Duplicates"
    case appLeftovers = "Application Leftovers"
    case otherUserData = "Other Files"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .userCaches:
            return "Application cache files that can be regenerated automatically by applications when needed."
        case .systemLogs:
            return "Diagnostic logs, crash reports, and system log archives older than standard retention windows."
        case .downloadsAndInstallers:
            return "Disk images (.dmg), package installers (.pkg), and download archives in user folders."
        case .largeFiles:
            return "Individual files consuming 100 MB or more of storage space."
        case .duplicates:
            return "Identical file copies confirmed by cryptographic content hashing."
        case .appLeftovers:
            return "Residual configuration and support files remaining from removed applications."
        case .otherUserData:
            return "Other scanned files and folders analyzed for storage breakdown."
        }
    }

    public var isBatchCleanEligible: Bool {
        switch self {
        case .userCaches, .systemLogs:
            return true
        case .downloadsAndInstallers, .largeFiles, .duplicates, .appLeftovers, .otherUserData:
            return false // Mandatory manual review
        }
    }

    public var iconName: String {
        switch self {
        case .userCaches:
            return "cylinder.split.1x2"
        case .systemLogs:
            return "doc.plaintext"
        case .downloadsAndInstallers:
            return "arrow.down.circle"
        case .largeFiles:
            return "externaldrive"
        case .duplicates:
            return "doc.on.doc"
        case .appLeftovers:
            return "archivebox"
        case .otherUserData:
            return "folder"
        }
    }
}
