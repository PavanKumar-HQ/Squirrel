import Foundation
import AppKit

/// Guards cleanup operations by checking whether applications owning targeted caches are currently running.
public struct ProcessSafetyGuard: Sendable {
    public static let shared = ProcessSafetyGuard()

    public init() {}

    /// Map of directory name or path keyword to bundle IDs and process names.
    private static let guardedApplications: [String: (bundleIds: [String], processNames: [String])] = [
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

    /// Checks if an application associated with a file path is actively running.
    public func isApplicationRunning(forPath path: String) -> (isRunning: Bool, appName: String?) {
        let pathLower = path.lowercased()

        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier?.lowercased() })
        let runningNames = Set(runningApps.compactMap { $0.localizedName?.lowercased() })

        for (keyword, guardConfig) in Self.guardedApplications {
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

        return (false, nil)
    }
}

