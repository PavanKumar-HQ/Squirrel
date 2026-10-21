# Limitations & Boundary Conditions
**Stage 0 Baseline**

---

## 1. Filesystem & APFS Accounting Limitations

1. **Allocated Blocks vs. Guaranteed Reclaimable Storage:**
   - `stat.st_blocks * 512` measures reported allocated blocks on disk, not guaranteed uniquely reclaimable physical storage.
   - Filesystem metadata, block alignment, and APFS compression can cause discrepancies between reported allocated size and actual physical container changes.

2. **APFS Clones, Shared Extents & Copy-on-Write:**
   - Inode/device tracking identifies physical hard links, but **cannot detect all APFS copy-on-write clone relationships**, because APFS clones possess distinct inodes while sharing data blocks.
   - Deleting one clone among multiple copies will not release physical storage blocks until all clones referencing those extents are removed.

3. **APFS Local Snapshots (Time Machine):**
   - Deleting files on an APFS volume does not immediately release physical space if an APFS local snapshot references the underlying data blocks. The space is only reclaimed once the snapshot expires or is deleted by macOS.
   - Squirrel explicitly communicates this so users are not misled when available space does not instantly increase 1:1.

4. **System Integrity Protection (SIP) & Sealed System Volumes (SSV):**
   - System directories (`/System`, `/usr/bin`, `/sbin`) are read-only and governed by SIP and cryptographically sealed APFS snapshots. Squirrel never attempts to modify SIP-protected locations.

5. **TCC Privacy Boundaries without Full Disk Access (FDA):**
   - Without FDA granted by the user, directories such as `~/Library/Mail`, `~/Library/Safari`, and `~/Library/Messages` return permission denied. Squirrel detects this and lists them honestly under **Inaccessible Areas** rather than fabricating numbers.

---

## 2. Recovery & Trash Caveats

1. **Finder "Put Back" Limitations:**
   - Moving files to macOS Trash via `NSWorkspace.recycle` or `FileManager.default.trashItem` places them into Trash. However, macOS Finder does not guarantee that "Put Back" will be available or functional for files originating from non-standard directories, command-line operations, or secondary volumes.

2. **Quarantine Rollback Limitations:**
   - Managed quarantine preserves files, permissions, and cryptographic hashes in an atomic manifest. However, if a third-party application has modified its internal configuration or database schema during the period an item was quarantined, restoring the raw cache file may not restore prior application state.

---

## 3. Startup Item Management Boundaries

1. **Apple `SMAppService` Scope:**
   - Apple's `SMAppService` is designed for applications to manage their *own* bundled helper daemons and login items; it is not a universal API for managing arbitrary third-party services.
   - Squirrel inspects standard `LaunchAgents` and `LaunchDaemons` directories and uses supported plist disable mechanisms (`Disabled = true` or `.disabled` extension), falling back to read-only presentation where modification is restricted.

---

## 4. Platform & Hardware Verification Boundaries

1. **Intel (`x86_64`) Runtime Verification:**
   - Squirrel compiles for both Apple Silicon (`arm64`) and Intel (`x86_64`), producing a verified Universal 2 Mach-O fat binary.
   - However, **Intel runtime execution remains explicitly unverified** until executed and validated on physical Intel hardware or an Intel-based macOS test runner.
