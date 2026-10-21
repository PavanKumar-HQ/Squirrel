# Architectural & Product Decision Records (ADR)
**Stage 0 Baseline**

---

## ADR-001: Native Swift & SwiftUI/AppKit Implementation
- **Context:** Squirrel requires a high-performance, responsive macOS utility without third-party web runtime overhead.
- **Decision:** Implement using Swift 6, AppKit, SwiftUI, Foundation, CryptoKit, and POSIX APIs.
- **Consequences:** Low memory footprint (~35 MB), direct integration with Finder Trash (`NSWorkspace.recycle`), native file coordination, and fast directory traversal.

## ADR-002: Multi-Stage Cryptographic Duplicate Detection
- **Context:** Detecting duplicate files across large trees must minimize I/O while guaranteeing that no two distinct files are ever misclassified.
- **Decision:** Staged pipeline: (1) size clustering, (2) 16 KB prefix cryptographic SHA-256 hash, (3) full SHA-256 hash, (4) full content confirmation.
- **Safety Rule:** The app never automatically deletes duplicate copies; the user must manually select copies to prune. Potential savings calculation `(count - 1) * size` avoids double-counting.

## ADR-003: Conservative Cleanup Safety Policy
- **Context:** Relying solely on file age, unlocked state, or zero-byte size can result in deleting active application state, lockfiles, or diagnostic archives.
- **Decision:**
  - Age, unlock status, or zero bytes does NOT grant automatic cleanup authorization.
  - Default classification is **Review Recommended** across all categories.
  - Batch "Clean Safely" is restricted to explicitly allowlisted, individually validated categories.
  - Zero-byte lockfiles are excluded from automatic cleanup.
- **Consequences:** Eliminates accidental deletion of active configuration or lock files.

## ADR-004: Shared Application Attribution Service
- **Context:** Users need to understand which installed application owns a cache, log, or startup item before taking action.
- **Decision:** Implement a shared `AppAttributionService` returning three confidence tiers:
  - `Confirmed`: exact bundle ID match in installed `.app` `Info.plist`, valid code signature and path structure.
  - `Likely`: vendor domain or reverse-DNS naming prefix match.
  - `Unknown`: unattributed or orphaned files.
  Includes a traceable evidence list for complete transparency.

## ADR-005: Startup Item Inventory & Non-Destructive Management
- **Context:** Third-party background persistence items (LaunchAgents, LaunchDaemons, Login Items) consume resources. Apple's `SMAppService` only manages services bundled with one's own app, not arbitrary third-party services.
- **Decision:**
  - Provide inventory across user `~/Library/LaunchAgents`, system `/Library/LaunchAgents`, and `/Library/LaunchDaemons` (read-only).
  - Use non-destructive disable actions (e.g. plist modification or renaming) rather than silent deletion.
  - Provide read-only fallback where permission or private API boundaries prevent modification.

## ADR-006: Standard macOS Quarantine Location
- **Context:** Non-standard Linux paths (e.g. `~/.local/share`) violate macOS conventions.
- **Decision:** Use `~/Library/Application Support/com.localfirst.squirrel/Quarantine/` with `0700` directory permissions and a versioned recovery manifest (`quarantine_manifest_v1.json`).

## ADR-007: Universal Binary Target & Intel Verification Boundary
- **Context:** The build pipeline produces a fat Mach-O Universal 2 binary supporting `arm64` and `x86_64` using `lipo`.
- **Decision:** Compile both architecture targets in the environment, but **explicitly document Intel runtime compatibility as unverified** until executed on physical Intel hardware or an Intel CI runner.
