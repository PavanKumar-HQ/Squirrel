# StorageCleaner — Local-First macOS Storage Cleaner

A high-performance, privacy-respecting native macOS storage cleaner built in pure Swift. StorageCleaner helps users understand what is consuming disk space, identify genuinely unnecessary files, reclaim storage safely, and recover from mistakes whenever technically possible.

---

## Key Principles & Features

- **Strictly Local-First & Zero Telemetry:** No accounts, no background services, no network calls, no cloud tracking.
- **Accurate Storage Accounting:** Directly queries macOS volume APIs (`statvfs`, `URLResourceValues`) to measure true total capacity, allocated disk space, and purgeable boundaries without fabricating numbers.
- **Interactive Squarified Treemap:** Real-time proportional storage visualization (Bruls-Huizing-van Wijk algorithm) with category drill-down and item inspection.
- **Evidence-Based Classification:** Every finding is linked to an explicit rule ID, supporting filesystem evidence, risk tier, and explanation of consequences.
- **Verified "Clean Safely" Action:** One-click cleanup strictly limited to allowlisted, non-essential caches and old diagnostic logs.
- **Content-Based Exact Duplicate Detection:** Multi-stage detection using size clustering, prefix hashing, and full cryptographic SHA-256 matching. Manual user review is mandatory before any copy is deleted.
- **Hybrid Recovery System:**
  - **macOS Trash:** Standard files and installers are sent to Finder Trash for native Put Back recovery.
  - **Managed Quarantine:** Application caches are safely moved to a local sandboxed directory (`~/Library/Application Support/StorageCleaner/Quarantine`) tracked by an atomic JSON manifest with 1-click collision-safe restoration.
  - **Direct Removal:** Restricted solely to ephemeral zero-byte locks and temporary files.
- **Universal Binary:** Native execution on both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs running macOS 14.0+.

---

## Requirements

- **Operating System:** macOS 14.0 (Sonoma) or newer.
- **Toolchain:** Swift 5.9+ / 6.0+ with Command Line Tools or Xcode.
- **Hardware:** Apple Silicon (`arm64`) or Intel (`x86_64`).

---

## Quick Start & Build Instructions

### 1. Run the Automated Test Suite

```bash
swift run StorageCleanerTests
```

### 2. Build and Run StorageCleaner in Development

```bash
swift run StorageCleaner
```

### 3. Build Universal Release Application Bundle & DMG

```bash
chmod +x scripts/build_release.sh
./scripts/build_release.sh
```

The resulting artifacts will be in the `dist/` directory:
- `dist/StorageCleaner.app` (Universal Mach-O 2 binary, ad-hoc code signed)
- `dist/StorageCleaner.dmg` (Checksum-verified Apple APFS/UDZO disk image)

---

## Architecture Overview

```
Sources/
├── StorageCleanerCore/            # Core business logic and filesystem engines
│   ├── Models/                    # VolumeSpace, StorageItem, Finding, DuplicateGroup, OperationJournal
│   ├── Scanner/                   # FilesystemScanner actor with safe traversal and cancellation
│   ├── Duplicates/                # DuplicateDetector actor with multi-stage SHA-256 hashing
│   ├── Rules/                     # ClassificationRules engine with traceable safety evidence
│   ├── Cleanup/                   # CleanupEngine, SafetyValidator (TOCTOU protection), QuarantineManager
│   └── Treemap/                   # TreemapEngine with squarified layout algorithm
│
└── StorageCleaner/                # Native macOS SwiftUI application
    ├── AppState.swift             # Central observable coordinator and state machine
    ├── StorageCleanerApp.swift    # App entry point with split navigation
    └── Views/
        ├── DashboardView.swift    # Overview capacity meter, opportunities card, embedded treemap
        ├── TreemapView.swift      # Interactive treemap canvas, drill-down breadcrumbs, details sidebar
        ├── FindingsListView.swift # Filterable catalog with expandable technical evidence
        ├── DuplicatesView.swift   # Duplicate groups matrix with keep recommendation
        ├── HistoryView.swift      # Operation journal log and quarantine restoration manager
        └── InaccessibleLocationsView.swift # Transparent permission boundary reporting
```

---

## Documentation Index

- [`ARCHITECTURE.md`](file:///Users/pavankumars/Downloads/mac%20storage/ARCHITECTURE.md): System architecture, modular boundaries, and design choices.
- [`SECURITY.md`](file:///Users/pavankumars/Downloads/mac%20storage/SECURITY.md): Threat model, symlink defenses, and TOCTOU mitigations.
- [`DECISIONS.md`](file:///Users/pavankumars/Downloads/mac%20storage/DECISIONS.md): Architectural decision records (ADRs).
- [`LIMITATIONS.md`](file:///Users/pavankumars/Downloads/mac%20storage/LIMITATIONS.md): Filesystem boundaries, APFS snapshots, and deferred scope.
- [`TESTING.md`](file:///Users/pavankumars/Downloads/mac%20storage/TESTING.md): Test execution commands and safety verification reports.
- [`RELEASE.md`](file:///Users/pavankumars/Downloads/mac%20storage/RELEASE.md): Distribution, packaging, Developer ID signing, and notarization guide.

---

## License

Free & Open Essential macOS Utility.
