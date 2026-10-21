import Foundation
import SwiftUI
import Combine
import SquirrelCore

public enum ScanStatus: String, Sendable {
    case idle = "Not Scanned"
    case scanning = "Scanning Filesystem..."
    case completed = "Scan Completed"
    case cancelled = "Scan Cancelled"
}

public enum NavigationSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case findings = "Findings"
    case treemap = "Storage Treemap"
    case duplicates = "Exact Duplicates"
    case history = "History & Quarantine"
    case permissions = "Inaccessible Areas"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .dashboard: return "gauge.with.needle"
        case .findings: return "checklist"
        case .treemap: return "square.grid.3x3"
        case .duplicates: return "doc.on.doc"
        case .history: return "clock.arrow.circlepath"
        case .permissions: return "lock.shield"
        }
    }
}

public final class AppState: ObservableObject, @unchecked Sendable {
    public static let shared = AppState()

    // Navigation and UI state
    @Published public var selectedSection: NavigationSection = .dashboard
    @Published public var showCleanSafelyConfirm: Bool = false
    @Published public var showFindingConfirmSheet: Bool = false
    @Published public var showDuplicateConfirmSheet: Bool = false
    @Published public var selectedFindingFilterIndex: Int = 0
    @Published public var findingSearchText: String = ""
    @Published public var expandedFindingId: UUID? = nil
    @Published public var selectedHistoryTab: Int = 0

    // Volume metrics
    @Published public var volumeSpace: VolumeSpace = VolumeSpace.querySystemVolume()

    // Scan State
    @Published public var scanStatus: ScanStatus = .idle
    @Published public var scanProgress: ScanProgress = ScanProgress()
    @Published public var lastScanDate: Date? = nil

    @Published public var scanTargetDescription: String = "Standard Folders (Downloads, Caches, Logs)"
    @Published public var customScanRootURL: URL? = nil

    // Findings and Data
    @Published public var scannedItems: [StorageItem] = []
    @Published public var findings: [Finding] = []
    @Published public var safeFindings: [Finding] = []
    @Published public var reviewFindings: [Finding] = []
    @Published public var keepFindings: [Finding] = []
    @Published public var safeCount: Int = 0
    @Published public var reviewCount: Int = 0
    @Published public var keepCount: Int = 0
    @Published public var duplicateGroups: [DuplicateGroup] = []
    @Published public var inaccessibleLocations: [InaccessibleLocation] = []
    @Published public var treemapRoot: TreemapNode = TreemapNode(name: "Storage", path: "/", size: 0, category: .otherUserData, isDirectory: true)
    @Published public var activeTreemapRoot: TreemapNode = TreemapNode(name: "Storage", path: "/", size: 0, category: .otherUserData, isDirectory: true)

    // Selection
    @Published public var selectedTreemapNode: TreemapNode? = nil
    @Published public var hoveredTreemapNodeId: UUID? = nil
    @Published public var treemapBreadcrumbs: [TreemapNode] = []
    @Published public var selectedFindingIds: Set<UUID> = []
    @Published public var selectedDuplicatePaths: Set<String> = []

    // Pagination & Treemap Layout Cache
    @Published public var findingsDisplayLimit: Int = 100
    @Published public var duplicatesDisplayLimit: Int = 50
    public var treemapCachedLayout: (rootId: UUID, size: CGSize, node: TreemapNode)? = nil

    // Cleanup Execution State
    @Published public var isCleaning: Bool = false
    @Published public var cleanupProgress: CleanupProgress = CleanupProgress()
    @Published public var lastCleanupSummary: CleanupSummary? = nil
    @Published public var showCleanupSummarySheet: Bool = false

    // History and Quarantine
    @Published public var journalEntries: [JournalEntry] = []
    @Published public var quarantineRecords: [QuarantineRecord] = []

    // Core Engines
    private let scanner = FilesystemScanner()
    private let duplicateDetector = DuplicateDetector()
    private let cleanupEngine = CleanupEngine()
    private let quarantineManager = QuarantineManager()

    public init() {
        refreshVolumeMetrics()
        refreshHistory()
    }

    public func refreshVolumeMetrics(for url: URL? = nil) {
        if let targetURL = url {
            self.volumeSpace = VolumeSpace.queryVolume(at: targetURL)
        } else {
            self.volumeSpace = VolumeSpace.querySystemVolume()
        }
        Task.detached(priority: .utility) {
            let audit = await AppleStorageAuditor.auditSystemStorage()
            await MainActor.run {
                self.volumeSpace.auditReport = audit
            }
        }
    }

    public func refreshHistory() {
        self.journalEntries = JournalManager.shared.getEntries()
        Task {
            let records = await quarantineManager.getRecords()
            await MainActor.run {
                self.quarantineRecords = records
            }
        }
    }

    // MARK: - Safe Scan Execution
    @MainActor
    public func selectCustomFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Folder"
        panel.message = "Choose a real directory or volume on this Mac to scan with Squirrel"
        if panel.runModal() == .OK, let selectedURL = panel.url {
            self.customScanRootURL = selectedURL
            self.scanTargetDescription = selectedURL.path
            self.refreshVolumeMetrics(for: selectedURL)
            self.startScan(customRoots: [selectedURL], targetDescription: selectedURL.path)
        }
    }

    public func startScan(customRoots: [URL]? = nil, targetDescription: String? = nil) {
        guard scanStatus != .scanning else { return }
        scanStatus = .scanning
        scanProgress = ScanProgress(currentPath: "Initializing scan roots...", itemsScannedCount: 0, bytesScannedTotal: 0, currentCategory: "Setup")
        selectedTreemapNode = nil
        treemapBreadcrumbs.removeAll()
        selectedFindingIds.removeAll()
        selectedDuplicatePaths.removeAll()

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        let roots: [URL]
        let description: String
        if let custom = customRoots, !custom.isEmpty {
            roots = custom
            description = targetDescription ?? custom.first?.path ?? "Custom Selection"
        } else {
            roots = [
                home.appendingPathComponent("Downloads", isDirectory: true),
                home.appendingPathComponent("Library/Caches", isDirectory: true),
                home.appendingPathComponent("Library/Logs", isDirectory: true)
            ]
            description = "Standard Folders (Downloads, Caches, Logs)"
        }

        self.scanTargetDescription = description

        Task {
            let validRoots = roots.filter { fileManager.fileExists(atPath: $0.path) && fileManager.isReadableFile(atPath: $0.path) }

            let result = await scanner.scan(roots: validRoots) { progress in
                Task { @MainActor in
                    self.scanProgress = progress
                }
            }

            // Classify findings and partition in background
            var computedFindings: [Finding] = []
            var safeList: [Finding] = []
            var reviewList: [Finding] = []
            var keepList: [Finding] = []

            let rules = ClassificationRules.shared
            let inaccessiblePaths = Set(result.inaccessibleLocations.map { $0.path })
            for item in result.items {
                if let finding = rules.classify(item: item, inaccessiblePaths: inaccessiblePaths) {
                    computedFindings.append(finding)
                    switch finding.eligibility {
                    case .safeToClean: safeList.append(finding)
                    case .reviewRecommended: reviewList.append(finding)
                    case .keep: keepList.append(finding)
                    }
                }
            }

            // Build Treemap Hierarchy
            let rootTreemap = TreemapEngine.buildHierarchy(from: result.items)

            let duplicates = await duplicateDetector.findDuplicates(items: result.items) { msg in
                Task { @MainActor in
                    self.scanProgress = ScanProgress(
                        currentPath: msg,
                        itemsScannedCount: result.items.count,
                        bytesScannedTotal: result.totalLogicalBytes,
                        currentCategory: "Duplicates",
                        isComplete: false
                    )
                }
            }

            // Sort all collections once in background by allocated size
            let finalFindings = computedFindings.sorted { $0.allocatedSize > $1.allocatedSize }
            let finalSafe = safeList.sorted { $0.allocatedSize > $1.allocatedSize }
            let finalReview = reviewList.sorted { $0.allocatedSize > $1.allocatedSize }
            let finalKeep = keepList.sorted { $0.allocatedSize > $1.allocatedSize }

            await MainActor.run {
                self.scannedItems = result.items
                self.findings = finalFindings
                self.safeFindings = finalSafe
                self.reviewFindings = finalReview
                self.keepFindings = finalKeep
                self.safeCount = finalSafe.count
                self.reviewCount = finalReview.count
                self.keepCount = finalKeep.count
                self.duplicateGroups = duplicates
                self.inaccessibleLocations = result.inaccessibleLocations
                self.treemapRoot = rootTreemap
                self.activeTreemapRoot = rootTreemap
                self.selectedTreemapNode = rootTreemap.children.first
                self.scanStatus = result.completedNormally ? .completed : .cancelled
                self.lastScanDate = Date()
                self.refreshVolumeMetrics()
            }
        }
    }

    public func cancelScan() {
        Task {
            await scanner.cancel()
            await duplicateDetector.cancel()
            await MainActor.run {
                self.scanStatus = .cancelled
            }
        }
    }

    // MARK: - Cleanup Execution
    public func executeSafeBatch() {
        guard !isCleaning else { return }
        isCleaning = true
        cleanupProgress = CleanupProgress(completedCount: 0, totalCount: 1, currentItemName: "Validating safe items...")

        Task {
            let summary = await cleanupEngine.executeSafeBatch(findings: findings) { prog in
                Task { @MainActor in
                    self.cleanupProgress = prog
                }
            }

            await MainActor.run {
                self.isCleaning = false
                self.lastCleanupSummary = summary
                self.showCleanupSummarySheet = true
                self.refreshHistory()
                self.refreshVolumeMetrics()

                let succeededPaths = Set(self.journalEntries.filter { $0.status == .success }.map { $0.originalPath })
                self.findings.removeAll { succeededPaths.contains($0.path) }
                self.scannedItems.removeAll { succeededPaths.contains($0.path) }
                self.treemapRoot = TreemapEngine.buildHierarchy(from: self.scannedItems)
                self.activeTreemapRoot = self.treemapRoot
            }
        }
    }

    public func executeSelectedFindings() {
        guard !isCleaning, !selectedFindingIds.isEmpty else { return }
        isCleaning = true
        let selected = findings.filter { selectedFindingIds.contains($0.id) }

        Task {
            let summary = await cleanupEngine.executeSelected(findings: selected) { prog in
                Task { @MainActor in
                    self.cleanupProgress = prog
                }
            }

            await MainActor.run {
                self.isCleaning = false
                self.lastCleanupSummary = summary
                self.showCleanupSummarySheet = true
                self.selectedFindingIds.removeAll()
                self.refreshHistory()
                self.refreshVolumeMetrics()

                let succeededPaths = Set(self.journalEntries.filter { $0.status == .success }.map { $0.originalPath })
                self.findings.removeAll { succeededPaths.contains($0.path) }
                self.scannedItems.removeAll { succeededPaths.contains($0.path) }
                self.treemapRoot = TreemapEngine.buildHierarchy(from: self.scannedItems)
                self.activeTreemapRoot = self.treemapRoot
            }
        }
    }

    public func executeDuplicateCleanup() {
        guard !isCleaning, !selectedDuplicatePaths.isEmpty else { return }
        isCleaning = true

        var membersToDelete: [DuplicateMember] = []
        for group in duplicateGroups {
            for member in group.files {
                if selectedDuplicatePaths.contains(member.path) {
                    membersToDelete.append(member)
                }
            }
        }

        Task {
            let summary = await cleanupEngine.deleteDuplicateCopies(members: membersToDelete) { prog in
                Task { @MainActor in
                    self.cleanupProgress = prog
                }
            }

            await MainActor.run {
                self.isCleaning = false
                self.lastCleanupSummary = summary
                self.showCleanupSummarySheet = true
                self.selectedDuplicatePaths.removeAll()
                self.refreshHistory()
                self.refreshVolumeMetrics()

                let succeededPaths = Set(self.journalEntries.filter { $0.status == .success }.map { $0.originalPath })
                var updatedGroups: [DuplicateGroup] = []
                for group in self.duplicateGroups {
                    let remaining = group.files.filter { !succeededPaths.contains($0.path) }
                    if remaining.count > 1 {
                        updatedGroups.append(DuplicateGroup(sha256Hash: group.sha256Hash, fileSize: group.fileSize, files: remaining))
                    }
                }
                self.duplicateGroups = updatedGroups
                self.scannedItems.removeAll { succeededPaths.contains($0.path) }
                self.treemapRoot = TreemapEngine.buildHierarchy(from: self.scannedItems)
                self.activeTreemapRoot = self.treemapRoot
            }
        }
    }

    // MARK: - Treemap Navigation
    public func resetTreemapToOverview() {
        self.activeTreemapRoot = self.treemapRoot
        self.treemapBreadcrumbs.removeAll()
        self.selectedTreemapNode = nil
    }

    public func drillDownTreemap(to node: TreemapNode) {
        if !node.children.isEmpty {
            self.treemapBreadcrumbs.append(node)
            self.activeTreemapRoot = node
            self.selectedTreemapNode = node
        }
    }

    public func navigateTreemapBreadcrumb(at index: Int) {
        guard index < self.treemapBreadcrumbs.count else { return }
        let target = self.treemapBreadcrumbs[index]
        self.activeTreemapRoot = target
        self.treemapBreadcrumbs = Array(self.treemapBreadcrumbs.prefix(index + 1))
        self.selectedTreemapNode = target
    }

    public func restoreQuarantineItem(record: QuarantineRecord) {
        Task {
            do {
                _ = try await quarantineManager.restoreFile(recordId: record.id)
                JournalManager.shared.record(JournalEntry(
                    originalPath: record.originalPath,
                    sanitizedName: URL(fileURLWithPath: record.originalPath).lastPathComponent,
                    actionType: .restoredFromQuarantine,
                    status: .restored,
                    bytesReclaimed: 0,
                    recoveryMethod: .managedQuarantine,
                    quarantineId: record.id
                ))
                await MainActor.run {
                    self.refreshHistory()
                }
            } catch {
                JournalManager.shared.record(JournalEntry(
                    originalPath: record.originalPath,
                    sanitizedName: URL(fileURLWithPath: record.originalPath).lastPathComponent,
                    actionType: .restoredFromQuarantine,
                    status: .failed,
                    bytesReclaimed: 0,
                    recoveryMethod: .managedQuarantine,
                    quarantineId: record.id,
                    errorMessage: error.localizedDescription
                ))
                await MainActor.run {
                    self.refreshHistory()
                }
            }
        }
    }

    // Computed totals
    public var safeToCleanBytes: Int64 {
        findings
            .filter { $0.category.isBatchCleanEligible && $0.eligibility == .safeToClean }
            .reduce(0) { $0 + $1.allocatedSize }
    }

    public var reviewRecommendedBytes: Int64 {
        findings
            .filter { $0.eligibility == .reviewRecommended }
            .reduce(0) { $0 + $1.allocatedSize }
    }

    public var duplicatePotentialReclaimBytes: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.potentialReclaimableBytes }
    }
}
