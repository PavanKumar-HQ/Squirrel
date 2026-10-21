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

print("\n==================================================")
print("  Test Results: \(passedCount) Passed, \(failedCount) Failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
} else {
    exit(0)
}
