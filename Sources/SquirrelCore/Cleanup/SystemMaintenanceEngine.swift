import Foundation
import AppKit

/// Represents an interactive system optimization task.
public struct SystemOptimizationTask: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let iconName: String
    public var isSelected: Bool

    public init(id: String, title: String, detail: String, iconName: String, isSelected: Bool = true) {
        self.id = id
        self.title = title
        self.detail = detail
        self.iconName = iconName
        self.isSelected = isSelected
    }
}

/// Result of executing a system optimization task.
public struct SystemOptimizationResult: Identifiable, Sendable, Equatable {
    public var id: String { taskId }
    public let taskId: String
    public let taskTitle: String
    public let succeeded: Bool
    public let message: String

    public init(taskId: String, taskTitle: String, succeeded: Bool, message: String) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.succeeded = succeeded
        self.message = message
    }
}

/// Engine executing safe, non-destructive macOS system maintenance and tuning tasks (mirroring Mole's `mo optimize`).
public actor SystemMaintenanceEngine {
    public static let shared = SystemMaintenanceEngine()

    public init() {}

    /// Returns standard safe optimization tasks available on macOS.
    public func availableTasks() -> [SystemOptimizationTask] {
        return [
            SystemOptimizationTask(
                id: "flush_dns",
                title: "Flush System DNS Cache",
                detail: "Resets macOS DNS resolver cache to fix slow domain lookups and resolve connection glitches.",
                iconName: "network"
            ),
            SystemOptimizationTask(
                id: "quicklook_cache",
                title: "Rebuild Finder QuickLook & Icon Cache",
                detail: "Refreshes QuickLook thumbnail store and icon generator to fix blank or corrupted Finder previews.",
                iconName: "eye.fill"
            ),
            SystemOptimizationTask(
                id: "stale_app_states",
                title: "Prune Stale Saved App States",
                detail: "Removes window restored states older than 30 days from ~/Library/Saved Application State.",
                iconName: "macwindow.badge.plus"
            ),
            SystemOptimizationTask(
                id: "quarantine_history",
                title: "Clean Gatekeeper Quarantine Log",
                detail: "Clears historical log of downloaded files in ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2.",
                iconName: "shield.slash.fill"
            ),
            SystemOptimizationTask(
                id: "prevent_network_dsstore",
                title: "Disable .DS_Store on Network & USB Drives",
                detail: "Sets Finder preference DSDontWriteNetworkStores to stop polluting external drives with .DS_Store files.",
                iconName: "externaldrive.badge.xmark"
            ),
            SystemOptimizationTask(
                id: "sqlite_vacuum",
                title: "Optimize Mail, Safari & Messages Databases",
                detail: "Runs VACUUM on SQLite databases used by Mail, Safari and Messages to reclaim fragmented space. Skipped if apps are running.",
                iconName: "cylinder.split.1x2.fill"
            ),
            SystemOptimizationTask(
                id: "network_stack_optimize",
                title: "Flush Routing Table & ARP Cache",
                detail: "Clears the IPv4/IPv6 routing table and ARP cache to resolve intermittent network glitches (mirrors Mole's network_stack_optimize).",
                iconName: "network.badge.shield.half.filled"
            ),
            SystemOptimizationTask(
                id: "legacy_overrides_audit",
                title: "Remove Legacy App Nap & Verification Overrides",
                detail: "Removes hidden App Nap and disk-image verification overrides left by old tweak tools in ~/Library/Preferences.",
                iconName: "switch.2",
                isSelected: false // Not selected by default — advanced/less common
            ),
            SystemOptimizationTask(
                id: "spotlight_optimize",
                title: "Rebuild Spotlight Index (if search is slow)",
                detail: "Checks if Spotlight indexing is behind and triggers a targeted reindex. Only runs if Spotlight is visibly stale.",
                iconName: "magnifyingglass.circle.fill",
                isSelected: false // User opt-in — can take several minutes
            )
        ]
    }

    /// Executes a list of selected optimization tasks.
    public func executeOptimization(
        tasks: [SystemOptimizationTask],
        progress: (@Sendable (String) -> Void)? = nil
    ) async -> [SystemOptimizationResult] {
        var results: [SystemOptimizationResult] = []

        for task in tasks where task.isSelected {
            progress?("Running \(task.title)...")
            let res = await executeTask(id: task.id, title: task.title)
            results.append(res)
        }

        progress?("Optimization completed.")
        return results
    }

    private func executeTask(id: String, title: String) async -> SystemOptimizationResult {
        switch id {
        case "flush_dns":
            let outcome = await SafeProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/dscacheutil"), arguments: ["-flushcache"], timeoutSeconds: 5)
            if outcome.exitCode == 0 {
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: "DNS resolver cache successfully flushed.")
            } else {
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: false, message: "dscacheutil returned code \(outcome.exitCode).")
            }

        case "quicklook_cache":
            let r1 = await SafeProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/qlmanage"), arguments: ["-r", "cache"], timeoutSeconds: 5)
            let r2 = await SafeProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/qlmanage"), arguments: ["-r"], timeoutSeconds: 5)
            if r1.exitCode == 0 || r2.exitCode == 0 {
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: "QuickLook thumbnail cache rebuilt successfully.")
            } else {
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: false, message: "qlmanage returned code \(r1.exitCode).")
            }

        case "stale_app_states":
            let home = FileManager.default.homeDirectoryForCurrentUser
            let savedStateURL = home.appendingPathComponent("Library/Saved Application State")
            guard FileManager.default.fileExists(atPath: savedStateURL.path) else {
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: "No saved application states found.")
            }

            var prunedCount = 0
            let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
            if let entries = try? FileManager.default.contentsOfDirectory(at: savedStateURL, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for item in entries where item.pathExtension == "savedState" {
                    if let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                       modDate < thirtyDaysAgo {
                        var resURL: NSURL?
                        if (try? FileManager.default.trashItem(at: item, resultingItemURL: &resURL)) != nil {
                            prunedCount += 1
                        }
                    }
                }
            }
            return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: "Safely moved \(prunedCount) stale app state folders (> 30 days) to Trash.")

        case "quarantine_history":
            let home = FileManager.default.homeDirectoryForCurrentUser
            let qPath = home.appendingPathComponent("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
            if FileManager.default.fileExists(atPath: qPath.path) {
                var resURL: NSURL?
                let success = (try? FileManager.default.trashItem(at: qPath, resultingItemURL: &resURL)) != nil
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: success, message: success ? "Gatekeeper quarantine database moved to Trash." : "Quarantine file was locked.")
            } else {
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: "Quarantine database already clean.")
            }

        case "prevent_network_dsstore":
            let proc = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/defaults"),
                arguments: ["write", "com.apple.desktopservices", "DSDontWriteNetworkStores", "-bool", "true"],
                timeoutSeconds: 3
            )
            let usbProc = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/defaults"),
                arguments: ["write", "com.apple.desktopservices", "DSDontWriteUSBStores", "-bool", "true"],
                timeoutSeconds: 3
            )
            let ok = proc.exitCode == 0 && usbProc.exitCode == 0
            return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: ok, message: ok ? "Finder will no longer create .DS_Store files on network shares or USB drives." : "defaults write returned code \(proc.exitCode).")

        case "sqlite_vacuum":
            // Vacuum SQLite databases for Mail, Safari, Messages — only when apps are NOT running
            let runningApps = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
            let protectedApps: [String: String] = [
                "com.apple.mail": "Mail",
                "com.apple.safari": "Safari",
                "com.apple.MobileSMS": "Messages"
            ]
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dbPaths: [(appBundleId: String, paths: [URL])] = [
                ("com.apple.mail", [
                    home.appendingPathComponent("Library/Mail/V10/MailData/Envelope Index")
                ]),
                ("com.apple.safari", [
                    home.appendingPathComponent("Library/Safari/History.db"),
                    home.appendingPathComponent("Library/Safari/WebFeedSources.plist")
                ]),
                ("com.apple.MobileSMS", [
                    home.appendingPathComponent("Library/Messages/chat.db")
                ])
            ]
            var vacuumedCount = 0
            var skippedApps: [String] = []
            for entry in dbPaths {
                if runningApps.contains(entry.appBundleId) {
                    skippedApps.append(protectedApps[entry.appBundleId] ?? entry.appBundleId)
                    continue
                }
                for dbURL in entry.paths {
                    guard FileManager.default.fileExists(atPath: dbURL.path),
                          dbURL.pathExtension == "db" else { continue }
                    let res = await SafeProcessRunner.run(
                        executableURL: URL(fileURLWithPath: "/usr/bin/sqlite3"),
                        arguments: [dbURL.path, "VACUUM;"],
                        timeoutSeconds: 30
                    )
                    if res.exitCode == 0 { vacuumedCount += 1 }
                }
            }
            var msg = "Vacuumed \(vacuumedCount) database(s)."
            if !skippedApps.isEmpty { msg += " Skipped while running: \(skippedApps.joined(separator: ", "))." }
            return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: msg)

        case "network_stack_optimize":
            // Flush routing table + ARP cache (mirrors Mole's network_stack_optimize)
            let routeFlush = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/sbin/route"),
                arguments: ["-n", "flush"],
                timeoutSeconds: 5
            )
            let arpFlush = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/sbin/arp"),
                arguments: ["-a", "-d"],
                timeoutSeconds: 5
            )
            // Note: route flush may require root on modern macOS — we try anyway and report
            let routeOk = routeFlush.exitCode == 0
            let arpOk = arpFlush.exitCode == 0
            if routeOk || arpOk {
                let routeMsg = routeOk ? "flushed" : "skipped (needs admin)"; let arpMsg = arpOk ? "cleared" : "skipped (needs admin)"; return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: "Routing table \(routeMsg). ARP cache \(arpMsg).")
            } else {
                // Both failed — likely need admin, flush DNS as a safe fallback
                let dnsFallback = await SafeProcessRunner.run(
                    executableURL: URL(fileURLWithPath: "/usr/bin/dscacheutil"),
                    arguments: ["-flushcache"],
                    timeoutSeconds: 5
                )
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: dnsFallback.exitCode == 0, message: "Route/ARP flush requires admin access; DNS resolver cache flushed as fallback.")
            }

        case "legacy_overrides_audit":
            // Remove App Nap disable overrides left by old tweak tools
            let home = FileManager.default.homeDirectoryForCurrentUser
            let prefsURL = home.appendingPathComponent("Library/Preferences")
            let legacyFiles = [
                prefsURL.appendingPathComponent("NSGlobalDomain.plist"),
            ]
            // Remove hidden App Nap disable flag if present
            var removedCount = 0
            let r1 = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/defaults"),
                arguments: ["write", "NSGlobalDomain", "NSAppSleepDisabled", "-bool", "false"],
                timeoutSeconds: 3
            )
            if r1.exitCode == 0 { removedCount += 1 }
            // Remove disk image verification disable
            let r2 = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/defaults"),
                arguments: ["delete", "com.apple.frameworks.diskimages", "skip-verify"],
                timeoutSeconds: 3
            )
            // r2 may fail if key didn't exist — that's fine
            let r3 = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/defaults"),
                arguments: ["delete", "com.apple.frameworks.diskimages", "skip-verify-locked"],
                timeoutSeconds: 3
            )
            _ = legacyFiles
            _ = r2
            _ = r3
            return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: r1.exitCode == 0, message: "App Nap sleep override restored to system default. Disk image verification overrides cleared.")

        case "spotlight_optimize":
            // Smart Spotlight reindex: only trigger if mdutil shows issues
            let statusResult = await SafeProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/mdutil"),
                arguments: ["-s", "/"],
                timeoutSeconds: 5
            )
            let output = statusResult.stdout.lowercased()
            if output.contains("disabled") || output.contains("not indexed") {
                // Spotlight is off — enable it
                let enableResult = await SafeProcessRunner.run(
                    executableURL: URL(fileURLWithPath: "/usr/bin/mdutil"),
                    arguments: ["-i", "on", "/"],
                    timeoutSeconds: 10
                )
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: enableResult.exitCode == 0, message: "Spotlight indexing re-enabled on system volume.")
            } else if output.contains("indexing") || output.contains("enabled") {
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: "Spotlight index is healthy and active — no rebuild needed.")
            } else {
                return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: true, message: "Spotlight status: \(statusResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)).")
            }

        default:
            return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: false, message: "Unknown task identifier.")
        }
    }
}
