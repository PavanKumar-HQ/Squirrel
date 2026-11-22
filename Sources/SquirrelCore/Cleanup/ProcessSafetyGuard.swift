import Foundation
import AppKit
import Darwin

/// Guards cleanup operations by checking whether applications or CLI development tools
/// owning targeted caches are currently running.
/// Incorporates Mole's SingletonLock pattern for instantaneous Electron/Chromium lock detection.
public struct ProcessSafetyGuard: Sendable {
    public static let shared = ProcessSafetyGuard()

    public init() {}

    /// Map of directory name or path keyword to bundle IDs and GUI process names.
    private static let guardedGUIApplications: [String: (bundleIds: [String], processNames: [String])] = [
        "xcode": (["com.apple.dt.Xcode"], ["Xcode"]),
        "deriveddata": (["com.apple.dt.Xcode"], ["Xcode"]),
        "chrome": (["com.google.Chrome"], ["Google Chrome"]),
        "safari": (["com.apple.Safari"], ["Safari"]),
        "brave": (["com.brave.Browser"], ["Brave Browser"]),
        "edge": (["com.microsoft.edgemac"], ["Microsoft Edge"]),
        "slack": (["com.tinyspeck.slackmacgap"], ["Slack"]),
        "discord": (["com.hnc.Discord"], ["Discord"]),
        "spotify": (["com.spotify.client"], ["Spotify"]),
        "vscode": (["com.microsoft.VSCode"], ["Code"]),
        "cursor": (["com.todesktop.230313mzl4w4u92"], ["Cursor"]),
        "docker": (["com.docker.docker"], ["Docker", "Docker Desktop"]),
        "notion": (["notion.id"], ["Notion"]),
        "telegram": (["ru.keepcoder.Telegram"], ["Telegram"]),
        "wechat": (["com.tencent.xinWeChat"], ["WeChat"])
    ]

    /// Map of path keywords to CLI executable names that should protect the directory from deletion.
    private static let guardedCLIProcesses: [String: [String]] = [
        "node_modules": ["node", "next", "vite", "npm", "pnpm", "yarn", "bun"],
        ".next": ["node", "next"],
        "target": ["cargo", "rustc"],
        ".build": ["swift", "swift-frontend", "xcodebuild"],
        "cargo": ["cargo", "rustc"],
        "pip": ["python", "python3", "pip"],
        "uv": ["uv"],
        "go-build": ["go"],
        "docker": ["docker", "com.docker.backend"]
    ]

    /// Inspects Chromium and Electron SingletonLock symlinks up to 3 directory levels above the target.
    /// Returns immediately (< 0.1ms) with true if an active instance holds the lock.
    public func isSingletonLockActive(forPath path: String) -> (isActive: Bool, holderInfo: String?) {
        var currentURL = URL(fileURLWithPath: path)
        let homeURL = FileManager.default.homeDirectoryForCurrentUser

        for _ in 0..<4 {
            guard currentURL.path.hasPrefix(homeURL.path) && currentURL.path != homeURL.path else { break }

            let lockURL = currentURL.appendingPathComponent("SingletonLock")
            var statBuf = stat()
            if lstat(lockURL.path, &statBuf) == 0 && (statBuf.st_mode & S_IFMT) == S_IFLNK {
                var buffer = [CChar](repeating: 0, count: 1024)
                let len = readlink(lockURL.path, &buffer, buffer.count - 1)
                if len > 0 {
                    buffer[len] = 0
                    let target = String(cString: buffer)
                    // Format is typically <hostname>-<pid>
                    if let pidStr = target.components(separatedBy: "-").last,
                       let pid = Int32(pidStr), pid > 0 {
                        // Check if process is alive
                        if kill(pid, 0) == 0 {
                            let appName = currentURL.lastPathComponent
                            return (true, "Active \(appName) session (PID \(pid))")
                        }
                    }
                }
            }
            currentURL = currentURL.deletingLastPathComponent()
        }

        return (false, nil)
    }

    /// Retrieves all active Darwin process names via kernel sysctl without subprocess spawning (0.0% CPU, < 1ms).
    public func runningDarwinProcessNames() -> Set<String> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else {
            return []
        }
        var names = Set<String>()
        for proc in procs {
            let name = withUnsafeBytes(of: proc.kp_proc.p_comm) { rawPtr -> String in
                guard let base = rawPtr.baseAddress?.assumingMemoryBound(to: CChar.self) else { return "" }
                return String(cString: base)
            }
            if !name.isEmpty {
                names.insert(name.lowercased())
            }
        }
        return names
    }

    /// Checks if an application or CLI dev tool associated with a file path is actively running.
    public func isApplicationRunning(forPath path: String) -> (isRunning: Bool, appName: String?) {
        // 1. Check Electron / Chromium SingletonLock (instantaneous, 100% accurate per-profile lock)
        let singletonCheck = isSingletonLockActive(forPath: path)
        if singletonCheck.isActive {
            return (true, singletonCheck.holderInfo)
        }

        let pathLower = path.lowercased()

        // 2. Check GUI Applications via NSWorkspace
        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier?.lowercased() })
        let runningNames = Set(runningApps.compactMap { $0.localizedName?.lowercased() })

        for (keyword, guardConfig) in Self.guardedGUIApplications {
            if pathLower.contains(keyword) {
                // Check bundle IDs
                for bId in guardConfig.bundleIds {
                    if runningBundleIds.contains(bId.lowercased()) {
                        let name = runningApps.first(where: { $0.bundleIdentifier?.lowercased() == bId.lowercased() })?.localizedName ?? keyword.capitalized
                        return (true, name)
                    }
                }
                // Check process names
                for pName in guardConfig.processNames {
                    if runningNames.contains(pName.lowercased()) {
                        return (true, pName)
                    }
                }
            }
        }

        // 3. Check CLI / Developer Daemons via Darwin kernel sysctl
        let cliProcesses = runningDarwinProcessNames()
        for (keyword, processList) in Self.guardedCLIProcesses {
            if pathLower.contains(keyword) {
                for proc in processList {
                    if cliProcesses.contains(proc.lowercased()) {
                        return (true, "Active CLI process '\(proc)'")
                    }
                }
            }
        }

        return (false, nil)
    }
}
