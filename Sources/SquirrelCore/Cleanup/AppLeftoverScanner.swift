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
/// Incorporates production safety filters (mirroring Mole's app_protection.sh) to protect
/// active editors, password managers, system services, and CLI tools.
public actor AppLeftoverScanner {
    public static let shared = AppLeftoverScanner()

    /// System and critical developer application data names that MUST NEVER be flagged as leftovers.
    private static let protectedAppSupportNames: Set<String> = [
        // System Services & Apple Subsystems
        "AddressBook", "Animoji", "AskPermission", "CallHistoryDB", "CallHistoryTransactions",
        "Categories", "CloudDocs", "CoreParsec", "CrashReporter", "DifferentialPrivacy",
        "DiskImages", "FaceTime", "FileProvider", "IntelligenceFlow", "Knowledge", "Music",
        "OpenDirectory", "Quick Look", "Safari", "ScreenTime", "Spotlight", "SyncServices",
        "WebKit", "accountsd", "cloudd", "containermanagerd", "identityservicesd", "passd",
        "MobileSync", "iCloud", "Dock", "NotificationCenter", "Keyboard", "QuickLook",
        "com.apple.sharedfilelist", "com.apple.TCC", "com.apple.AddressBook",

        // Developer Tools & Code Editors (often named differently from .app bundle)
        "Code", "Visual Studio Code", "Cursor", "Antigravity", "Sublime Text", "Sublime Text 3",
        "JetBrains", "IntelliJIdea", "PyCharm", "WebStorm", "CLion", "Fleet", "Xcode",
        "Docker", "Docker Desktop", "Postman", "Insomnia", "Ollama", "Claude", "ChatGPT",
        "pnpm", "pip", "uv", "cargo", "gnupg", "dconf", "mesa", "Homebrew",

        // Security & Password Managers
        "1Password", "1Password 7", "Bitwarden", "LastPass", "Dashlane", "KeePassXC",
        "Keychains", "Security",

        // Browsers & Messengers with non-bundle folder names
        "Google", "BraveSoftware", "Microsoft", "Mozilla", "Firefox", "Arc",
        "Discord", "Telegram", "Slack", "Signal", "WhatsApp", "Steam", "Spotify"
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
        guard let entries = try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var leftovers: [AppLeftoverItem] = []

        for entry in entries {
            let name = entry.lastPathComponent

            // Fast-path safety: skip protected system names and known tool folders
            if Self.isProtectedFolder(name) {
                continue
            }

            // Check if matches an installed application bundle or process
            let normalized = name.lowercased()
            let spaceless = name.replacingOccurrences(of: " ", with: "").lowercased()
            let isInstalled = installedAppNames.contains(normalized) || installedAppNames.contains(spaceless)

            if !isInstalled {
                // Secondary fast-path: native macOS LaunchServices registry check (< 0.1ms, zero subprocesses)
                if Self.doesApplicationExistInLaunchServices(named: name) {
                    continue
                }

                // Legitimate uninstalled app leftover
                let size = ProjectPurgeScanner.fastDirectorySize(at: entry.path)
                if size > 1024 * 1024 { // Only surface significant leftovers (> 1 MB)
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

    /// Checks if folder name belongs to a protected system or developer category.
    public static func isProtectedFolder(_ name: String) -> Bool {
        if protectedAppSupportNames.contains(name) || name.hasPrefix("com.apple.") {
            return true
        }
        let lower = name.lowercased()
        if lower.contains("keychain") || lower.contains("security") || lower.contains("tcc") {
            return true
        }
        if lower.contains("inputmethod") || lower.contains("keyboard") || lower.contains("ime") {
            return true
        }
        return false
    }

    /// Uses native macOS LaunchServices to verify whether an application matching the bundle ID exists on disk.
    /// Executes instantly (< 0.1ms) without spawning subprocesses or scanning Spotlight.
    public static func doesApplicationExistInLaunchServices(named name: String) -> Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) != nil {
            return true
        }
        return false
    }

    private static func discoverInstalledAppNames() -> Set<String> {
        let fileManager = FileManager.default
        var names = Set<String>()

        let candidateAppDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
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
                names.insert(name.replacingOccurrences(of: " ", with: "").lowercased())
            }
            if let id = app.bundleIdentifier {
                names.insert(id.lowercased())
            }
        }

        return names
    }
}
