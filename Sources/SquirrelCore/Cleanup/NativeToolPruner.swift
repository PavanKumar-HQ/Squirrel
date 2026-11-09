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

    /// Discovers all supported tools, checking presence on disk and measuring cache sizes via kernel du.
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
                if FileManager.default.fileExists(atPath: cPath) {
                    totalCacheSize += ProjectPurgeScanner.fastDirectorySize(at: cPath)
                }
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

    /// Executes the native tool prune command or safely clears cache paths using SafeProcessRunner.
    public func pruneTool(_ tool: SupportedTool) async -> ToolPruneResult {
        let sizeBefore = tool.cachePaths.reduce(0) { sum, path in
            FileManager.default.fileExists(atPath: path) ? sum + ProjectPurgeScanner.fastDirectorySize(at: path) : sum
        }

        if let execPath = tool.executablePath, !tool.pruneCommandArgs.isEmpty {
            var env = ProcessInfo.processInfo.environment
            env["LC_ALL"] = "C"

            let result = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: execPath),
                arguments: tool.pruneCommandArgs,
                timeoutSeconds: 20.0,
                environment: env
            )

            let sizeAfter = tool.cachePaths.reduce(0) { sum, path in
                FileManager.default.fileExists(atPath: path) ? sum + ProjectPurgeScanner.fastDirectorySize(at: path) : sum
            }
            let reclaimed = max(0, sizeBefore - sizeAfter)

            return ToolPruneResult(
                toolName: tool.name,
                succeeded: result.isSuccess,
                output: result.stdout.isEmpty ? result.stderr : result.stdout,
                bytesReclaimed: reclaimed > 0 ? reclaimed : sizeBefore
            )
        } else {
            // Direct cache purge via trash for tools without a prune subcommand (e.g. Cargo registry cache)
            var cleanedBytes: Int64 = 0
            let fileManager = FileManager.default

            for cPath in tool.cachePaths {
                let url = URL(fileURLWithPath: cPath)
                if fileManager.fileExists(atPath: cPath) {
                    let dirSize = ProjectPurgeScanner.fastDirectorySize(at: cPath)
                    if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        for item in contents {
                            var resultingURL: NSURL?
                            if (try? fileManager.trashItem(at: item, resultingItemURL: &resultingURL)) != nil {
                                cleanedBytes += dirSize / Int64(max(1, contents.count))
                            }
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
}
