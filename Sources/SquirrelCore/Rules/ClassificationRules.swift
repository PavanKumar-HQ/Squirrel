import Foundation

/// Engine that evaluates discovered items against evidence-based safety rules.
public struct ClassificationRules {
    public static let shared = ClassificationRules()

    public init() {}

    /// Classifies an individual discovered item into a traceable Finding.
    public func classify(item: StorageItem, inaccessiblePaths: Set<String> = []) -> Finding? {
        let pathLower = item.path.lowercased()
        let nameLower = item.name.lowercased()

        // Rule 0: TCC / System / Inaccessible / Non-writable protection
        if !item.isWritable || isPathProtectedOrInaccessible(item.path, inaccessiblePaths: inaccessiblePaths) {
            return Finding(
                category: determineCategory(for: item),
                title: "Protected Item (\(item.name))",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-TCC-RESTRICTED",
                ruleDescription: "This location is protected by macOS System Integrity Protection (SIP) or TCC privacy controls and cannot be modified without elevated permissions.",
                evidence: ["System permissions prevent modification", "Protected by macOS security policy"],
                eligibility: .keep,
                riskLevel: .high,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: 0,
                consequencesExplanation: "Cannot be modified safely; excluded from cleanup.",
                exclusionReason: "macOS TCC/SIP permission restricted"
            )
        }

        // Rule: Developer artifacts - explicitly excluded from first-release cleanup
        if isDeveloperArtifact(path: pathLower) {
            return Finding(
                category: .otherUserData,
                title: "Development Artifact (\(item.name))",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-DEV-EXCLUDE",
                ruleDescription: "Developer build caches, dependencies, and environments are intentionally excluded from cleanup in v1.0 to prevent breaking developer workflows.",
                evidence: ["Matches developer workspace pattern: \(item.name)"],
                eligibility: .keep,
                riskLevel: .high,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: 0,
                consequencesExplanation: "Removing active project dependencies or build caches can corrupt compilation workflows or require lengthy re-downloads.",
                exclusionReason: "Developer workspace protection policy"
            )
        }

        // Rule: User Caches
        if pathLower.contains("/library/caches/") || pathLower.hasSuffix("/library/caches") {
            let isOld = isOlderThan(date: item.modificationDate, days: 7)
            let eligibility: CleanupEligibility = isOld ? .safeToClean : .reviewRecommended
            let risk: RiskLevel = isOld ? .low : .medium

            return Finding(
                category: .userCaches,
                title: "User Cache: \(item.name)",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-CACHE-01",
                ruleDescription: "User-level application cache files generated for temporary performance or pre-rendered assets.",
                evidence: [
                    "Located within ~/Library/Caches",
                    isOld ? "Modified more than 7 days ago" : "Recently modified (< 7 days)"
                ],
                eligibility: eligibility,
                riskLevel: risk,
                recoveryMethod: .managedQuarantine,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: "Applications will regenerate caches as needed upon next launch. First launch after cleanup might be slightly slower while caches rebuild."
            )
        }

        // Rule: System & App Logs
        if pathLower.contains("/library/logs/") || nameLower.hasSuffix(".log") || nameLower.hasSuffix(".diag") || nameLower.hasSuffix(".crash") {
            let isOld = isOlderThan(date: item.modificationDate, days: 14)
            let eligibility: CleanupEligibility = isOld ? .safeToClean : .reviewRecommended

            return Finding(
                category: .systemLogs,
                title: "Diagnostic Log: \(item.name)",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-LOGS-01",
                ruleDescription: "Application logs and diagnostic traces stored in user logs directory.",
                evidence: [
                    "File extension matches log/crash/diag format",
                    isOld ? "Inactive for more than 14 days" : "Active within past 14 days"
                ],
                eligibility: eligibility,
                riskLevel: .low,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: "Historical diagnostic records will be moved to Trash. No application configuration or active user data is affected."
            )
        }

        // Rule: Download Installers & Disk Images
        if nameLower.hasSuffix(".dmg") || nameLower.hasSuffix(".pkg") || nameLower.hasSuffix(".iso") {
            return Finding(
                category: .downloadsAndInstallers,
                title: "Installer Package: \(item.name)",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-INSTALLER-01",
                ruleDescription: "Downloaded software installation image or package.",
                evidence: [
                    "Disk image or installer package format",
                    "Stored in user directory: \(item.path)"
                ],
                eligibility: .reviewRecommended, // Never batch delete installers
                riskLevel: .medium,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: "If the application inside this installer has already been installed into /Applications, keeping the original disk image is usually unnecessary."
            )
        }

        // Rule: Large Files
        if item.logicalSize >= 100 * 1024 * 1024 {
            return Finding(
                category: .largeFiles,
                title: "Large File: \(item.name)",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-LARGE-01",
                ruleDescription: "Individual file consuming greater than 100 MB of disk space.",
                evidence: [
                    "File size exceeds 100 MB threshold (\(ByteCountFormatter.string(fromByteCount: item.logicalSize, countStyle: .file)))"
                ],
                eligibility: .reviewRecommended,
                riskLevel: .medium,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: "User review required. Personal videos, virtual disk images, or archives should only be deleted if no longer needed."
            )
        }

        return nil
    }

    private func isDeveloperArtifact(path: String) -> Bool {
        return path.contains("/deriveddata/") ||
               path.contains("/node_modules/") ||
               path.contains("/.cargo/") ||
               path.contains("/.rustup/") ||
               path.contains("/docker/") ||
               path.contains("/.gradle/") ||
               path.contains("/target/debug/") ||
               path.contains("/target/release/")
    }

    private func isOlderThan(date: Date?, days: Int) -> Bool {
        guard let date = date else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return date < cutoff
    }

    private func isPathProtectedOrInaccessible(_ path: String, inaccessiblePaths: Set<String>) -> Bool {
        if inaccessiblePaths.contains(path) { return true }
        for inacc in inaccessiblePaths {
            let prefix = inacc.hasSuffix("/") ? inacc : "\(inacc)/"
            if path.hasPrefix(prefix) { return true }
        }
        return false
    }

    private func determineCategory(for item: StorageItem) -> StorageCategory {
        let path = item.path.lowercased()
        if path.contains("/caches/") || path.hasSuffix("/caches") {
            return .userCaches
        } else if path.contains("/logs/") || path.hasSuffix(".log") || path.hasSuffix(".diag") || path.hasSuffix(".crash") {
            return .systemLogs
        } else if path.hasSuffix(".dmg") || path.hasSuffix(".pkg") || path.hasSuffix(".iso") || path.contains("/downloads/") {
            return .downloadsAndInstallers
        } else if item.logicalSize >= 100 * 1024 * 1024 {
            return .largeFiles
        } else {
            return .otherUserData
        }
    }
}
