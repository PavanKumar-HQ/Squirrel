# Testing & Verification Guide

## 1. Overview

The StorageCleaner verification suite validates all core safety invariants, filesystem traversal safeguards, cryptographic duplicate hashing, quarantine and rollback integrity, and squarified treemap calculation.

All automated tests operate exclusively inside isolated temporary fixture directories (`FileManager.default.temporaryDirectory`), completely segregated from user documents and actual operating system directories.

---

## 2. Running Automated Tests

To execute the test suite:

```bash
swift run StorageCleanerTests
```

### Verified Test Results (35 Passed, 0 Failed):

1. **Volume Metrics & Accounting**
   - ✓ System volume total capacity is positive (245.11 GB)
   - ✓ Available capacity is positive (127.93 GB)
   - ✓ Used space is positive (117.18 GB)
   - ✓ Total capacity >= available capacity

2. **Scanner Nested Traversal & Metrics**
   - ✓ Scanner completed without error
   - ✓ Scanner found exactly 3 items (1 subfolder + 2 files)
   - ✓ Scanner accurately accounted for 6144 logical bytes

3. **Scanner Symlink & Cycle Protection**
   - ✓ Scanner safely handled symlink without getting trapped in cycle

4. **SafetyValidator Pre-Flight Defenses**
   - ✓ Regular file safely passed pre-flight validation
   - ✓ SafetyValidator correctly rejected symbolic link: Target path is a symbolic link; potential TOCTOU symlink substitution detected.
   - ✓ SafetyValidator correctly rejected system root '/'

5. **Exact Duplicate Content-Based Detection**
   - ✓ Duplicate detector found exactly 1 duplicate group
   - ✓ Duplicate group has exactly 2 members
   - ✓ Potential savings accurately calculated without double-counting: 56 bytes
   - ✓ Contains copy A
   - ✓ Contains copy B
   - ✓ Does NOT contain different file with same size
   - ✓ Has a designated recommended copy to keep

6. **Quarantine & Collision-Safe Restoration**
   - ✓ Original file removed after quarantine move
   - ✓ Quarantine record captures exact byte size
   - ✓ Quarantined file successfully restored
   - ✓ Collision safe naming applied (restored to collision-safe filename)
   - ✓ Restored content matches original payload exactly

7. **Classification Safety Rules**
   - ✓ Developer artifact classified as Keep / Not Recommended
   - ✓ Correct rule ID applied: `RULE-DEV-EXCLUDE`
   - ✓ Old inactive log classified as Safe to Clean
   - ✓ Correct rule ID applied: `RULE-LOGS-01`
   - ✓ Installer requires explicit Review Recommended (`RULE-INSTALLER-01`)

8. **Squarified Treemap Layout Engine**
   - ✓ Treemap hierarchy contains category nodes
   - ✓ Treemap tile has positive dimensions
   - ✓ Tile fits within canvas width
   - ✓ Tile fits within canvas height
