import Foundation
import AppKit
import Darwin

/// Guards cleanup operations by checking whether applications or CLI development tools
/// owning targeted caches are currently running.
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
        let pathLower = path.lowercased()

        // 1. Check GUI Applications via NSWorkspace
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

        // 2. Check CLI / Developer Daemons via Darwin kernel sysctl
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
