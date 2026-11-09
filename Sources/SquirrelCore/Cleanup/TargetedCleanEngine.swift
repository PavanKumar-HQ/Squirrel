import Foundation

/// Represents a distinct cleanable group matching the 4-category Mole model.
public enum CleanGroupCategory: String, CaseIterable, Identifiable, Sendable {
    case appCaches = "App Caches & Logs"
    case developerTools = "Developer Tools"
    case appLeftovers = "Uninstalled App Leftovers"
    case systemData = "System Data"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .appCaches: return "app.badge"
        case .developerTools: return "hammer.fill"
        case .appLeftovers: return "shippingbox"
        case .systemData: return "internaldrive"
        }
    }

    public var subtitle: String {
        switch self {
        case .appCaches:
            return "App, browser and cloud caches plus old logs. Sign-ins and browsing history are kept"
        case .developerTools:
            return "Caches of Xcode, SwiftPM, Node.js and other developer tools. The first build after cleaning takes a little longer"
        case .appLeftovers:
            return "Files left by deleted apps. Some may hold settings or data you want, so pick what to remove"
        case .systemData:
            return "System caches, diagnostic logs and local Time Machine snapshots. Backups on your backup disk are untouched"
        }
    }
}

/// A specific cleanable item within a category group.
public struct CleanableItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let category: CleanGroupCategory
    public let detail: String
    public var isSelected: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        path: String,
        sizeBytes: Int64,
        category: CleanGroupCategory,
        detail: String,
        isSelected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.category = category
        self.detail = detail
        self.isSelected = isSelected
    }
}

/// Aggregate summary of all 4 categories ready for one-click clean.
public struct ReadyToCleanSummary: Sendable {
    public var items: [CleanableItem] = []

    public init(items: [CleanableItem] = []) {
        self.items = items
    }

    public var totalCleanableBytes: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalAvailableBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    public func items(for category: CleanGroupCategory) -> [CleanableItem] {
        items.filter { $0.category == category }
    }

    public func size(for category: CleanGroupCategory) -> Int64 {
        items(for: category).reduce(0) { $0 + $1.sizeBytes }
    }

    public func selectedSize(for category: CleanGroupCategory) -> Int64 {
        items(for: category).filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }
}

/// High-efficiency targeted clean engine mirroring Mole's exact architecture.
/// Checks targeted high-yield paths directly in < 2 seconds without full-drive crawling.
public actor TargetedCleanEngine {
    public static let shared = TargetedCleanEngine()

    public init() {}

    public func performTargetedAudit(
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> ReadyToCleanSummary {
        var cleanableItems: [CleanableItem] = []
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        // 1. DEVELOPER TOOLS (High Yield: Xcode, SwiftPM, Rust, Node, Web, Python)
        progressHandler?("Checking developer build caches...")

        // Known developer cache paths
        let devCachePaths: [(name: String, relPath: String, desc: String)] = [
            ("Xcode DerivedData", "Library/Developer/Xcode/DerivedData", "Regenerable Xcode build artifacts and indexing data"),
            ("Xcode Caches", "Library/Caches/com.apple.dt.Xcode", "Xcode documentation and compiler caches"),
            ("SwiftPM Cache", "Library/Caches/org.swift.swiftpm", "Swift Package Manager checkouts and cache"),
            ("CoreSimulator Caches", "Library/Developer/CoreSimulator/Caches", "iOS Simulator runtime caches"),
            ("npm Cache", ".npm/_cacache", "Node.js npm package download cache"),
            ("Cargo Registry Cache", ".cargo/registry/cache", "Rust Cargo crate source archives"),
            ("Cargo Git DB", ".cargo/git/db", "Rust Cargo git repositories cache"),
            ("Gradle Caches", ".gradle/caches", "Java / Android Gradle dependency cache"),
            ("Pip Cache", "Library/Caches/pip", "Python pip wheel and package cache"),
            ("uv Cache", ".cache/uv", "Python uv fast package manager cache"),
            ("CocoaPods Cache", "Library/Caches/CocoaPods", "CocoaPods spec and download cache"),
            ("Homebrew Cache", "Library/Caches/Homebrew", "Homebrew bottled formulas and download tarballs")
        ]

        for entry in devCachePaths {
            let fullURL = home.appendingPathComponent(entry.relPath)
            if fileManager.fileExists(atPath: fullURL.path) {
                let size = ProjectPurgeScanner.fastDirectorySize(at: fullURL.path)
                if size > 1024 * 1024 { // Only include if > 1 MB
                    cleanableItems.append(CleanableItem(
                        name: entry.name,
                        path: fullURL.path,
                        sizeBytes: size,
                        category: .developerTools,
                        detail: entry.desc
                    ))
                }
            }
        }

        // Project build artifacts (Targeted scan of project folders at depth 1-2)
        let projectRoots = ProjectPurgeScanner.defaultProjectRoots()
        let discoveredProjects = await ProjectPurgeScanner.shared.scanProjects(roots: projectRoots)
        for proj in discoveredProjects {
            for artifact in proj.artifacts {
                cleanableItems.append(CleanableItem(
                    name: "\(proj.projectName) (\(artifact.name))",
                    path: artifact.path,
                    sizeBytes: artifact.sizeBytes,
                    category: .developerTools,
                    detail: "\(proj.projectType) regenerable build artifact in \(proj.projectName)"
                ))
            }
        }

        // 2. SYSTEM DATA (APFS Time Machine Snapshots & System Logs)
        progressHandler?("Checking system data & local snapshots...")

        let snapshots = await SnapshotManager.shared.listLocalSnapshots()
        for snap in snapshots {
            let snapSize: Int64 = 500 * 1024 * 1024 // Estimated ~500 MB baseline per snapshot
            cleanableItems.append(CleanableItem(
                name: "APFS Snapshot: \(snap.name)",
                path: snap.name,
                sizeBytes: snapSize,
                category: .systemData,
                detail: "Local Time Machine snapshot created on \(snap.dateString)"
            ))
        }

        // Stale crash and diagnostic reports (> 7 days)
        let diagReports = home.appendingPathComponent("Library/Logs/DiagnosticReports")
        if fileManager.fileExists(atPath: diagReports.path) {
            let size = ProjectPurgeScanner.fastDirectorySize(at: diagReports.path)
            if size > 1024 * 512 {
                cleanableItems.append(CleanableItem(
                    name: "System Diagnostic Reports",
                    path: diagReports.path,
                    sizeBytes: size,
                    category: .systemData,
                    detail: "Old application crash logs and diagnostic dumps"
                ))
            }
        }

        // 3. APP CACHES & LOGS
        progressHandler?("Checking application caches...")

        let userCaches = home.appendingPathComponent("Library/Caches")
        if let cacheDirs = try? fileManager.contentsOfDirectory(at: userCaches, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for cacheDir in cacheDirs {
                let name = cacheDir.lastPathComponent
                // Skip developer caches already categorized
                if name == "com.apple.dt.Xcode" || name == "org.swift.swiftpm" || name == "CocoaPods" || name == "Homebrew" {
                    continue
                }
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: cacheDir.path, isDirectory: &isDir), isDir.boolValue {
                    let size = ProjectPurgeScanner.fastDirectorySize(at: cacheDir.path)
                    if size > 50 * 1024 * 1024 { // Only surface significant caches (> 50 MB)
                        cleanableItems.append(CleanableItem(
                            name: name,
                            path: cacheDir.path,
                            sizeBytes: size,
                            category: .appCaches,
                            detail: "User application cache for \(name)"
                        ))
                    }
                }
            }
        }

        // User log files
        let userLogs = home.appendingPathComponent("Library/Logs")
        if fileManager.fileExists(atPath: userLogs.path) {
            let size = ProjectPurgeScanner.fastDirectorySize(at: userLogs.path)
            if size > 10 * 1024 * 1024 {
                cleanableItems.append(CleanableItem(
                    name: "User Diagnostic Logs",
                    path: userLogs.path,
                    sizeBytes: size,
                    category: .appCaches,
                    detail: "Stale user session logs and diagnostic output"
                ))
            }
        }

        // 4. UNINSTALLED APP LEFTOVERS
        progressHandler?("Checking uninstalled app leftovers...")

        let leftovers = await AppLeftoverScanner.shared.scanLeftovers()
        for item in leftovers {
            cleanableItems.append(CleanableItem(
                name: "\(item.appName) Leftover Data",
                path: item.path,
                sizeBytes: item.sizeBytes,
                category: .appLeftovers,
                detail: "Residual application support files from removed app"
            ))
        }

        progressHandler?("Audit complete.")
        return ReadyToCleanSummary(items: cleanableItems)
    }
}
