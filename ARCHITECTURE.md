# Architecture Specification: Squirrel (macOS Storage Cleaner)
**Document Version:** 2.0 (Baseline for Stage 0)  
**Status:** Approved Working Architecture Baseline  

---

## 1. Executive Summary & Technology Decision

### Selected Architecture: Native Swift + AppKit / SwiftUI
- **Language & Runtime:** Swift 6 (Toolchain verified: Apple Swift 6.4 / clang-2100.3.34.1, Command Line Tools SDK).
- **UI Framework:** SwiftUI & AppKit (`NSWorkspace`, `NSApplication`, `NSWindow`, `FileManager`).
- **Target OS:** macOS 14.0+ (Sonoma and later).
- **Target Architectures:** Universal Binary (`arm64` for Apple Silicon and `x86_64` for Intel).
  - *Verification Boundary:* Intel compilation is validated via `lipo` fat binary linking; **Intel runtime execution remains explicitly unverified** until executed on physical Intel hardware or an Intel CI runner.
- **Zero Third-Party Runtime Overhead:** Pure native toolchain utilizing Foundation, AppKit, CryptoKit, and POSIX filesystem APIs.

---

## 2. System Architecture & Modular Boundaries

The core storage engine is strictly decoupled from presentation:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Presentation Layer                               │
│  - Storage Overview Dashboard & Capacity Meter                              │
│  - Interactive Squarified Treemap (Pure Swift Layout & Drill-down)          │
│  - Findings & Opportunity Inspector                                         │
│  - Exact Duplicates Manager (Mandatory User Review Matrix)                  │
│  - Startup Items Inspector (Inventory, Running Status, App Ownership)       │
│  - History, Quarantine & Rollback Inspector                                 │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ Observes via Combine / ObservableObject
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                           AppState Coordinator                              │
│  - Central state machine & cooperative cancellation controller               │
│  - Real-time progress publisher                                             │
└───────────┬──────────────────────────┬───────────────────────────┬──────────┘
            │                          │                           │
┌───────────▼──────────────┐ ┌─────────▼─────────────┐ ┌──────────▼───────────┐
│ Filesystem Scanner Engine│ │ App Attribution Engine│ │ Startup Item Manager │
│ - Async directory walker │ │ - Bundle ID mapping   │ │ - ~/Library/Launch*  │
│ - Stat & inode tracking  │ │ - Code signature check│ │ - /Library/Launch*   │
│ - Hard link deduplicator │ │ - Ownership:          │ │ - BTM / LoginItems   │
│ - Inaccessible recorder  │ │   Confirmed / Likely /│ │ - Non-destructive    │
│ - APFS accounting        │ │   Unknown with proofs │ │   disable / enable   │
└───────────┬──────────────┘ └─────────┬─────────────┘ └──────────────────────┘
            │                          │
┌───────────▼──────────────────────────▼─────────────┐
│             Classification & Safety Engine         │
│  - Review Recommended by default for all findings   │
│  - Explicit category-specific safety allowlists     │
│  - Age/zero-byte alone does NOT authorize deletion  │
│  - Developer workspace protection policy            │
└──────────────────────────┬─────────────────────────┘
                           │ Dispatches Validated Actions
┌──────────────────────────▼─────────────────────────┐
│              Safe Cleanup & Hybrid Recovery        │
│  - Pre-flight TOCTOU & symlink re-check            │
│  - Finder Trash (NSWorkspace.recycle / trashItem)  │
│  - Managed Quarantine (~/Library/App Support/...)  │
│  - Schema-versioned Atomic Operation Journal       │
└────────────────────────────────────────────────────┘
```

---

## 3. Storage Accounting & APFS Semantics

1. **Capacity & Volume Free Space:**
   - Source: `statvfs` and `URLResourceValues` (`volumeTotalCapacityKey`, `volumeAvailableCapacityKey`, `volumeAvailableCapacityForImportantUsageKey`).
   - Measurements are reported directly from filesystem APIs without arbitrary inflation.

2. **Distinct Size Metrics:**
   The engine strictly distinguishes three separate metrics:
   - **Logical File Size:** Byte count of data contents (`fileSizeKey` / `stat.st_size`).
   - **Reported Allocated Size:** Actual disk blocks allocated on the filesystem (`stat.st_blocks * 512` / `totalFileAllocatedSizeKey`).
   - **Estimated Reclaimable Space:** Conservative estimate based on eligible files, accounting for hard-link duplication.

3. **APFS Clones, Snapshots & Shared Extents Limitation:**
   - Inode and device tracking (`st_dev`, `st_ino`) accurately deduplicates physical hard links.
   - However, **APFS copy-on-write clones and shared extents cannot be detected solely through inode tracking**, as clones have distinct inodes while sharing physical data blocks.
   - Deleting an APFS clone will not increase physical free space until all referencing clones are removed.
   - If an APFS local snapshot (e.g., Time Machine) references deleted blocks, free disk space does not immediately increase. Squirrel explicitly communicates this limitation to users.

---

## 4. Application Attribution Service (`AppAttributionService`)

A shared attribution service correlates discovered files, caches, logs, and background services with installed macOS applications:

```swift
public enum AttributionConfidence: String, Codable, Sendable {
    case confirmed = "Confirmed" // Matched bundle ID, valid code signature & path
    case likely    = "Likely"    // Matched vendor domain prefix or reverse-DNS naming
    case unknown   = "Unknown"   // Unattributed standalone file or orphan
}

public struct AppAttribution: Sendable {
    public let appName: String?
    public let bundleIdentifier: String?
    public let confidence: AttributionConfidence
    public let evidence: [String]
}
```

### Attribution Strategy:
1. **Installed Applications Index:** Scans `/Applications`, `/System/Applications`, and `~/Applications` for registered `Info.plist` bundle identifiers and names.
2. **LaunchAgents & Service Plists:** Correlates `ProgramArguments`, `Label`, and bundle identifiers against the application index.
3. **Evidence Log:** Provides traceable evidence strings (e.g., `"Matches bundle ID com.spotify.client from /Applications/Spotify.app"`).

---

## 5. Startup Item Management Module (`StartupInventoryService`)

Manages background persistence mechanisms with non-destructive disable/enable workflows:

### Supported Locations:
- **User LaunchAgents:** `~/Library/LaunchAgents/`
- **System LaunchAgents:** `/Library/LaunchAgents/` (read inventory; administrative privileges required for modification)
- **System LaunchDaemons:** `/Library/LaunchDaemons/` (read-only inventory)
- **Login Items:** Background Task Management (BTM) / ServiceManagement where supported, with read-only fallback where private APIs are disallowed.

### Operation Policy:
- **No Indiscriminate Deletion:** Startup items are disabled reversibly (e.g. by setting `Disabled = true` in the plist or appending `.disabled`), never deleted without user confirmation.
- **Attribution Display:** Each item displays its associated application name, bundle ID, path, and running status.

---

## 6. Revised Cleanup Safety & Classification Matrix

### Core Principle:
**A file being old, unlocked, or zero bytes does NOT prove it is safe to delete.**
All findings require explicit category-specific safety rules, and the default policy across all categories is **Review Recommended**.

| Category | Default Action | Safety Level | Safety Rules & Policy |
|---|---|---|---|
| **System & User Caches** | Review Recommended | Selective Clean | Only allowlisted transient subcategories (e.g. inactive web asset caches older than 7 days) can be batch-cleaned. All other caches require review. |
| **Old Log Files** | Review Recommended | Review Required | 14-day inactivity is a discovery threshold, not automatic permission to delete. Critical diagnostic logs require user review. |
| **Download Installers** | Review Recommended | Review Required | `.dmg`, `.pkg`, `.iso` in user folders. Mandatory manual review; never batch-cleaned. |
| **Large Files** | Review Recommended | Review Required | Files >= 100 MB. Classified by type and age; user review mandatory. |
| **Exact Duplicate Files** | Review Recommended | Review Required | Multi-stage content hash verified. Mandatory manual selection of copies to remove. |
| **Developer Workspaces** | Keep / Excluded | Excluded | Xcode `DerivedData`, Docker containers, `node_modules`, Cargo caches are excluded in v1.0. |
| **Zero-Byte Files** | Keep / Review | Excluded from Auto-Delete | Zero-byte lockfiles and sentinel files are NOT automatically deleted; they may represent active application state. |

---

## 7. Hybrid Recovery & Quarantine Design

1. **Finder Trash (`NSWorkspace.recycle(_:)` / `FileManager.default.trashItem`):**
   - Primary recovery method for user documents, installers, and duplicates.
   - *Limitation Disclosure:* Trash placement does not guarantee that Finder's "Put Back" will succeed for non-standard or external volume paths.

2. **Managed Quarantine:**
   - **Location:** `~/Library/Application Support/com.localfirst.squirrel/Quarantine/`
   - **Permissions:** Restricted to owner-only (`0700` directory, `0600` archived files).
   - **Manifest (`quarantine_manifest_v1.json`):**
     - Schema version (`1.0`).
     - Original path and file name.
     - Timestamp, file size, permissions (`st_mode`), and SHA-256 checksum.
     - Collision-safe restoration logic (appends `_restored_<timestamp>` if target exists).

3. **Schema-Versioned Operation Journal (`operation_journal.json`):**
   - Stored in `~/Library/Application Support/com.localfirst.squirrel/`.
   - Written atomically (`atomicWrite`) to prevent corruption during unexpected shutdowns.
   - Schema versioned (`schemaVersion: 1`).
   - Redacts sensitive file paths and document contents from persistent logs.

---

## 8. Multi-Stage Duplicate Detection Pipeline

1. **Size Clustering:** Group candidate regular files (> 0 bytes) by exact logical byte length.
2. **Prefix Cryptographic Hash:** Calculate CryptoKit SHA-256 over the initial 16 KB for clusters with > 1 file.
3. **Full Cryptographic SHA-256 Hash:** Stream full cryptographic SHA-256 hash for prefix collisions.
4. **Content Verification:** Exact byte-for-byte or cryptographic confirmation before labeling as duplicates.
5. **No Double-Counting:** Potential savings calculated strictly as `(count - 1) * size`.
6. **Mandatory Manual Selection:** Squirrel never automatically deletes duplicate copies.
