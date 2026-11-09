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

        // Rule 1: Xcode DerivedData
        if pathLower.contains("/developer/xcode/deriveddata") {
            return Finding(
                category: .developerCaches,
                title: "Xcode DerivedData: \(item.name)",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-XCODE-DERIVEDDATA",
                ruleDescription: "Xcode intermediate build products, indexes, and compilation modules.",
                evidence: [
                    "Located inside ~/Library/Developer/Xcode/DerivedData",
                    "Regenerated automatically on next project build"
                ],
                eligibility: .safeToClean,
                riskLevel: .low,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: "Xcode will automatically re-index and rebuild compilation artifacts the next time you compile the project."
            )
        }

        // Rule 2: Xcode iOS DeviceSupport & Simulator Caches
        if pathLower.contains("/developer/xcode/ios devicesupport") ||
           pathLower.contains("/developer/xcode/watchos devicesupport") ||
           pathLower.contains("/developer/coresimulator/caches") {
            let isDeviceSupport = pathLower.contains("devicesupport")
            return Finding(
                category: .developerCaches,
                title: isDeviceSupport ? "Xcode Device Support Symbols: \(item.name)" : "CoreSimulator Cache: \(item.name)",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: isDeviceSupport ? "RULE-XCODE-DEVICESUPPORT" : "RULE-XCODE-SIMULATOR-CACHE",
                ruleDescription: isDeviceSupport ? "Symbol files cached from connected iOS/watchOS devices for debug symbolication." : "Simulator runtime and image cache.",
                evidence: [
                    "Located inside Xcode Developer directories",
                    isDeviceSupport ? "Historical device debug symbols" : "Simulator runtime cache"
                ],
                eligibility: isDeviceSupport ? .reviewRecommended : .safeToClean,
                riskLevel: isDeviceSupport ? .medium : .low,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: isDeviceSupport
                    ? "Symbolic files for older iOS versions will be removed. Xcode will re-fetch symbols if you reconnect the device."
                    : "Simulator caches will be cleaned; rebuilt on next simulator launch."
            )
        }

        // Rule 3: Package Manager & Toolchain Caches (npm, pnpm, yarn, pip, uv, cargo, go-build, gradle, maven, cocoapods)
        if isPackageManagerCache(path: pathLower, name: nameLower) {
            let toolName = identifyToolName(path: pathLower, name: nameLower)
            return Finding(
                category: .developerCaches,
                title: "\(toolName) Cache (\(item.name))",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-PKG-CACHE",
                ruleDescription: "Downloaded package archives, precompiled binaries, or bytecode stored by \(toolName).",
                evidence: [
                    "Identified toolchain cache directory: \(toolName)",
                    "Packages are downloaded on demand if needed again"
                ],
                eligibility: .safeToClean,
                riskLevel: .low,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: "\(toolName) will re-download packages on next install if not already cached locally."
            )
        }

        // Rule 4: Project Build Artifacts (node_modules, target, dist, build, .venv, .next, etc.)
        if isProjectPurgeTarget(path: pathLower, name: nameLower) {
            let artifactType = identifyArtifactType(name: nameLower)
            let isBuildCache = (nameLower == ".next" || nameLower == ".turbo")
            let ruleId = isBuildCache ? "RULE-BUILD-CACHE" : "RULE-PROJECT-PURGE"
            return Finding(
                category: .projectArtifacts,
                title: "Project Artifact: \(item.name) (\(artifactType))",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: ruleId,
                ruleDescription: "Heavy project dependency or build output directory (\(artifactType)).",
                evidence: [
                    "Matches project artifact signature: \(item.name)",
                    "Source files, configs, and git history remain fully untouched outside this directory"
                ],
                eligibility: .reviewRecommended,
                riskLevel: .low,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: "Removes compiled build artifacts or installed dependencies. They can be reinstalled anytime using your project package manager (e.g. npm install, cargo build)."
            )
        }

        // Rule 5: Sandboxed App Container Caches
        if isContainerCache(path: pathLower) {
            return Finding(
                category: .appContainers,
                title: "App Container Cache: \(item.name)",
                path: item.path,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                ruleId: "RULE-CONTAINER-CACHE",
                ruleDescription: "Sandboxed application container caches stored under ~/Library/Containers or Group Containers.",
                evidence: [
                    "Located inside sandboxed container cache path",
                    "Temporary application cache data"
                ],
                eligibility: .safeToClean,
                riskLevel: .low,
                recoveryMethod: .macOSTrash,
                estimatedReclaimableBytes: item.allocatedSize,
                consequencesExplanation: "Applications will regenerate necessary caches automatically when opened."
            )
        }

        // Rule 6: User Caches (~/Library/Caches)
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

        // Rule 7: System & App Logs
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

        // Rule 8: Download Installers & Disk Images
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

        // Rule 9: Large Files
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

    private func isPackageManagerCache(path: String, name: String) -> Bool {
        if path.contains("/.npm/_cacache") || path.hasSuffix("/.npm/_cacache") { return true }
        if path.contains("/library/caches/pnpm") || path.contains("/.local/share/pnpm/store") { return true }
        if path.contains("/library/caches/yarn") { return true }
        if path.contains("/library/caches/pip") { return true }
        if path.contains("/.cache/uv") || path.contains("/library/caches/uv") { return true }
        if path.contains("/.cache/poetry") || path.contains("/library/caches/pypoetry") { return true }
        if path.contains("/.cargo/registry/cache") || path.contains("/.rustup/downloads") { return true }
        if path.contains("/library/caches/go-build") { return true }
        if path.contains("/.gradle/caches") { return true }
        if path.contains("/.m2/repository") { return true }
        if path.contains("/library/caches/cocoapods") { return true }
        if path.contains("/library/caches/homebrew") { return true }
        return false
    }

    private func identifyToolName(path: String, name: String) -> String {
        if path.contains("npm") { return "npm" }
        if path.contains("pnpm") { return "pnpm" }
        if path.contains("yarn") { return "Yarn" }
        if path.contains("pip") { return "pip" }
        if path.contains("uv") { return "uv" }
        if path.contains("poetry") { return "Poetry" }
        if path.contains("cargo") || path.contains("rustup") { return "Rust / Cargo" }
        if path.contains("go-build") { return "Go" }
        if path.contains("gradle") { return "Gradle" }
        if path.contains(".m2") { return "Maven" }
        if path.contains("cocoapods") { return "CocoaPods" }
        if path.contains("homebrew") { return "Homebrew" }
        return "Package Manager"
    }

    private func isProjectPurgeTarget(path: String, name: String) -> Bool {
        let targets = [
            "node_modules", "target", "dist", "build", "venv", ".venv",
            ".next", ".turbo", ".nuxt", ".output", ".svelte-kit", ".astro",
            ".dart_tool", ".zig-cache", "zig-out", "pods", ".cxx", ".build"
        ]
        return targets.contains(name)
    }

    private func identifyArtifactType(name: String) -> String {
        switch name {
        case "node_modules": return "Node.js Dependencies"
        case "target": return "Rust / Cargo / Maven Build"
        case "dist", "build": return "Compiled Build Output"
        case "venv", ".venv": return "Python Virtual Environment"
        case ".next": return "Next.js Build Cache"
        case ".turbo": return "Turborepo Cache"
        case ".svelte-kit": return "SvelteKit Cache"
        case ".astro": return "Astro Build Cache"
        case ".build": return "Swift Package Manager Build"
        case "pods": return "CocoaPods Dependencies"
        default: return "Build Artifact"
        }
    }

    private func isContainerCache(path: String) -> Bool {
        return (path.contains("/library/containers/") && path.contains("/data/library/caches/")) ||
               (path.contains("/library/group containers/") && path.contains("/library/caches/"))
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

    public func determineCategory(for item: StorageItem) -> StorageCategory {
        let path = item.path.lowercased()
        let name = item.name.lowercased()

        if path.contains("/developer/xcode/") || isPackageManagerCache(path: path, name: name) {
            return .developerCaches
        } else if isProjectPurgeTarget(path: path, name: name) {
            return .projectArtifacts
        } else if isContainerCache(path: path) {
            return .appContainers
        } else if path.contains("/caches/") || path.hasSuffix("/caches") {
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
