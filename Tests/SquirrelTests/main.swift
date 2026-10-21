import Foundation
import SquirrelCore

var passedCount = 0
var failedCount = 0

@MainActor
func assertTest(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ PASS: \(message)")
        passedCount += 1
    } else {
        print("  ✗ FAIL: \(message)")
        failedCount += 1
    }
}

@MainActor
func runAsyncTest(_ name: String, block: @MainActor () async throws -> Void) async {
    print("\nRunning [\(name)]...")
    do {
        try await block()
    } catch {
        print("  ✗ EXCEPTION in \(name): \(error)")
        failedCount += 1
    }
}

// Setup isolated temp fixture directory
let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SquirrelTestSuite_\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: tempDir)
}

print("==================================================")
print("  Squirrel Automated Test Suite Runner")
print("  'A little more room for your Mac.'")
print("==================================================")

// Test 1: Volume Storage Query
await runAsyncTest("Volume Metrics & Accounting") {
    let vol = VolumeSpace.querySystemVolume()
    assertTest(vol.totalCapacity > 0, "System volume total capacity is positive (\(ByteCountFormatter.string(fromByteCount: vol.totalCapacity, countStyle: .file)))")
    assertTest(vol.availableCapacity > 0, "Available capacity is positive (\(ByteCountFormatter.string(fromByteCount: vol.availableCapacity, countStyle: .file)))")
    assertTest(vol.usedSpace > 0, "Used space is positive (\(ByteCountFormatter.string(fromByteCount: vol.usedSpace, countStyle: .file)))")
    assertTest(vol.totalCapacity >= vol.availableCapacity, "Total capacity >= available capacity")
}

// Test 2: Scanner Nested Traversal & Accurate Byte Counting
await runAsyncTest("Scanner Nested Traversal & Metrics") {
    let testSub = tempDir.appendingPathComponent("SubFolder", isDirectory: true)
    try FileManager.default.createDirectory(at: testSub, withIntermediateDirectories: true)

    let file1 = testSub.appendingPathComponent("docA.txt")
    let data1 = Data(repeating: 0x41, count: 2048) // 2048 bytes
    try data1.write(to: file1)

    let file2 = tempDir.appendingPathComponent("docB.log")
    let data2 = Data(repeating: 0x42, count: 4096) // 4096 bytes
    try data2.write(to: file2)

    let scanner = FilesystemScanner()
    let result = await scanner.scan(roots: [tempDir])

    assertTest(result.completedNormally, "Scanner completed without error")
    assertTest(result.items.count == 3, "Scanner found exactly 3 items (1 subfolder + 2 files)")
    assertTest(result.totalLogicalBytes == 6144, "Scanner accurately accounted for 6144 logical bytes")
}

// Test 3: Symlink Cycle and Traversal Protection
await runAsyncTest("Scanner Symlink & Cycle Protection") {
    let cycleDir = tempDir.appendingPathComponent("CycleFolder", isDirectory: true)
    try FileManager.default.createDirectory(at: cycleDir, withIntermediateDirectories: true)

    let symlink = cycleDir.appendingPathComponent("linkToParent")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: tempDir)

    let scanner = FilesystemScanner()
    let result = await scanner.scan(roots: [tempDir])

    assertTest(result.completedNormally, "Scanner safely handled symlink without getting trapped in cycle")
}

// Test 4: SafetyValidator Pre-Flight TOCTOU & Symlink Rejection
await runAsyncTest("SafetyValidator Pre-Flight Defenses") {
    let regularFile = tempDir.appendingPathComponent("safeFile.txt")
    try "test content".write(to: regularFile, atomically: true, encoding: .utf8)

    let passOutcome = SafetyValidator.validate(path: regularFile.path)
    if case .passed(let meta) = passOutcome {
        assertTest(meta.size > 0 && !meta.isDirectory, "Regular file safely passed pre-flight validation")
    } else {
        assertTest(false, "Regular file should pass validation")
    }

    // Symlink creation & check
    let symlink = tempDir.appendingPathComponent("symlinkAttack")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: regularFile)

    let symOutcome = SafetyValidator.validate(path: symlink.path)
    if case .failed(let reason) = symOutcome {
        assertTest(reason.contains("symbolic link"), "SafetyValidator correctly rejected symbolic link: \(reason)")
    } else {
        assertTest(false, "SafetyValidator should have rejected symlink")
    }

    // Root paths check
    let rootOutcome = SafetyValidator.validate(path: "/")
    if case .failed = rootOutcome {
        assertTest(true, "SafetyValidator correctly rejected system root '/'")
    } else {
        assertTest(false, "SafetyValidator must reject root path")
    }
}

// Test 5: Exact Content-Based Duplicate Detection
await runAsyncTest("Exact Duplicate Content-Based Detection") {
    let content1 = "Standard test block for exact duplicate content hashing.".data(using: .utf8)!
    let dupA = tempDir.appendingPathComponent("duplicate_1.bin")
    let dupB = tempDir.appendingPathComponent("duplicate_2_copy.bin")
    let nonDup = tempDir.appendingPathComponent("non_duplicate_same_length.bin")

    try content1.write(to: dupA)
    try content1.write(to: dupB)

    var content2 = content1
    content2[0] = 0xFF // Mutate first byte so size is identical but content differs
    try content2.write(to: nonDup)

    let scanner = FilesystemScanner()
    let scanResult = await scanner.scan(roots: [tempDir])

    let detector = DuplicateDetector()
    let duplicates = await detector.findDuplicates(items: scanResult.items)

    assertTest(duplicates.count == 1, "Duplicate detector found exactly 1 duplicate group")
    if let group = duplicates.first {
        assertTest(group.files.count == 2, "Duplicate group has exactly 2 members")
        assertTest(group.potentialReclaimableBytes == Int64(content1.count), "Potential savings accurately calculated without double-counting: \(group.potentialReclaimableBytes) bytes")
        let canonA = dupA.resolvingSymlinksInPath().path
        let canonB = dupB.resolvingSymlinksInPath().path
        let groupCanonPaths = group.files.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path }
        assertTest(groupCanonPaths.contains(canonA), "Contains copy A")
        assertTest(groupCanonPaths.contains(canonB), "Contains copy B")
        assertTest(!groupCanonPaths.contains(nonDup.resolvingSymlinksInPath().path), "Does NOT contain different file with same size")
        assertTest(group.files.contains(where: { $0.isRecommendedToKeep }), "Has a designated recommended copy to keep")
    }
}

// Test 6: Managed Quarantine & Collision-Safe Restoration
await runAsyncTest("Quarantine & Collision-Safe Restoration") {
    let quarantineBase = tempDir.appendingPathComponent("QuarantineBase", isDirectory: true)
    let quarantineManager = QuarantineManager(customBaseDir: quarantineBase)

    let testFile = tempDir.appendingPathComponent("vital_cache.dat")
    let testPayload = "Important cache payload for recovery verification".data(using: .utf8)!
    try testPayload.write(to: testFile)

    // Move to quarantine
    let record = try await quarantineManager.quarantineFile(at: testFile.path)
    assertTest(!FileManager.default.fileExists(atPath: testFile.path), "Original file removed after quarantine move")
    assertTest(record.fileSize == Int64(testPayload.count), "Quarantine record captures exact byte size")

    // Recreate original file at the same path to simulate a collision
    try "New conflicting file at same path".write(to: testFile, atomically: true, encoding: .utf8)

    // Restore from quarantine
    let restoredPath = try await quarantineManager.restoreFile(recordId: record.id)
    assertTest(FileManager.default.fileExists(atPath: restoredPath), "Quarantined file successfully restored")
    assertTest(restoredPath != testFile.path, "Collision safe naming applied (restored to \(URL(fileURLWithPath: restoredPath).lastPathComponent))")

    let restoredData = try Data(contentsOf: URL(fileURLWithPath: restoredPath))
    assertTest(restoredData == testPayload, "Restored content matches original payload exactly")
}

// Test 7: Classification Safety Rules
await runAsyncTest("Classification Safety Rules") {
    let rules = ClassificationRules.shared

    // Developer artifact rule
    let devItem = StorageItem(
        url: URL(fileURLWithPath: "/Users/developer/project/DerivedData/Build/Products"),
        path: "/Users/developer/project/DerivedData/Build/Products",
        name: "Products",
        logicalSize: 300 * 1024 * 1024,
        allocatedSize: 300 * 1024 * 1024,
        isDirectory: true,
        isSymbolicLink: false,
        deviceId: 1,
        inode: 501,
        modificationDate: Date(),
        isReadable: true,
        isWritable: true
    )
    let devFinding = rules.classify(item: devItem)
    assertTest(devFinding?.eligibility == .keep, "Developer artifact classified as Keep / Not Recommended")
    assertTest(devFinding?.ruleId == "RULE-DEV-EXCLUDE", "Correct rule ID applied: RULE-DEV-EXCLUDE")

    // Old log file rule
    let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
    let logItem = StorageItem(
        url: URL(fileURLWithPath: "/Users/developer/Library/Logs/diagnostic.log"),
        path: "/Users/developer/Library/Logs/diagnostic.log",
        name: "diagnostic.log",
        logicalSize: 2 * 1024 * 1024,
        allocatedSize: 2 * 1024 * 1024,
        isDirectory: false,
        isSymbolicLink: false,
        deviceId: 1,
        inode: 502,
        modificationDate: oldDate,
        isReadable: true,
        isWritable: true
    )
    let logFinding = rules.classify(item: logItem)
    assertTest(logFinding?.eligibility == .safeToClean, "Old inactive log classified as Safe to Clean")
    assertTest(logFinding?.ruleId == "RULE-LOGS-01", "Correct rule ID applied: RULE-LOGS-01")

    // Installer rule (must NOT be safe to clean automatically)
    let installerItem = StorageItem(
        url: URL(fileURLWithPath: "/Users/developer/Downloads/AppInstaller.dmg"),
        path: "/Users/developer/Downloads/AppInstaller.dmg",
        name: "AppInstaller.dmg",
        logicalSize: 150 * 1024 * 1024,
        allocatedSize: 150 * 1024 * 1024,
        isDirectory: false,
        isSymbolicLink: false,
        deviceId: 1,
        inode: 503,
        modificationDate: Date(),
        isReadable: true,
        isWritable: true
    )
    let installerFinding = rules.classify(item: installerItem)
    assertTest(installerFinding?.eligibility == .reviewRecommended, "Installer requires explicit Review Recommended")
}

// Test 8: Squarified Treemap Layout Engine
await runAsyncTest("Squarified Treemap Layout Engine") {
    let item1 = StorageItem(
        url: URL(fileURLWithPath: "/Users/test/Downloads/installer.dmg"),
        path: "/Users/test/Downloads/installer.dmg",
        name: "installer.dmg",
        logicalSize: 500 * 1024 * 1024,
        allocatedSize: 500 * 1024 * 1024,
        isDirectory: false,
        isSymbolicLink: false,
        deviceId: 1,
        inode: 601,
        modificationDate: Date(),
        isReadable: true,
        isWritable: true
    )
    let item2 = StorageItem(
        url: URL(fileURLWithPath: "/Users/test/Library/Caches/cache.bin"),
        path: "/Users/test/Library/Caches/cache.bin",
        name: "cache.bin",
        logicalSize: 100 * 1024 * 1024,
        allocatedSize: 100 * 1024 * 1024,
        isDirectory: false,
        isSymbolicLink: false,
        deviceId: 1,
        inode: 602,
        modificationDate: Date(),
        isReadable: true,
        isWritable: true
    )

    var root = TreemapEngine.buildHierarchy(from: [item1, item2])
    assertTest(!root.children.isEmpty, "Treemap hierarchy contains category nodes")

    let canvasBounds = CGRect(x: 0, y: 0, width: 900, height: 600)
    TreemapEngine.layoutSquarified(node: &root, bounds: canvasBounds)

    for child in root.children {
        assertTest(child.rect.width > 0 && child.rect.height > 0, "Treemap tile has positive dimensions (\(child.name): \(child.rect))")
        assertTest(child.rect.maxX <= canvasBounds.width + 1.0, "Tile fits within canvas width")
        assertTest(child.rect.maxY <= canvasBounds.height + 1.0, "Tile fits within canvas height")
    }
}

// Test 9: Hard-Link Inode Deduplication in Aggregate Accounting
await runAsyncTest("Hard-Link Inode Deduplication") {
    let hlDir = tempDir.appendingPathComponent("HardLinkTestDir", isDirectory: true)
    try FileManager.default.createDirectory(at: hlDir, withIntermediateDirectories: true)

    let originalFile = hlDir.appendingPathComponent("original.bin")
    let hardlinkFile = hlDir.appendingPathComponent("link_to_original.bin")

    let payload = Data(repeating: 0x7E, count: 8192) // 8192 bytes
    try payload.write(to: originalFile)

    // Create POSIX hard link (link original to hardlinkFile)
    let linkResult = link(originalFile.path, hardlinkFile.path)
    assertTest(linkResult == 0, "POSIX hard link created successfully between two directory entries")

    let scanner = FilesystemScanner()
    let result = await scanner.scan(roots: [hlDir])

    assertTest(result.completedNormally, "Hard link directory scan completed normally")
    assertTest(result.items.count == 2, "Scanner identified both directory entries (count = 2)")
    assertTest(result.totalLogicalBytes == 8192, "Hard links pointing to identical (dev, ino) are deduplicated in aggregate totals (expected 8192 bytes, got \(result.totalLogicalBytes))")
}

// Test 10: Empty Directory Honest Accounting (Zero Fabrication)
await runAsyncTest("Empty Directory Honest Accounting") {
    let emptyDir = tempDir.appendingPathComponent("EmptyTestDir", isDirectory: true)
    try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

    let scanner = FilesystemScanner()
    let result = await scanner.scan(roots: [emptyDir])

    assertTest(result.completedNormally, "Empty directory scan completed normally")
    assertTest(result.items.isEmpty, "Empty directory yields 0 items (no mock items injected)")
    assertTest(result.totalLogicalBytes == 0, "Empty directory yields exactly 0 logical bytes")
    assertTest(result.totalAllocatedBytes == 0, "Empty directory yields exactly 0 allocated bytes")
    assertTest(result.inaccessibleLocations.isEmpty, "No inaccessible locations in accessible empty dir")
}

// Test 11: User-Selected Custom Directory Traversal
await runAsyncTest("User-Selected Custom Directory Traversal") {
    let customDir = tempDir.appendingPathComponent("UserSelectedFolder", isDirectory: true)
    try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)

    let fileX = customDir.appendingPathComponent("custom_report.pdf")
    let fileY = customDir.appendingPathComponent("custom_archive.pkg")

    try "PDF content".data(using: .utf8)!.write(to: fileX)
    try "PKG package".data(using: .utf8)!.write(to: fileY)

    let scanner = FilesystemScanner()
    let result = await scanner.scan(roots: [customDir])

    assertTest(result.completedNormally, "Custom directory scan completed normally")
    assertTest(result.items.count == 2, "Found exactly 2 items in custom folder")
    assertTest(result.categoryTotals[.downloadsAndInstallers] ?? 0 > 0, "Installer file properly categorized")
}

// Test 12: Inaccessible Path Handling
await runAsyncTest("Inaccessible & Non-Existent Path Handling") {
    let nonExistentURL = URL(fileURLWithPath: "/non_existent_squirrel_path_\(UUID().uuidString)")

    let scanner = FilesystemScanner()
    let result = await scanner.scan(roots: [nonExistentURL])

    assertTest(!result.inaccessibleLocations.isEmpty, "Inaccessible/non-existent location recorded")
    assertTest(result.inaccessibleLocations.first?.path == nonExistentURL.path, "Recorded path matches attempted query path")
    assertTest(result.totalLogicalBytes == 0, "No phantom bytes added for inaccessible paths")
}

// Test 13: Protected TCC / Inaccessible Path Exclusion
await runAsyncTest("Protected TCC & Inaccessible Classification Protection") {
    let protectedPath = "/Users/test/Library/Caches/FamilyCircle"
    let protectedItem = StorageItem(
        url: URL(fileURLWithPath: protectedPath),
        path: protectedPath,
        name: "FamilyCircle",
        logicalSize: 1048576,
        allocatedSize: 1048576,
        isDirectory: true,
        isSymbolicLink: false,
        deviceId: 1,
        inode: 123456,
        modificationDate: Date().addingTimeInterval(-86400 * 30),
        isReadable: false,
        isWritable: false
    )

    let rules = ClassificationRules.shared
    let inaccessiblePaths: Set<String> = [protectedPath]
    let finding = rules.classify(item: protectedItem, inaccessiblePaths: inaccessiblePaths)

    assertTest(finding != nil, "Finding produced for protected item")
    assertTest(finding?.eligibility == .keep, "Protected item is classified as Keep / Excluded")
    assertTest(finding?.ruleId == "RULE-TCC-RESTRICTED", "RULE-TCC-RESTRICTED applied to protected item")
    assertTest(finding?.estimatedReclaimableBytes == 0, "Reclaimable bytes is 0 for protected item")
}

// Test 14: Hierarchical Cascading Deletion & Parent Pruning
await runAsyncTest("Hierarchical Container Cascading Deletion") {
    let containerDir = tempDir.appendingPathComponent("CascadeTest_\(UUID().uuidString)", isDirectory: true)
    let childSubdir = containerDir.appendingPathComponent("NestedSubdir", isDirectory: true)
    let childFile = childSubdir.appendingPathComponent("leaf.log")

    try FileManager.default.createDirectory(at: childSubdir, withIntermediateDirectories: true)
    try "cascade payload".data(using: .utf8)!.write(to: childFile)

    let parentFinding = Finding(
        category: .systemLogs,
        title: "Parent Container",
        path: containerDir.path,
        logicalSize: 2048,
        allocatedSize: 4096,
        modificationDate: Date(),
        ruleId: "RULE-LOGS-01",
        ruleDescription: "Parent container test",
        evidence: [],
        eligibility: .safeToClean,
        riskLevel: .low,
        recoveryMethod: .macOSTrash,
        estimatedReclaimableBytes: 4096,
        consequencesExplanation: "Testing parent container deletion"
    )

    let childFinding = Finding(
        category: .systemLogs,
        title: "Child Log",
        path: childFile.path,
        logicalSize: 1024,
        allocatedSize: 4096,
        modificationDate: Date(),
        ruleId: "RULE-LOGS-01",
        ruleDescription: "Child leaf test",
        evidence: [],
        eligibility: .safeToClean,
        riskLevel: .low,
        recoveryMethod: .macOSTrash,
        estimatedReclaimableBytes: 4096,
        consequencesExplanation: "Testing child file deletion"
    )

    let engine = CleanupEngine()
    let summary = await engine.executeSelected(findings: [parentFinding, childFinding])

    assertTest(summary.itemsSucceededCount == 2, "Both parent and child marked succeeded (child counted with parent)")
    assertTest(summary.itemsFailedCount == 0, "Zero failures (no errno: 2 on child leaf)")
}

// Test 15: Progress Pacing & Performance Pacing
await runAsyncTest("Scanner Progress Pacing & Throttle Check") {
    let pacingDir = tempDir.appendingPathComponent("PacingTest_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: pacingDir, withIntermediateDirectories: true)

    // Create 100 small files to test traversal throttling
    for i in 1...100 {
        let f = pacingDir.appendingPathComponent("file_\(i).txt")
        try "pacing test".data(using: .utf8)!.write(to: f)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var val = 0
        func increment() {
            lock.lock()
            val += 1
            lock.unlock()
        }
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return val
        }
    }
    let counter = Counter()
    let scanner = FilesystemScanner()
    let result = await scanner.scan(roots: [pacingDir]) { _ in
        counter.increment()
    }

    assertTest(result.completedNormally, "Pacing scan completed normally")
    assertTest(result.items.count == 100, "All 100 items discovered")
    assertTest(counter.count <= 20, "Progress handler was properly throttled (called \(counter.count) times for 100 fast files)")
}

// Test 16: Apple Storage Parity & APFS Container Audit
await runAsyncTest("Apple Storage Parity & APFS Container Audit") {
    let report = await AppleStorageAuditor.auditSystemStorage()

    assertTest(report.totalContainerCapacity > 0, "Total APFS container capacity is positive (\(Double(report.totalContainerCapacity) / 1e9) GB)")
    assertTest(report.appleAvailableStorage > 0, "Apple System Settings available storage is positive (\(Double(report.appleAvailableStorage) / 1e9) GB)")
    assertTest(report.appleUsedStorage > 0, "Apple System Settings used storage is positive (\(Double(report.appleUsedStorage) / 1e9) GB)")
    assertTest(
        report.totalContainerCapacity == report.appleAvailableStorage + report.appleUsedStorage,
        "Total container equals Apple available plus Apple used (\(report.totalContainerCapacity) == \(report.appleAvailableStorage + report.appleUsedStorage))"
    )
    assertTest(report.rawPhysicalAvailableStorage <= report.appleAvailableStorage, "Raw unallocated physical storage <= Apple available storage (accounts for APFS purgeable)")
    assertTest(report.categories.count >= 5, "Audit includes all 5 primary Apple storage categories")

    let catNames = Set(report.categories.map { $0.categoryName })
    assertTest(catNames.contains("Documents"), "Category 'Documents' is measured")
    assertTest(catNames.contains("Applications"), "Category 'Applications' is measured")
    assertTest(catNames.contains("Developer"), "Category 'Developer' is measured")
    assertTest(catNames.contains("System Data"), "Category 'System Data' is measured")
    assertTest(catNames.contains("macOS"), "Category 'macOS' is measured")
}

// Test 17: Darwin Mach Kernel Process Telemetry
await runAsyncTest("Darwin Mach Kernel Process Telemetry") {
    let telemetry = SystemTelemetry.captureCurrentProcessTelemetry()
    assertTest(telemetry.physicalFootprint > 0, "Physical footprint is positive from Darwin kernel: \(telemetry.physicalFootprint / 1024 / 1024) MB")
    assertTest(telemetry.residentSize > 0, "Resident size (RSS) is positive: \(telemetry.residentSize / 1024 / 1024) MB")
    assertTest(telemetry.userCPUTimeMicroseconds + telemetry.systemCPUTimeMicroseconds > 0, "Cumulative Mach thread CPU execution time is captured")
}

// Test 18: TOCTOU Revalidation & Symlink Mutation Defense
await runAsyncTest("TOCTOU Immediate Revalidation Before Removal") {
    let toctouTarget = tempDir.appendingPathComponent("toctou_target.txt")
    try "Original legitimate file".write(to: toctouTarget, atomically: true, encoding: .utf8)

    // Pre-flight validation passes initially
    let initialValidation = SafetyValidator.validate(path: toctouTarget.path)
    if case .passed = initialValidation {
        assertTest(true, "Initial file passed safety validation")
    } else {
        assertTest(false, "Initial file should pass validation")
    }

    // Now mutate: delete file and replace with symlink to /etc/hosts
    try FileManager.default.removeItem(at: toctouTarget)
    try FileManager.default.createSymbolicLink(at: toctouTarget, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))

    // Revalidate immediately before destructive action
    let revalidation = SafetyValidator.validate(path: toctouTarget.path)
    if case .failed(let reason) = revalidation {
        assertTest(reason.contains("symbolic link"), "TOCTOU attack detected and prevented: \(reason)")
    } else {
        assertTest(false, "SafetyValidator failed to detect symlink substitution!")
    }
}

// Test 19: Cache Cleanup 5-Metric Accounting & Candidate Breakdown Verification
await runAsyncTest("Cache Cleanup 5-Metric Storage Recovery & Candidate Accounting") {
    let fixtureDir = tempDir.appendingPathComponent("CleanupFixture_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)

    // Create 3 files in fixture:
    // File 1: Old cache file (16 KB) -> Safe to clean
    let oldCacheFile = fixtureDir.appendingPathComponent("old_cache.dat")
    let data16k = Data(repeating: 0x43, count: 16384)
    try data16k.write(to: oldCacheFile)

    // File 2: Hard-link copy of File 1 -> Safe to clean, but hard link deduplicated
    let hardLinkFile = fixtureDir.appendingPathComponent("hardlink_cache.dat")
    try FileManager.default.linkItem(at: oldCacheFile, to: hardLinkFile)

    // File 3: Inactive log file (8 KB) -> Safe to clean
    let logFile = fixtureDir.appendingPathComponent("app.log")
    let data8k = Data(repeating: 0x4C, count: 8192)
    try data8k.write(to: logFile)

    // Scan the fixture
    let scanner = FilesystemScanner()
    let scanResult = await scanner.scan(roots: [fixtureDir])
    assertTest(scanResult.items.count == 3, "Discovered exactly 3 candidate files in fixture")

    // Construct findings manually for this test fixture
    let oldFinding = Finding(
        category: .userCaches,
        title: "Old Cache",
        path: oldCacheFile.path,
        logicalSize: 16384,
        allocatedSize: 16384,
        ruleId: "RULE-CACHE-01",
        ruleDescription: "Test cache",
        evidence: ["Test fixture"],
        eligibility: .safeToClean,
        riskLevel: .low,
        recoveryMethod: .directRemoval,
        estimatedReclaimableBytes: 16384
    )
    let hardLinkFinding = Finding(
        category: .userCaches,
        title: "Hardlink Cache",
        path: hardLinkFile.path,
        logicalSize: 16384,
        allocatedSize: 16384,
        ruleId: "RULE-CACHE-01",
        ruleDescription: "Test hardlink",
        evidence: ["Test fixture"],
        eligibility: .safeToClean,
        riskLevel: .low,
        recoveryMethod: .directRemoval,
        estimatedReclaimableBytes: 16384
    )
    let logFinding = Finding(
        category: .systemLogs,
        title: "Old Log",
        path: logFile.path,
        logicalSize: 8192,
        allocatedSize: 8192,
        ruleId: "RULE-LOGS-01",
        ruleDescription: "Test log",
        evidence: ["Test fixture"],
        eligibility: .safeToClean,
        riskLevel: .low,
        recoveryMethod: .directRemoval,
        estimatedReclaimableBytes: 8192
    )
    let reviewOnlyFinding = Finding(
        category: .largeFiles,
        title: "Review Installer",
        path: "/mock/review_only.dmg",
        logicalSize: 50 * 1024 * 1024,
        allocatedSize: 50 * 1024 * 1024,
        ruleId: "RULE-INSTALLER-01",
        ruleDescription: "Review item",
        evidence: ["Must be skipped"],
        eligibility: .reviewRecommended,
        riskLevel: .medium,
        recoveryMethod: .macOSTrash,
        estimatedReclaimableBytes: 50 * 1024 * 1024
    )

    let allDiscovered = [oldFinding, hardLinkFinding, logFinding, reviewOnlyFinding]

    let engine = CleanupEngine()
    let summary = await engine.executeSafeBatch(
        findings: allDiscovered,
        scanDuration: 0.12,
        targetVolumeURL: tempDir
    )

    // Verify candidate breakdown
    assertTest(summary.candidatesDiscoveredCount == 4, "Candidate discovered count matches input (4)")
    assertTest(summary.itemsEligibleCount == 3, "Items eligible count reflects Safe to Clean only (3)")
    assertTest(summary.itemsSkippedCount == 1, "Review only item safely skipped (1)")
    assertTest(summary.itemsSucceededCount == 3, "All 3 eligible items processed successfully")
    assertTest(summary.itemsFailedCount == 0, "Zero failures reported")

    // Verify 5 storage metrics
    // Metric 1: Logical bytes identified (16384 + 8192 = 24576, hard link deduplicated)
    assertTest(summary.logicalBytesIdentified == 24576, "Metric 1 (Logical Bytes Identified) deduplicated hard links: \(summary.logicalBytesIdentified) == 24576")
    // Metric 2: Estimated reclaimable storage
    assertTest(summary.estimatedReclaimableBytes == 24576, "Metric 2 (Estimated Reclaimable Storage) matches deduplicated blocks: \(summary.estimatedReclaimableBytes)")
    // Metric 3: Bytes successfully processed (both files removed from disk)
    assertTest(summary.bytesSuccessfullyProcessed == 40960, "Metric 3 (Bytes Successfully Processed) captures all handled paths: \(summary.bytesSuccessfullyProcessed)")
    // Metric 4: Observed filesystem capacity delta
    assertTest(summary.beforeCapacity.totalCapacity > 0, "Before-cleanup volume capacity is measured")
    assertTest(summary.afterCapacity.totalCapacity > 0, "After-cleanup volume capacity is measured")
    // Metric 5: Verified reclaimed storage
    assertTest(summary.verifiedReclaimedBytes >= 0, "Metric 5 (Verified Reclaimed Storage) derived from OS capacity delta")

    // Verify files on disk
    assertTest(!FileManager.default.fileExists(atPath: oldCacheFile.path), "Eligible cache file was cleanly removed")
    assertTest(!FileManager.default.fileExists(atPath: logFile.path), "Eligible log file was cleanly removed")
}

// Test 20: Cooperative Cancellation Responsiveness
await runAsyncTest("Cooperative Cancellation Responsiveness") {
    let largeDir = tempDir.appendingPathComponent("CancelFixture", isDirectory: true)
    try FileManager.default.createDirectory(at: largeDir, withIntermediateDirectories: true)
    for i in 0..<300 {
        let f = largeDir.appendingPathComponent("item_\(i).txt")
        try "test".write(to: f, atomically: true, encoding: .utf8)
    }

    let cancelScanner = FilesystemScanner()
    let scanTask = Task {
        return await cancelScanner.scan(roots: [largeDir])
    }

    // Cancel task immediately
    scanTask.cancel()
    await cancelScanner.cancel()
    let cancelResult = await scanTask.value

    assertTest(!cancelResult.completedNormally, "Scan safely reported non-normal completion upon cooperative cancellation")
}

// Test 21: Efficiency Benchmarking Across Workloads (Small, Deep, Many Files, Cold vs Warm)
await runAsyncTest("Efficiency Benchmarking Across Workloads & Warm Cache Speedup") {
    // Workload A: Small directory tree (100 files)
    let smallDir = tempDir.appendingPathComponent("WorkloadA_Small", isDirectory: true)
    try FileManager.default.createDirectory(at: smallDir, withIntermediateDirectories: true)
    for i in 0..<100 {
        try "small".write(to: smallDir.appendingPathComponent("f_\(i).txt"), atomically: true, encoding: .utf8)
    }

    let benchScanner = FilesystemScanner()
    let coldStartA = Date()
    let resColdA = await benchScanner.scan(roots: [smallDir])
    let coldDurA = Date().timeIntervalSince(coldStartA)

    assertTest(resColdA.items.count == 100, "Workload A (Small) found all 100 files")
    assertTest(coldDurA > 0, "Workload A scan duration is positive (\(String(format: "%.3f", coldDurA))s)")
    let throughputA = Double(resColdA.items.count) / max(0.0001, coldDurA)
    assertTest(throughputA > 0, "Workload A throughput is positive: \(String(format: "%.0f", throughputA)) items/s")

    // Workload B: Deep directory tree (5 levels deep)
    var currentSub = tempDir.appendingPathComponent("WorkloadB_Deep", isDirectory: true)
    for depth in 0..<5 {
        currentSub = currentSub.appendingPathComponent("Level_\(depth)", isDirectory: true)
        try FileManager.default.createDirectory(at: currentSub, withIntermediateDirectories: true)
        for i in 0..<20 {
            try "deep".write(to: currentSub.appendingPathComponent("deep_\(i).txt"), atomically: true, encoding: .utf8)
        }
    }
    let resDeep = await benchScanner.scan(roots: [tempDir.appendingPathComponent("WorkloadB_Deep")])
    assertTest(resDeep.items.count == 105, "Workload B (Deep) traversed all 5 directory levels (100 files + 5 folders = 105)")

    // Workload C: Controlled 500-file Cold vs Warm Benchmark
    let comparison = await BenchmarkManager.shared.runControlledBenchmark()
    assertTest(comparison.itemCount >= 500, "Controlled benchmark evaluated \(comparison.itemCount) items")
    assertTest(comparison.coldDurationSeconds > 0, "Cold traversal duration is positive (\(String(format: "%.3f", comparison.coldDurationSeconds))s)")
    assertTest(comparison.warmDurationSeconds > 0, "Warm traversal duration is positive (\(String(format: "%.3f", comparison.warmDurationSeconds))s)")
    assertTest(comparison.warmSpeedupFactor > 0, "Warm speedup factor is calculated: \(String(format: "%.2f", comparison.warmSpeedupFactor))x")
    assertTest(comparison.memoryFootprintBytes > 0, "Process memory footprint during benchmark is verified via Mach kernel: \(comparison.memoryFootprintBytes / 1024 / 1024) MB")
}

print("\n==================================================")
print("  Test Results: \(passedCount) Passed, \(failedCount) Failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
} else {
    exit(0)
}

