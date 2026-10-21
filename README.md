# Squirrel

<p align="center">
  <img src="Resources/AppIcon.png" alt="Squirrel Icon" width="128" height="128" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.3);">
</p>

<p align="center">
  <strong>A little more room for your Mac.</strong><br>
  <em>A high-performance, strictly local-first native macOS storage cleaner with evidence-based cleanup and hybrid recovery.</em>
</p>

<p align="center">
  <a href="https://github.com/PavanKumar-HQ/Squirrel"><img src="https://img.shields.io/badge/macOS-14.0%2B-blue.svg?style=flat-square" alt="macOS 14+"></a>
  <a href="https://github.com/PavanKumar-HQ/Squirrel"><img src="https://img.shields.io/badge/Architecture-Universal%20(arm64%20%2B%20x86__64)-purple.svg?style=flat-square" alt="Universal Binary"></a>
  <a href="https://github.com/PavanKumar-HQ/Squirrel"><img src="https://img.shields.io/badge/Privacy-100%25%20Local--First-green.svg?style=flat-square" alt="Privacy"></a>
  <a href="https://github.com/PavanKumar-HQ/Squirrel"><img src="https://img.shields.io/badge/Telemetry-Zero-orange.svg?style=flat-square" alt="Zero Telemetry"></a>
</p>

---

## Overview

**Squirrel** helps users understand what is consuming disk space, identify genuinely unnecessary files, reclaim storage safely, and recover from mistakes whenever technically possible.

Built natively in Swift without webview bloat, Squirrel operates strictly on-demand. It features no background daemons, no accounts, no cloud sync, and zero external network calls.

---

## Key Features

- **Strictly Local-First & Zero Telemetry:** No accounts, no background services, no network calls, and no analytics. Your filesystem data never leaves your machine.
- **Accurate Storage Accounting:** Queries macOS APFS/HFS+ volume APIs (`statvfs`, `URLResourceValues`) to measure true total capacity, allocated disk space, and purgeable boundaries without fabricating numbers.
- **Interactive Squarified Treemap:** Real-time proportional storage visualization (Bruls-Huizing-van Wijk algorithm) with category drill-down, breadcrumb navigation, and item inspection.
- **Evidence-Based Classification:** Every finding is linked to an explicit rule ID (e.g. `RULE-CACHE-01`, `RULE-LOGS-01`, `RULE-INSTALLER-01`, `RULE-LARGE-01`), supporting filesystem evidence, risk tier, and explanation of potential consequences.
- **Verified "Clean Safely" Action:** One-click cleanup strictly limited to allowlisted, non-essential caches and stale diagnostic logs.
- **Content-Based Exact Duplicate Detection:** Multi-stage detection using size clustering, prefix hashing, and full cryptographic SHA-256 matching. Manual user review is mandatory before any copy is deleted.
- **Hybrid Recovery System:**
  - **macOS Trash:** Standard files and installers are sent to Finder Trash for native Put Back recovery.
  - **Managed Quarantine:** Application caches are safely moved to a local sandboxed directory (`~/Library/Application Support/Squirrel/Quarantine`) tracked by an atomic JSON manifest with 1-click collision-safe restoration.
  - **Direct Removal:** Restricted solely to ephemeral zero-byte locks and temporary files.
- **Universal Binary:** Native execution on both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs running macOS 14.0+.

---

## Quick Start & Running Options

### 1. Launch the Native macOS Application

Since the Universal `.app` bundle has already been compiled and packaged:

```bash
open "dist/Squirrel.app"
```

Or open the `dist` folder in Finder and double-click `Squirrel.app`:
```bash
open dist/
```

### 2. View the Localhost Interactive Web Preview

Squirrel includes a local web showcase running directly on your machine:

```bash
python3 -m http.server 3000 --directory web
```

Then visit in your browser:
👉 **[http://localhost:3000](http://localhost:3000)**

### 3. Run the Automated Test Suite

To run all 35 filesystem, duplicate detection, quarantine rollback, and safety tests:

```bash
swift run SquirrelTests
```

### 4. Build Universal Release App & DMG

To re-compile dual architectures (`arm64` + `x86_64`), assemble the `.app` bundle, sign, and build the distributable `.dmg`:

```bash
chmod +x scripts/build_release.sh
./scripts/build_release.sh
```

Artifacts produced:
- **Application Bundle:** `dist/Squirrel.app` (Mach-O Universal 2 binary)
- **Disk Image:** `dist/Squirrel.dmg` (Checksum-verified Apple APFS/UDZO disk image)

---

## Architecture & Codebase Map

```
Sources/
├── SquirrelCore/                 # Core business logic and filesystem engines
│   ├── Models/                  # VolumeSpace, StorageItem, Finding, DuplicateGroup, OperationJournal
│   ├── Scanner/                 # FilesystemScanner actor with safe traversal and cancellation
│   ├── Duplicates/              # DuplicateDetector actor with multi-stage SHA-256 hashing
│   ├── Rules/                   # ClassificationRules engine with traceable safety evidence
│   ├── Cleanup/                 # CleanupEngine, SafetyValidator (TOCTOU protection), QuarantineManager
│   └── Treemap/                 # TreemapEngine with squarified layout algorithm
│
└── Squirrel/                    # Native macOS SwiftUI application
    ├── AppState.swift           # Central observable coordinator and state machine
    ├── SquirrelApp.swift        # App entry point with NavigationSplitView
    ├── Resources/               # High-resolution AppIcon assets
    └── Views/
        ├── DashboardView.swift  # Overview capacity meter, opportunities card, embedded treemap
        ├── TreemapView.swift    # Interactive treemap canvas, drill-down breadcrumbs, details sidebar
        ├── FindingsListView.swift # Filterable catalog with expandable technical evidence
        ├── DuplicatesView.swift # Duplicate groups matrix with keep recommendation
        ├── HistoryView.swift    # Operation journal log and quarantine restoration manager
        └── InaccessibleLocationsView.swift # Transparent permission boundary reporting

web/                             # Localhost interactive web preview (port 3000)
├── index.html                   # Dashboard UI with Squirrel branding
├── style.css                    # Dark macOS aesthetic & glassmorphism
└── app.js                       # Interactive treemap & cleanup simulation
```

---

## Classification Rules Matrix

| Rule ID | Category | Default Action | Safety Level | Recovery Policy |
|---|---|---|---|---|
| `RULE-CACHE-01` | **User Caches** | Safe to Clean (if inactive > 7 days) | Safe to Clean | Managed Quarantine |
| `RULE-LOGS-01` | **System & App Logs** | Safe to Clean (if inactive > 14 days) | Safe to Clean | macOS Trash |
| `RULE-INSTALLER-01` | **Download Installers** | Review Recommended | Review Only | macOS Trash |
| `RULE-LARGE-01` | **Large Files** | Review Recommended | Review Only | macOS Trash |
| `RULE-DUP-01` | **Exact Duplicates** | Review Recommended | Review Only | macOS Trash |
| `RULE-DEV-EXCLUDE` | **Developer Artifacts** | Keep / Excluded | Excluded | Never Cleaned |

---

## Documentation Index

- [`ARCHITECTURE.md`](file:///Users/pavankumars/Downloads/mac%20storage/ARCHITECTURE.md): System architecture, modular boundaries, and design choices.
- [`SECURITY.md`](file:///Users/pavankumars/Downloads/mac%20storage/SECURITY.md): Threat model, symlink defenses, and TOCTOU mitigations.
- [`DECISIONS.md`](file:///Users/pavankumars/Downloads/mac%20storage/DECISIONS.md): Architectural decision records (ADRs).
- [`LIMITATIONS.md`](file:///Users/pavankumars/Downloads/mac%20storage/LIMITATIONS.md): Filesystem boundaries, APFS snapshots, and deferred scope.
- [`TESTING.md`](file:///Users/pavankumars/Downloads/mac%20storage/TESTING.md): Test execution commands and 35-point safety verification reports.
- [`RELEASE.md`](file:///Users/pavankumars/Downloads/mac%20storage/RELEASE.md): Distribution, packaging, Developer ID signing, and notarization guide.

---

## Repository & Contributing

- **GitHub Repository:** [https://github.com/PavanKumar-HQ/Squirrel.git](https://github.com/PavanKumar-HQ/Squirrel.git)
- **Author:** Pavan Kumar (`sumapavan1231@gmail.com`)
- **License:** Free & Open Essential macOS Utility
