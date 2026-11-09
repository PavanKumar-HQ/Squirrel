import Foundation

/// Represents a discovered project artifact (e.g. node_modules, target, .venv).
public struct ProjectArtifact: Identifiable, Sendable, Codable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let modificationDate: Date?

    public init(name: String, path: String, sizeBytes: Int64, modificationDate: Date?) {
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
    }
}

/// Represents a detected software development project containing purgeable artifacts.
public struct ProjectCandidate: Identifiable, Sendable, Equatable {
    public var id: String { projectPath }
    public let projectName: String
    public let projectPath: String
    public let projectType: String
    public let artifacts: [ProjectArtifact]
    public let totalReclaimableBytes: Int64

    public init(
        projectName: String,
        projectPath: String,
        projectType: String,
        artifacts: [ProjectArtifact]
    ) {
        self.projectName = projectName
        self.projectPath = projectPath
        self.projectType = projectType
        self.artifacts = artifacts
        self.totalReclaimableBytes = artifacts.reduce(0) { $0 + $1.sizeBytes }
    }
}

/// Actor responsible for scanning developer directories, discovering software projects,
/// and identifying heavy regenerable build artifacts (mirroring Mole's `mo purge`).
public actor ProjectPurgeScanner {
    public static let shared = ProjectPurgeScanner()

    private var isCancelled = false

    public init() {}

    public func cancel() {
        isCancelled = true
    }

    /// Known project root indicators (file name -> Project Type)
    private static let projectIndicators: [String: String] = [
        "package.json": "Node.js / Web",
        "Cargo.toml": "Rust / Cargo",
        "go.mod": "Go",
        "pom.xml": "Java / Maven",
        "build.gradle": "Gradle",
        "build.gradle.kts": "Gradle",
        "pyproject.toml": "Python",
        "requirements.txt": "Python",
        "Pipfile": "Python",
        "Package.swift": "Swift Package Manager",
        "CMakeLists.txt": "C/C++ CMake",
        "Makefile": "Make Project",
        "composer.json": "PHP Composer"
    ]

    /// Target artifact directory names
    private static let targetArtifactNames: Set<String> = [
        "node_modules", "target", "build", "dist", "venv", ".venv",
        ".next", ".turbo", ".nuxt", ".output", ".svelte-kit", ".astro",
        ".dart_tool", ".zig-cache", "zig-out", "Pods", ".cxx", ".build"
    ]

    /// Discovers default search paths on the user's Mac
    public static func defaultProjectRoots() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidateNames = [
            "Code", "Projects", "Developer", "Workspace", "Repos",
            "dev", "Development", "Downloads"
        ]
        var roots: [URL] = []
        var visitedPaths = Set<String>()

        for name in candidateNames {
            let url = home.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                roots.append(url)
                visitedPaths.insert(url.path)
            }
        }

        // Also discover any user project folder directly in $HOME (excluding standard macOS system folders)
        let systemBases: Set<String> = [
            "Library", "Applications", "Movies", "Music", "Pictures", "Public", "Desktop", "System", "Documents"
        ]
        if let homeContents = try? fileManager.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for itemURL in homeContents {
                let base = itemURL.lastPathComponent
                guard !systemBases.contains(base), !visitedPaths.contains(itemURL.path) else { continue }
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue {
                    roots.append(itemURL)
                    visitedPaths.insert(itemURL.path)
                }
            }
        }

        return roots
    }

    /// Scans provided project root folders and discovers all projects containing purgeable artifacts.
    public func scanProjects(
        roots: [URL],
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async -> [ProjectCandidate] {
        isCancelled = false
        var candidates: [ProjectCandidate] = []

        for root in roots {
            guard !isCancelled else { break }
            progressHandler?("Scanning \(root.lastPathComponent)...")

            let discovered = await scanDirectoryForProjects(root: root, maxDepth: 4, progressHandler: progressHandler)
            candidates.append(contentsOf: discovered)
        }

        // Sort by reclaimable bytes descending (biggest savings first)
        return candidates.sorted { $0.totalReclaimableBytes > $1.totalReclaimableBytes }
    }

    private func scanDirectoryForProjects(
        root: URL,
        maxDepth: Int,
        progressHandler: (@Sendable (String) -> Void)?
    ) async -> [ProjectCandidate] {
        var foundProjects: [ProjectCandidate] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var visitedProjectDirs = Set<String>()

        while let fileURL = enumerator.nextObject() as? URL {
            guard !isCancelled else { break }

            let fileName = fileURL.lastPathComponent

            // Check if this file is a project indicator
            if let projectType = Self.projectIndicators[fileName] {
                let projectDir = fileURL.deletingLastPathComponent()
                let projectDirPath = projectDir.path

                if !visitedProjectDirs.contains(projectDirPath) {
                    visitedProjectDirs.insert(projectDirPath)
                    progressHandler?("Checking \(projectDir.lastPathComponent)...")

                    // Inspect this project directory for purge targets
                    let artifacts = measureArtifacts(in: projectDir)
                    if !artifacts.isEmpty {
                        let candidate = ProjectCandidate(
                            projectName: projectDir.lastPathComponent,
                            projectPath: projectDirPath,
                            projectType: projectType,
                            artifacts: artifacts
                        )
                        foundProjects.append(candidate)
                    }
                }
            }

            // Do not recurse deeply into recognized artifacts
            if Self.targetArtifactNames.contains(fileName) {
                enumerator.skipDescendants()
            }
        }

        return foundProjects
    }

    private func measureArtifacts(in projectDir: URL) -> [ProjectArtifact] {
        var artifacts: [ProjectArtifact] = []
        let fileManager = FileManager.default

        for targetName in Self.targetArtifactNames {
            let targetURL = projectDir.appendingPathComponent(targetName, isDirectory: true)
            var isDir: ObjCBool = false

            if fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue {
                let size = calculateDirectorySize(targetURL)
                if size > 0 {
                    let modDate = (try? fileManager.attributesOfItem(atPath: targetURL.path)[.modificationDate]) as? Date
                    artifacts.append(ProjectArtifact(
                        name: targetName,
                        path: targetURL.path,
                        sizeBytes: size,
                        modificationDate: modDate
                    ))
                }
            }
        }

        return artifacts
    }

    private func calculateDirectorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return 0 }

        var totalSize: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                totalSize += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0)
            }
        }
        return totalSize
    }
}

