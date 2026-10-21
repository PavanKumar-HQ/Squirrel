# Limitations & Boundary Conditions

## 1. Filesystem & APFS Accounting Limitations

1. **APFS Local Snapshots (Time Machine):**
   - Deleting a large file on an APFS volume does not immediately release disk space if an APFS local snapshot (e.g., created by Time Machine or system updates) references the underlying data blocks. The space is only reclaimed once the snapshot expires or is deleted.
   - The cleaner clearly discloses this behavior to prevent user confusion when available space does not instantly increase 1:1.

2. **APFS Clones & Copy-On-Write:**
   - Duplicate files that are APFS clones share underlying disk blocks. Removing one copy may not release physical storage blocks until all clones are removed.

3. **System Integrity Protection (SIP) & Sealed System Volume (SSV):**
   - System files under `/System`, `/usr/bin`, `/sbin`, and protected system containers are read-only and governed by SIP and cryptographically signed APFS system volume snapshots. The application does not attempt to clean or tamper with SIP-protected locations.

4. **TCC Protected Directories without Full Disk Access (FDA):**
   - Without FDA granted by the user in macOS System Settings > Privacy & Security, protected directories (such as `~/Library/Mail`, `~/Library/Safari`, `~/Library/Messages`) return permission denied. The cleaner detects this and lists them honestly under Inaccessible Locations rather than guessing their contents.

## 2. Scope Exclusions in v1.0

1. **Developer Workspaces Deferred:**
   - Xcode `DerivedData`, simulator runtimes, Docker containers/images, Node `node_modules`, Cargo caches, and package manager databases are strictly deferred from automated cleanup to prevent breaking ongoing software development tasks.
2. **No Background Deletion / Daemons:**
   - The application does not install launch daemons, background watchers, or menu bar polling services. All operations are strictly on-demand.
