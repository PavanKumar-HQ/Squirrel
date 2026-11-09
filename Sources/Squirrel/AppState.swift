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
    case readyToClean = "Ready to Clean"
    case dashboard = "Dashboard"
    case findings = "Findings"
    case treemap = "Storage Treemap"
    case projectPurge = "Project Purge"
    case nativeTools = "Developer Tools"
    case apfsSnapshots = "APFS Snapshots"
    case duplicates = "Exact Duplicates"
    case history = "History & Quarantine"
    case folderAccess = "Folder Access"
    case permissions = "Inaccessible Areas"
    case diagnostics = "Diagnostics & Efficiency"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .readyToClean: return "sparkles"
        case .dashboard: return "gauge.with.needle"
        case .findings: return "checklist"
        case .treemap: return "square.grid.3x3"
        case .projectPurge: return "shippingbox"
        case .nativeTools: return "hammer"
        case .apfsSnapshots: return "camera.metering.matrix"
        case .duplicates: return "doc.on.doc"
        case .history: return "clock.arrow.circlepath"
        case .folderAccess: return "folder.badge.gearshape"
        case .permissions: return "lock.shield"
        case .diagnostics: return "speedometer"
        }
    }
}

public struct CleanResultFeedback: Sendable, Equatable {
    public let reclaimedBytes: Int64
    public let itemsCleanedCount: Int
    public let itemsSkippedCount: Int
    public let skippedReasons: [String]

    public init(reclaimedBytes: Int64, itemsCleanedCount: Int, itemsSkippedCount: Int, skippedReasons: [String] = []) {
        self.reclaimedBytes = reclaimedBytes
        self.itemsCleanedCount = itemsCleanedCount
        self.itemsSkippedCount = itemsSkippedCount
        self.skippedReasons = skippedReasons
    }
}

public final class AppState: ObservableObject, @unchecked Sendable {
    public static let shared = AppState()

    // Navigation and UI state
    @Published public var selectedSection: NavigationSection = .readyToClean
    @Published public var readyToCleanSummary: ReadyToCleanSummary = ReadyToCleanSummary()
    @Published public var isAuditingHub: Bool = false
    @Published public var hubAuditProgress: String = ""
    @Published public var expandedHubCategories: Set<CleanGroupCategory> = [.developerTools, .systemData]
    @Published public var showHubConfirmClean: Bool = false
    @Published public var showCleanSafelyConfirm: Bool = false
    @Published public var lastCleanResult: CleanResultFeedback? = nil
    @Published public var showCleanResultBanner: Bool = false
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
    @Published public var isScanningDuplicates: Bool = false
    @Published public var duplicateScanProgressText: String = ""
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

    // Project Purge State (Mole-inspired)
    @Published public var discoveredProjects: [ProjectCandidate] = []
    @Published public var isScanningProjects: Bool = false
    @Published public var projectScanProgressText: String = ""
    @Published public var projectPurgeSearchText: String = ""
    @Published public var selectedProjectPaths: Set<String> = []
    @Published public var showConfirmPurge: Bool = false
    @Published public var isPurgingProjects: Bool = false

    // Native Developer Tools State (Mole-inspired)
    @Published public var supportedTools: [SupportedTool] = []
    @Published public var isRefreshingTools: Bool = false
    @Published public var pruningToolName: String? = nil
    @Published public var toolConsoleOutput: String = ""
    @Published public var showToolConsoleSheet: Bool = false
    @Published public var toolConsoleTitle: String = ""

    // APFS Snapshots State (Mole-inspired)
    @Published public var localSnapshots: [LocalSnapshot] = []
    @Published public var isRefreshingSnapshots: Bool = false
    @Published public var deletingSnapshotName: String? = nil
    @Published public var showConfirmDeleteAllSnapshots: Bool = false

    // History and Quarantine
    @Published public var journalEntries: [JournalEntry] = []
    @Published public var quarantineRecords: [QuarantineRecord] = []

    // Folder Access & Bookmarks
    @Published public var authorizedFolders: [AuthorizedFolderRecord] = []

    // Diagnostics & Efficiency Telemetry
    @Published public var lastScanPerformance: ScanPerformanceRecord? = nil
    @Published public var recentBenchmarkRecords: [ScanPerformanceRecord] = []
    @Published public var lastControlledBenchmark: BenchmarkComparison? = nil
    @Published public var currentProcessTelemetry: ProcessTelemetry = ProcessTelemetry()
    @Published public var isRunningBenchmark: Bool = false
    @Published public var benchmarkStatusText: String = ""
    public var lastScanDuration: TimeInterval = 0

    // Core Engines
    private let scanner = FilesystemScanner()
    private let duplicateDetector = DuplicateDetector()
    private let cleanupEngine = CleanupEngine()
    private let quarantineManager = QuarantineManager()
    private let projectPurgeScanner = ProjectPurgeScanner.shared
    private let nativeToolPruner = NativeToolPruner.shared
    private let snapshotManager = SnapshotManager.shared
    private var currentScanTask: Task<Void, Never>?
    private var currentDuplicateTask: Task<Void, Never>?
    private var currentProjectScanTask: Task<Void, Never>?

    public init() {
        refreshVolumeMetrics()
        refreshHistory()
        refreshTelemetry()
        refreshFolderAccess()
        refreshTools()
        refreshSnapshots()
    }

    public func refreshFolderAccess() {
        FolderAccessManager.shared.refreshAllStatuses()
        self.authorizedFolders = FolderAccessManager.shared.getRecords()
    }

    public func authorizeFolder(url: URL) throws {
        try FolderAccessManager.shared.grantAccess(for: url)
        self.refreshFolderAccess()
    }

    public func revokeFolderAccess(id: UUID) {
        FolderAccessManager.shared.revokeAccess(id: id)
        self.refreshFolderAccess()
    }

    @MainActor
    public func scanAuthorizedFolder(record: AuthorizedFolderRecord) {
        do {
            let (resolvedURL, _) = try FolderAccessManager.shared.resolveAccess(for: record)
            self.customScanRootURL = resolvedURL
            self.scanTargetDescription = record.displayName
            self.refreshVolumeMetrics(for: resolvedURL)
            self.refreshFolderAccess()
            self.startScan(customRoots: [resolvedURL], targetDescription: record.displayName)
        } catch {
            self.refreshFolderAccess()
        }
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

    public func refreshTelemetry() {
        self.currentProcessTelemetry = SystemTelemetry.captureCurrentProcessTelemetry()
        self.recentBenchmarkRecords = BenchmarkManager.shared.getRecentRecords()
        self.lastControlledBenchmark = BenchmarkManager.shared.getLastBenchmarkComparison()
    }

    // MARK: - Safe Scan Execution
    @MainActor
    public func selectCustomFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Authorize & Scan"
        panel.message = "Choose a directory on this Mac to authorize and scan with Squirrel. Squirrel saves this authorization securely so you are never prompted again."
        if panel.runModal() == .OK, let selectedURL = panel.url {
            // Persist authorization grant
            try? self.authorizeFolder(url: selectedURL)
            self.customScanRootURL = selectedURL
            self.scanTargetDescription = selectedURL.path
            self.refreshVolumeMetrics(for: selectedURL)
            self.startScan(customRoots: [selectedURL], targetDescription: selectedURL.path)
        }
    }

    @MainActor
    public func scanHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Persist authorization grant for home
        try? self.authorizeFolder(url: home)
        self.customScanRootURL = home
        self.scanTargetDescription = "User Home (~/)"
        self.refreshVolumeMetrics(for: home)
        self.startScan(customRoots: [home], targetDescription: "User Home (~/)")
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
            var defaultRoots: [URL] = [
                home.appendingPathComponent("Downloads", isDirectory: true),
                home.appendingPathComponent("Library/Caches", isDirectory: true),
                home.appendingPathComponent("Library/Logs", isDirectory: true),
                home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
                home.appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true),
                home.appendingPathComponent(".npm", isDirectory: true),
                home.appendingPathComponent(".cache", isDirectory: true),
                home.appendingPathComponent(".cargo/registry/cache", isDirectory: true),
                home.appendingPathComponent(".gradle/caches", isDirectory: true),
                home.appendingPathComponent(".Trash", isDirectory: true)
            ]
            // Add user developer workspaces if present
            for dirName in ["Code", "Projects", "Developer", "Workspace", "Repos", "dev"] {
                let candidate = home.appendingPathComponent(dirName, isDirectory: true)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    defaultRoots.append(candidate)
                }
            }

            // Also add all top-level project folders in $HOME (e.g. attendly, Geniusphere)
            let systemBases: Set<String> = [
                "Library", "Applications", "Movies", "Music", "Pictures", "Public", "Desktop", "System", "Documents"
            ]
            if let homeContents = try? fileManager.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for itemURL in homeContents {
                    let base = itemURL.lastPathComponent
                    guard !systemBases.contains(base), !defaultRoots.contains(itemURL) else { continue }
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue {
                        defaultRoots.append(itemURL)
                    }
                }
            }

            roots = defaultRoots
            description = "Comprehensive Sweep (Downloads, Caches, Developer, Repos, Trash)"
        }

        self.scanTargetDescription = description

        self.currentScanTask?.cancel()
        self.currentScanTask = Task {
            let startFootprint = SystemTelemetry.captureCurrentProcessTelemetry().physicalFootprint
            let validRoots = roots.filter { fileManager.fileExists(atPath: $0.path) && fileManager.isReadableFile(atPath: $0.path) }

            // Execute scan wrapped in security-scoped resource access scopes
            let result: ScanResult
            if let accessResult = try? await FolderAccessManager.shared.withAccess(to: validRoots, operation: { accessibleRoots in
                return await self.scanner.scan(roots: accessibleRoots) { progress in
                    Task { @MainActor in
                        self.scanProgress = progress
                    }
                }
            }) {
                result = accessResult
            } else {
                result = await self.scanner.scan(roots: validRoots) { progress in
                    Task { @MainActor in
                        self.scanProgress = progress
                    }
                }
            }

            // Check cancellation before intensive post-processing
            if Task.isCancelled || !result.completedNormally {
                await MainActor.run {
                    self.scanStatus = .cancelled
                    self.scannedItems = []
                    self.findings = []
                    self.safeFindings = []
                    self.reviewFindings = []
                    self.keepFindings = []
                    self.safeCount = 0
                    self.reviewCount = 0
                    self.keepCount = 0
                    self.duplicateGroups = []
                    self.inaccessibleLocations = []
                    let emptyTreemap = TreemapNode(name: "Storage", path: "/", size: 0, category: .otherUserData, isDirectory: true)
                    self.treemapRoot = emptyTreemap
                    self.activeTreemapRoot = emptyTreemap
                }
                return
            }

            // Classify findings and partition in background
            var computedFindings: [Finding] = []
            var safeList: [Finding] = []
            var reviewList: [Finding] = []
            var keepList: [Finding] = []

            let rules = ClassificationRules.shared
            let inaccessiblePaths = Set(result.inaccessibleLocations.map { $0.path })
            for item in result.items {
                if Task.isCancelled { return }
                if let finding = rules.classify(item: item, inaccessiblePaths: inaccessiblePaths) {
                    computedFindings.append(finding)
                    switch finding.eligibility {
                    case .safeToClean: safeList.append(finding)
                    case .reviewRecommended: reviewList.append(finding)
                    case .keep: keepList.append(finding)
                    }
                }
            }

            if Task.isCancelled { return }

            // Build Treemap Hierarchy
            let rootTreemap = TreemapEngine.buildHierarchy(from: result.items)

            if Task.isCancelled { return }

            // Sort all collections once in background by allocated size
            let finalFindings = computedFindings.sorted { $0.allocatedSize > $1.allocatedSize }
            let finalSafe = safeList.sorted { $0.allocatedSize > $1.allocatedSize }
            let finalReview = reviewList.sorted { $0.allocatedSize > $1.allocatedSize }
            let finalKeep = keepList.sorted { $0.allocatedSize > $1.allocatedSize }

            let peakFootprint = SystemTelemetry.captureCurrentProcessTelemetry().physicalFootprint
            let perfRecord = ScanPerformanceRecord(
                targetDescription: description,
                itemCount: result.items.count,
                totalLogicalBytes: result.totalLogicalBytes,
                durationSeconds: result.scanDurationSeconds,
                startPhysicalFootprint: startFootprint,
                peakPhysicalFootprint: peakFootprint,
                completedNormally: result.completedNormally
            )
            BenchmarkManager.shared.recordScan(perfRecord)

            await MainActor.run {
                if result.completedNormally && !Task.isCancelled {
                    self.scannedItems = result.items
                    self.findings = finalFindings
                    self.safeFindings = finalSafe
                    self.reviewFindings = finalReview
                    self.keepFindings = finalKeep
                    self.safeCount = finalSafe.count
                    self.reviewCount = finalReview.count
                    self.keepCount = finalKeep.count
                    self.inaccessibleLocations = result.inaccessibleLocations
                    self.treemapRoot = rootTreemap
                    self.activeTreemapRoot = rootTreemap
                    self.scanStatus = .completed
                    self.lastScanDate = Date()
                } else {
                    self.scanStatus = .cancelled
                    self.scannedItems = []
                    self.findings = []
                    self.safeFindings = []
                    self.reviewFindings = []
                    self.keepFindings = []
                    self.safeCount = 0
                    self.reviewCount = 0
                    self.keepCount = 0
                    self.duplicateGroups = []
                    self.inaccessibleLocations = []
                    let emptyTreemap = TreemapNode(name: "Storage", path: "/", size: 0, category: .otherUserData, isDirectory: true)
                    self.treemapRoot = emptyTreemap
                    self.activeTreemapRoot = emptyTreemap
                    // Incomplete scan: lastScanDate is NOT updated
                }
                self.lastScanDuration = result.scanDurationSeconds
                self.lastScanPerformance = perfRecord
                self.refreshVolumeMetrics()
                self.refreshTelemetry()
            }
        }
    }

    public func cancelScan() {
        currentScanTask?.cancel()
        currentScanTask = nil
        currentDuplicateTask?.cancel()
        currentDuplicateTask = nil
        Task {
            await scanner.cancel()
            await duplicateDetector.cancel()
            await MainActor.run {
                self.scanStatus = .cancelled
                self.isScanningDuplicates = false
            }
        }
    }

    /// On-demand content duplicate scanner matching modular macOS tools (like Mole).
    /// Scans only when user triggers it or navigates to the Duplicates view.
    public func startDuplicateScan() {
        guard !isScanningDuplicates else { return }
        guard !scannedItems.isEmpty else {
            // If no scan has been run yet, start a scan first
            startScan()
            return
        }

        isScanningDuplicates = true
        duplicateScanProgressText = "Analyzing candidate files for duplicates..."
        selectedDuplicatePaths.removeAll()

        currentDuplicateTask?.cancel()
        currentDuplicateTask = Task {
            let items = self.scannedItems
            let duplicates = await duplicateDetector.findDuplicates(items: items) { msg in
                Task { @MainActor in
                    self.duplicateScanProgressText = msg
                }
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.duplicateGroups = duplicates
                }
                self.isScanningDuplicates = false
                self.duplicateScanProgressText = ""
            }
        }
    }

    // MARK: - Cleanup Execution
    public func executeSafeBatch() {
        guard !isCleaning else { return }
        isCleaning = true
        cleanupProgress = CleanupProgress(completedCount: 0, totalCount: 1, currentItemName: "Validating safe items...")

        let currentFindings = self.findings
        let duration = self.lastScanDuration
        let targetURL = self.customScanRootURL ?? URL(fileURLWithPath: "/")

        Task {
            let summary = await cleanupEngine.executeSafeBatch(
                findings: currentFindings,
                scanDuration: duration,
                targetVolumeURL: targetURL
            ) { prog in
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
                self.refreshTelemetry()

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
        let allCount = findings.count
        let duration = self.lastScanDuration
        let targetURL = self.customScanRootURL ?? URL(fileURLWithPath: "/")

        Task {
            let summary = await cleanupEngine.executeSelected(
                findings: selected,
                allDiscoveredCount: allCount,
                scanDuration: duration,
                targetVolumeURL: targetURL
            ) { prog in
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
                self.refreshTelemetry()

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
        var totalCopies = 0
        for group in duplicateGroups {
            totalCopies += group.files.count
            for member in group.files {
                if selectedDuplicatePaths.contains(member.path) {
                    membersToDelete.append(member)
                }
            }
        }

        let duration = self.lastScanDuration
        let targetURL = self.customScanRootURL ?? URL(fileURLWithPath: "/")

        Task {
            let summary = await cleanupEngine.deleteDuplicateCopies(
                members: membersToDelete,
                totalCandidateCopiesCount: totalCopies,
                scanDuration: duration,
                targetVolumeURL: targetURL
            ) { prog in
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
                self.refreshTelemetry()

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

    // MARK: - Controlled Diagnostic Benchmark Runner
    public func runControlledBenchmark() async -> BenchmarkComparison {
        let comparison = await BenchmarkManager.shared.runControlledBenchmark()
        await MainActor.run {
            self.lastControlledBenchmark = comparison
            self.refreshTelemetry()
        }
        return comparison
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

    // MARK: - Mole Integration: Project Purge, Native Tools & Snapshots

    public func scanProjects() {
        Task { @MainActor in
            guard !self.isScanningProjects else { return }
            self.isScanningProjects = true
            self.projectScanProgressText = "Discovering project workspaces..."

            self.currentProjectScanTask?.cancel()
            self.currentProjectScanTask = Task {
                let roots = ProjectPurgeScanner.defaultProjectRoots()
                let projects = await self.projectPurgeScanner.scanProjects(roots: roots) { prog in
                    Task { @MainActor in
                        self.projectScanProgressText = prog
                    }
                }

                await MainActor.run {
                    if !Task.isCancelled {
                        self.discoveredProjects = projects
                    }
                    self.isScanningProjects = false
                    self.projectScanProgressText = ""
                }
            }
        }
    }

    public func purgeProject(candidate: ProjectCandidate) {
        Task {
            for artifact in candidate.artifacts {
                let url = URL(fileURLWithPath: artifact.path)
                var resultingURL: NSURL?
                _ = try? FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            }
            await MainActor.run {
                self.discoveredProjects.removeAll { $0.projectPath == candidate.projectPath }
                self.refreshVolumeMetrics()
            }
        }
    }

    public func purgeSelectedProjects(paths: Set<String>) async {
        let targets = discoveredProjects.filter { paths.contains($0.projectPath) }
        for proj in targets {
            for artifact in proj.artifacts {
                let url = URL(fileURLWithPath: artifact.path)
                var resultingURL: NSURL?
                _ = try? FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            }
        }
        await MainActor.run {
            self.discoveredProjects.removeAll { paths.contains($0.projectPath) }
            self.refreshVolumeMetrics()
        }
    }

    public func refreshTools() {
        Task { @MainActor in
            guard !self.isRefreshingTools else { return }
            self.isRefreshingTools = true
            let tools = await self.nativeToolPruner.discoverTools()
            self.supportedTools = tools
            self.isRefreshingTools = false
        }
    }

    public func pruneTool(tool: SupportedTool) async -> ToolPruneResult {
        let result = await nativeToolPruner.pruneTool(tool)
        await MainActor.run {
            self.refreshTools()
            self.refreshVolumeMetrics()
        }
        return result
    }

    public func pruneAllInstalledTools() async {
        let installed = supportedTools.filter { $0.isInstalled }
        for tool in installed {
            _ = await nativeToolPruner.pruneTool(tool)
        }
        await MainActor.run {
            self.refreshTools()
            self.refreshVolumeMetrics()
        }
    }

    public func refreshSnapshots() {
        Task { @MainActor in
            guard !self.isRefreshingSnapshots else { return }
            self.isRefreshingSnapshots = true
            let snapshots = await self.snapshotManager.listLocalSnapshots()
            self.localSnapshots = snapshots
            self.isRefreshingSnapshots = false
        }
    }

    public func deleteSnapshot(snapshot: LocalSnapshot) async {
        _ = await snapshotManager.deleteSnapshot(snapshot)
        await MainActor.run {
            self.refreshSnapshots()
            self.refreshVolumeMetrics()
        }
    }

    public func deleteAllSnapshots() async {
        for snap in localSnapshots {
            _ = await snapshotManager.deleteSnapshot(snap)
        }
        await MainActor.run {
            self.refreshSnapshots()
            self.refreshVolumeMetrics()
        }
    }

    // MARK: - Ready to Clean (Mole Model Unified Hub)

    public func performHubAudit() {
        Task { @MainActor in
            guard !self.isAuditingHub else { return }
            self.isAuditingHub = true
            self.hubAuditProgress = "Targeted audit across high-yield categories..."

            let summary = await TargetedCleanEngine.shared.performTargetedAudit { prog in
                Task { @MainActor in
                    self.hubAuditProgress = prog
                }
            }

            self.readyToCleanSummary = summary
            self.isAuditingHub = false
            self.hubAuditProgress = ""
            self.refreshVolumeMetrics()
        }
    }

    public func cleanSelectedHubItems() async {
        let initialSpace = VolumeSpace.querySystemVolume()
        let selected = readyToCleanSummary.items.filter { $0.isSelected }
        var cleanedCount = 0
        var skippedCount = 0
        var skippedReasons: [String] = []
        let safetyGuard = ProcessSafetyGuard.shared

        for item in selected {
            // Safety guard: protect running applications/CLI daemons
            let runningCheck = safetyGuard.isApplicationRunning(forPath: item.path)
            if runningCheck.isRunning, let appName = runningCheck.appName {
                skippedCount += 1
                skippedReasons.append("\(item.name) was skipped because \(appName) is actively running.")
                continue
            }

            if item.category == .systemData && item.name.starts(with: "APFS Snapshot:") {
                let success = await snapshotManager.deleteSnapshot(LocalSnapshot(name: item.name, dateString: item.path, isTimeMachine: true))
                if success {
                    cleanedCount += 1
                }
            } else {
                let url = URL(fileURLWithPath: item.path)
                var resultingURL: NSURL?
                if (try? FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)) != nil {
                    cleanedCount += 1
                }
            }
        }

        let postSpace = VolumeSpace.querySystemVolume()
        let verifiedReclaimed = max(0, postSpace.availableCapacity - initialSpace.availableCapacity)
        let feedback = CleanResultFeedback(
            reclaimedBytes: verifiedReclaimed > 0 ? verifiedReclaimed : selected.reduce(0) { $0 + $1.sizeBytes },
            itemsCleanedCount: cleanedCount,
            itemsSkippedCount: skippedCount,
            skippedReasons: skippedReasons
        )

        await MainActor.run {
            self.lastCleanResult = feedback
            self.showCleanResultBanner = true
            self.performHubAudit()
            self.refreshVolumeMetrics()
        }
    }

    public func toggleHubCategory(category: CleanGroupCategory, isSelected: Bool) {
        for idx in readyToCleanSummary.items.indices {
            if readyToCleanSummary.items[idx].category == category {
                readyToCleanSummary.items[idx].isSelected = isSelected
            }
        }
    }

    public func selectAllHubItems(selected: Bool) {
        for idx in readyToCleanSummary.items.indices {
            readyToCleanSummary.items[idx].isSelected = selected
        }
    }

    public func selectRecommendedHubItems() {
        for idx in readyToCleanSummary.items.indices {
            let cat = readyToCleanSummary.items[idx].category
            readyToCleanSummary.items[idx].isSelected = (cat != .appLeftovers)
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
