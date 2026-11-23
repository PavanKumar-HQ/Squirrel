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

        default:
            return SystemOptimizationResult(taskId: id, taskTitle: title, succeeded: false, message: "Unknown task identifier.")
        }
    }
}
