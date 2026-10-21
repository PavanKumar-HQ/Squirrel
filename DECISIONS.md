# Architectural & Product Decision Records (ADR)

## ADR-001: Native Swift & SwiftUI Implementation
- **Context:** The cleaner must be a production-quality, fast, responsive macOS application targeting both Apple Silicon (`arm64`) and Intel (`x86_64`) without bloated runtimes.
- **Decision:** Implement the entire application in pure Swift 6 with SwiftUI and Foundation/AppKit.
- **Alternatives Considered:**
  - *Tauri / Rust:* Rust is not installed on the system; web view bridges add IPC latency and memory overhead.
  - *Electron:* Consumes excessive memory (unacceptable on a 16GB baseline Mac).
- **Consequences:** Near-instant launch times, minimal memory footprint (~35MB idle vs 250MB+ in Electron), direct access to AppKit Finder recycling (`NSWorkspace.recycle`) and POSIX file system APIs.

## ADR-002: Multi-Stage Cryptographic Duplicate Detection
- **Context:** Detecting identical duplicate files on modern SSDs must not exhaust I/O or freeze the UI by hashing gigabytes of distinct files.
- **Decision:** Use a 4-tier detection pipeline:
  1. *Size clustering:* Group files with identical byte lengths (> 0 bytes). Files with unique sizes are eliminated immediately without reading content.
  2. *Inexpensive prefix hashing:* Read and hash the initial 16 KB using CryptoKit SHA-256. Files differing in headers/metadata are eliminated.
  3. *Full cryptographic hashing:* Compute full SHA-256 for candidate collisions.
  4. *Mandatory human selection:* The app never automatically deletes duplicate files; the user must inspect and select which copies to prune.
- **Consequences:** I/O reads are cut by ~95% compared to naive hashing.

## ADR-003: Progressive Permissions & Fail-Safe Inaccessibility Handling
- **Context:** macOS enforces strict privacy boundaries (TCC, System Integrity Protection, Sandbox/FDA). Some folders (`~/Library/Personal Data`, SIP locations) return permission denied.
- **Decision:** The scanner never stops or crashes on `EACCES`/`EPERM`. It catalogs unreadable paths into a clear "Inaccessible Locations" diagnostic report and computes honest totals based only on readable bytes.
- **Consequences:** Transparent user communication without misleading free space estimates.

## ADR-004: Hybrid Recovery Policy (Trash, Quarantine, Direct Removal)
- **Context:** Deleting files permanently can lead to accidental data loss.
- **Decision:**
  - User documents, downloads, installers, and duplicates are moved to macOS Trash (`FileManager.default.trashItem`).
  - System/app caches with restoration potential go to a managed, manifest-tracked quarantine directory.
  - Direct permanent removal is restricted to zero-byte lockfiles and explicitly allowlisted ephemeral cache records.
- **Consequences:** High user confidence and reversible actions.
