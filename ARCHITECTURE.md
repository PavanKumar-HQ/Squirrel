# Architecture Specification: Local-First macOS Storage Cleaner

## 1. Executive Summary & Technology Decision

### Selected Architecture: Native Swift 6 + SwiftUI (macOS 14.0+)
- **Language & Runtime:** Swift 6.4 with Swift Concurrency (`async`/`await`, structured tasks, actors).
- **UI Framework:** SwiftUI with AppKit integration (`NSWorkspace`, `NSItemProvider`, `NSApplication`).
- **Target OS:** macOS 14.0 (Sonoma) and later.
- **Architectures:** Universal Binary (`arm64` for Apple Silicon and `x86_64` for Intel).
- **Zero Third-Party Dependency Overhead:** Pure native toolchain using Swift Package Manager, Foundation, AppKit, CryptoKit, and POSIX filesystem APIs.

### Alternatives Considered & Rejected:
1. **Tauri + Rust:**
   - *Status in environment:* Rust toolchain is not installed (`rustc not found`).
   - *Trade-offs:* Requires Node/web frontend runtime, Chromium/WebKit IPC overhead, memory usage higher than native SwiftUI, less direct integration with macOS Finder Trash (`NSWorkspace.recycle`), AppKit drag-and-drop, and native security-scoped bookmarks.
2. **Electron:**
   - *Rejected:* Heavyweight (~200MB+ bundle, 300MB+ idle RAM), antithetical to a lean utility on a 16GB MacBook Air.
3. **Python / PyObjC:**
   - *Rejected:* Poor binary packaging, no native Swift concurrency, slower filesystem traversal on large trees.

---

## 2. System Architecture & Modular Boundaries

The application is architected into strictly decoupled layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    SwiftUI Presentation                     │
│  - Storage Overview Dashboard & Capacity Meter              │
│  - Interactive Squarified Treemap with Drill-down & Details  │
│  - Findings & Opportunity Inspector                         │
│  - Duplicate Manager with Selection Matrix                  │
│  - History, Quarantine & Recovery Inspector                 │
└──────────────────────────────┬──────────────────────────────┘
                               │ Observes & Dispatches Actions
┌──────────────────────────────▼──────────────────────────────┐
│                    Cleaner State Coordinator                │
│  - Scan state machine (Idle, Scanning, Complete, Cancelled)  │
│  - Real-time progress publisher                             │
│  - Unified findings catalog & selection model               │
└───────────┬──────────────────────────────────┬──────────────┘
            │ Drives                           │ Coordinates
┌───────────▼──────────────┐       ┌───────────▼──────────────┐
│ Filesystem Scan Engine   │       │ Safe Cleanup Engine      │
│ - Async directory walker │       │ - Safety Rule Validator  │
│ - Stat & size accounting │       │ - Pre-flight re-check    │
│ - Inode / hard link set  │       │ - Trash handler (Finder) │
│ - Inaccessible recorder  │       │ - Quarantine manager     │
│ - Category classifiers   │       │ - Direct remove (allow)  │
│ - Content-based hasher   │       │ - Journal & Audit Logger │
└──────────────────────────┘       └──────────────────────────┘
```

---

## 3. Storage Accounting & APFS Semantics

1. **Capacity & Volume Free Space:**
   - Source: `statvfs` and `URLResourceValues` (`volumeTotalCapacityKey`, `volumeAvailableCapacityForImportantUsageKey`, `volumeAvailableCapacityForOpportunisticUsageKey`).
   - Never fabricated or estimated arbitrarily.
2. **Logical vs Allocated Size:**
   - Logical size: `fileSizeKey` (content byte count).
   - Allocated size: `totalFileAllocatedSizeKey` / `fileAllocatedSizeKey` (actual blocks allocated on the APFS container).
3. **Hard Links & APFS Clones:**
   - Tracked via device ID and inode (`st_dev`, `st_ino`). Hard links sharing inodes are counted only once in aggregate storage calculations to prevent inflated numbers.
4. **No Universal Space Guarantees:**
   - Disk cleanup cannot promise exact byte-for-byte free space increase due to APFS copy-on-write clones, APFS local snapshots (Time Machine), and filesystem metadata allocation. The app explicitly informs users of this distinction.

---

## 4. Scan Categories & Classification Matrix

| Category | Default Action | Safety Level | Detection Rules & Evidence |
|---|---|---|---|
| **System & User Caches** | Review / Safe if inactive | Safe to Clean (selective) | User cache folders (`~/Library/Caches/*`) older than eligibility threshold; active apps checked. |
| **Old Log Files** | Safe to Clean | Safe to Clean | `.log`, `.crash`, `.diag` files in `~/Library/Logs` older than 14 days, non-locked. |
| **Download Installers & DMGs** | Review Recommended | Review Only | `.dmg`, `.pkg`, `.iso` in `~/Downloads` and user locations. *Never batch deleted automatically.* |
| **Large Files** | Review Recommended | Review Only | Files >= 100MB across scanned user directories. Classified by file type & age. |
| **Exact Duplicate Files** | Review Recommended | Review Only | Multi-stage content hash verified (SHA-256). *Mandatory manual copy selection.* |
| **Application Leftovers** | Review Recommended | Review Only | Orphaned preference/support files in `~/Library/Application Support` for uninstalled apps. |

---

## 5. Hybrid Recovery System

1. **macOS Trash (`FileManager.default.trashItem` / `NSWorkspace.shared.recycle`):**
   - Primary recovery method for user-facing files (downloads, duplicates, installers).
   - Allows users to review and put back files via standard macOS Finder Trash.
2. **Managed Quarantine (`~/.local/share/StorageCleaner/Quarantine`):**
   - Used for application caches or files where path metadata and atomic restoration are vital.
   - Saves a cryptographic manifest (`manifest.json`) storing original path, timestamp, file hash, and permissions.
   - Supports 1-click restore or collision-safe resolution.
3. **Direct Removal:**
   - Strictly restricted to allowlisted ephemeral cache files (e.g., temporary lockfiles, broken zero-byte `.tmp` files) where Trash placement creates unnecessary garbage.
4. **Operation Journal:**
   - Append-only local JSON log recording operation ID, timestamp, target path, action (Trash/Quarantine/Delete), result status, and error details (sanitized without logging private document contents).

---

## 6. Security Boundaries & Permissions

1. **Progressive Permissions:**
   - Out of the box, scans user-accessible folders (`~/Downloads`, `~/Library/Caches`, `~/Library/Logs`, user documents if granted).
   - Gracefully handles `EACCES` / `EPERM` without crashing or halting scans. Inaccessible paths are cataloged into an "Inaccessible Locations" report.
2. **Defense against Race Conditions (TOCTOU):**
   - Re-validates inode, file size, modification date, and non-symlink status immediately before executing any cleanup operation.
   - If the file was modified, replaced with a symlink, or deleted concurrently, operation aborts with a descriptive status.
3. **Zero Network / Local-First:**
   - Zero telemetry, zero analytics, zero external network requests.
