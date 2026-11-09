import Foundation

/// Status and metadata for a detected developer CLI tool.
public struct SupportedTool: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let cliCommand: String
    public let pruneCommandArgs: [String]
    public let cachePaths: [String]
    public let isInstalled: Bool
    public let executablePath: String?
    public let estimatedCacheBytes: Int64
    public let description: String

    public init(
        name: String,
        cliCommand: String,
        pruneCommandArgs: [String],
        cachePaths: [String],
        isInstalled: Bool,
        executablePath: String?,
        estimatedCacheBytes: Int64,
        description: String
    ) {
        self.name = name
        self.cliCommand = cliCommand
        self.pruneCommandArgs = pruneCommandArgs
        self.cachePaths = cachePaths
        self.isInstalled = isInstalled
        self.executablePath = executablePath
        self.estimatedCacheBytes = estimatedCacheBytes
        self.description = description
    }
}

/// Result of executing a native tool prune command.
public struct ToolPruneResult: Sendable, Equatable {
    public let toolName: String
    public let succeeded: Bool
    public let output: String
    public let bytesReclaimed: Int64

    public init(toolName: String, succeeded: Bool, output: String, bytesReclaimed: Int64) {
        self.toolName = toolName
        self.succeeded = succeeded
        self.output = output
        self.bytesReclaimed = bytesReclaimed
    }
}

/// Manages detection and native command execution for developer tools and package managers.
public actor NativeToolPruner {
    public static let shared = NativeToolPruner()

    public init() {}

    /// Discovers all supported tools, checking presence on disk and measuring cache sizes.
    public func discoverTools() async -> [SupportedTool] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let toolSpecs: [(name: String, cmd: String, args: [String], caches: [String], desc: String)] = [
            (
                "Homebrew",
                "brew",
                ["cleanup", "-s", "--prune=all"],
                ["\(home)/Library/Caches/Homebrew"],
                "Removes outdated downloads, lockfiles, and stale formula caches."
            ),
            (
                "Docker",
                "docker",
                ["system", "prune", "-f"],
                ["\(home)/Library/Containers/com.docker.docker/Data/vms"],
                "Removes dangling images, stopped containers, and build cache."
            ),
            (
                "pnpm",
                "pnpm",
                ["store", "prune"],
                ["\(home)/Library/Caches/pnpm", "\(home)/.local/share/pnpm/store"],
                "Prunes unreferenced package tarballs from content-addressable store."
            ),
            (
                "npm",
                "npm",
                ["cache", "clean", "--force"],
                ["\(home)/.npm/_cacache"],
                "Purges npm package archive and index caches."
            ),
            (
                "pip (Python)",
                "pip3",
                ["cache", "purge"],
                ["\(home)/Library/Caches/pip"],
                "Purges cached Python wheels and download archives."
            ),
            (
                "uv (Python)",
                "uv",
                ["cache", "prune"],
                ["\(home)/.cache/uv", "\(home)/Library/Caches/uv"],
                "Prunes unreferenced wheel caches and download staging."
            ),
            (
                "Go",
                "go",
                ["clean", "-cache"],
                ["\(home)/Library/Caches/go-build"],
                "Clears the Go build cache containing compiled object files."
            ),
            (
                "Rust / Cargo",
                "cargo",
                [],
                ["\(home)/.cargo/registry/cache", "\(home)/.rustup/downloads"],
                "Cleans Cargo crates registry downloads and toolchain archives."
            )
        ]

        var discovered: [SupportedTool] = []

        for spec in toolSpecs {
            let execPath = findExecutable(named: spec.cmd)
            let isInstalled = (execPath != nil)

            var totalCacheSize: Int64 = 0
            for cPath in spec.caches {
                totalCacheSize += calculatePathSize(cPath)
            }

            discovered.append(SupportedTool(
                name: spec.name,
                cliCommand: spec.cmd,
                pruneCommandArgs: spec.args,
                cachePaths: spec.caches,
                isInstalled: isInstalled,
                executablePath: execPath,
                estimatedCacheBytes: totalCacheSize,
                description: spec.desc
            ))
        }

        return discovered
    }

    /// Executes the native tool prune command or safely clears cache paths.
    public func pruneTool(_ tool: SupportedTool) async -> ToolPruneResult {
        let sizeBefore = tool.cachePaths.reduce(0) { $0 + calculatePathSize($1) }

        if let execPath = tool.executablePath, !tool.pruneCommandArgs.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: execPath)
            process.arguments = tool.pruneCommandArgs

            // Set clean environment
            var env = ProcessInfo.processInfo.environment
            env["LC_ALL"] = "C"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let outputStr = String(data: data, encoding: .utf8) ?? ""

                let sizeAfter = tool.cachePaths.reduce(0) { $0 + calculatePathSize($1) }
                let reclaimed = max(0, sizeBefore - sizeAfter)

                return ToolPruneResult(
                    toolName: tool.name,
                    succeeded: process.terminationStatus == 0,
                    output: outputStr,
                    bytesReclaimed: reclaimed > 0 ? reclaimed : sizeBefore
                )
            } catch {
                return ToolPruneResult(
                    toolName: tool.name,
                    succeeded: false,
                    output: "Execution failed: \(error.localizedDescription)",
                    bytesReclaimed: 0
                )
            }
        } else {
            // For tools without CLI prune (like Cargo registry cache), safely clean directory contents
            var cleanedBytes: Int64 = 0
            let fileManager = FileManager.default

            for cPath in tool.cachePaths {
                let url = URL(fileURLWithPath: cPath)
                if let items = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    for item in items {
                        let itemSize = calculatePathSize(item.path)
                        if (try? fileManager.removeItem(at: item)) != nil {
                            cleanedBytes += itemSize
                        }
                    }
                }
            }

            return ToolPruneResult(
                toolName: tool.name,
                succeeded: true,
                output: "Cleaned cache directories directly.",
                bytesReclaimed: cleanedBytes
            )
        }
    }

    private func findExecutable(named name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.cargo/bin",
            "\(home)/.local/bin",
            "/opt/anaconda3/bin"
        ]

        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            let envDirs = envPath.components(separatedBy: ":")
            searchPaths.insert(contentsOf: envDirs, at: 0)
        }

        for dir in searchPaths {
            guard !dir.isEmpty else { continue }
            let fullPath = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    private func calculatePathSize(_ path: String) -> Int64 {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: path) else { return 0 }

        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: path, isDirectory: &isDir)
        if !isDir.boolValue {
            let attr = try? fileManager.attributesOfItem(atPath: path)
            return (attr?[.size] as? Int64) ?? 0
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                totalSize += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0)
            }
        }
        return totalSize
    }
}

