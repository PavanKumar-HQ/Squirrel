import Foundation
import AppKit

/// Represents an orphaned file or folder left behind by an uninstalled application.
public struct AppLeftoverItem: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let appName: String
    public let path: String
    public let sizeBytes: Int64
    public let modificationDate: Date?

    public init(appName: String, path: String, sizeBytes: Int64, modificationDate: Date?) {
        self.appName = appName
        self.path = path
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
    }
}

/// Discovers files left behind by deleted applications in Application Support and Preferences.
public actor AppLeftoverScanner {
    public static let shared = AppLeftoverScanner()

    // Well-known Apple / macOS system services to preserve
    private static let protectedSystemNames: Set<String> = [
        "AddressBook", "Animoji", "AskPermission", "CallHistoryDB", "CallHistoryTransactions",
        "Categories", "CloudDocs", "CoreParsec", "CrashReporter", "DifferentialPrivacy",
        "DiskImages", "FaceTime", "FileProvider", "IntelligenceFlow", "Knowledge", "Music",
        "OpenDirectory", "Quick Look", "Safari", "ScreenTime", "Spotlight", "SyncServices",
        "WebKit", "accountsd", "cloudd", "containermanagerd", "identityservicesd", "passd"
    ]

    public init() {}

    /// Discovers leftovers from uninstalled apps
    public func scanLeftovers() async -> [AppLeftoverItem] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)

        guard fileManager.fileExists(atPath: appSupport.path) else { return [] }

        // 1. Gather all currently installed app bundle names & IDs
        let installedAppNames = Self.discoverInstalledAppNames()

        // 2. Inspect Application Support folders
        guard let entries = try? fileManager.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var leftovers: [AppLeftoverItem] = []

        for entry in entries {
            let name = entry.lastPathComponent

            // Skip protected Apple system names
            if Self.protectedSystemNames.contains(name) || name.hasPrefix("com.apple.") {
                continue
            }

            // Check if matches an installed application
            let isInstalled = installedAppNames.contains(name.lowercased()) ||
                              installedAppNames.contains(name.replacingOccurrences(of: " ", with: "").lowercased())

            if !isInstalled {
                // Orphaned folder
                let size = ProjectPurgeScanner.fastDirectorySize(at: entry.path)
                if size > 0 {
                    let modDate = (try? fileManager.attributesOfItem(atPath: entry.path)[.modificationDate]) as? Date
                    leftovers.append(AppLeftoverItem(
                        appName: name,
                        path: entry.path,
                        sizeBytes: size,
                        modificationDate: modDate
                    ))
                }
            }
        }

        return leftovers.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func discoverInstalledAppNames() -> Set<String> {
        let fileManager = FileManager.default
        var names = Set<String>()

        let candidateAppDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        for dir in candidateAppDirs {
            guard let appBundles = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for app in appBundles where app.pathExtension.lowercased() == "app" {
                let base = app.deletingPathExtension().lastPathComponent
                names.insert(base.lowercased())
                names.insert(base.replacingOccurrences(of: " ", with: "").lowercased())

                // Check CFBundleIdentifier in Info.plist
                let plistPath = app.appendingPathComponent("Contents/Info.plist")
                if let plistData = try? Data(contentsOf: plistPath),
                   let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                   let bundleId = plist["CFBundleIdentifier"] as? String {
                    names.insert(bundleId.lowercased())
                }
            }
        }

        // Also add active process names
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let name = app.localizedName {
                names.insert(name.lowercased())
            }
            if let id = app.bundleIdentifier {
                names.insert(id.lowercased())
            }
        }

        return names
    }
}
