# Security Architecture & Safeguards

## 1. Principles
- **Fail-Closed Execution:** If an item cannot be conclusively validated prior to cleanup, the operation aborts immediately.
- **No Elevated Privileges:** The application runs under the unprivileged user context. It never calls `sudo`, never asks for root credentials, and never tampers with macOS security controls.
- **Local-First Privacy:** No network socket is opened. No telemetry or analytics payloads are compiled or sent. Sensitive file paths and user document names are never exported to external systems.

## 2. Defenses Against Filesystem Exploits

1. **Time-of-Check to Time-of-Use (TOCTOU):**
   - Between the time a file is scanned and the moment a user clicks "Clean", the file could be replaced with a symlink to a sensitive location (e.g. `/etc/passwd` or `~/.ssh/id_rsa`).
   - *Safeguard:* Prior to executing any deletion, quarantine, or trash action, the cleaner performs `lstat()` and `URLResourceValues` checks to verify:
     - The item is NOT a symbolic link.
     - The item's file system identifier (inode and dev) matches the scanned finding.
     - The file modification timestamp and size have not changed unexpectedly.
2. **Path Traversal Protection:**
   - All directory traversals are strictly bound to canonicalized real paths (`resolvingSymlinksInPath`). Scanners never follow symlinks that point outside the permitted scan root or point to parent directory cycles.
3. **Quarantine Sanitization:**
   - Quarantined files are moved into a structured, sandboxed folder with restrictive permissions (`0700`). Manifest records store cryptographic hashes (SHA-256) to ensure file integrity upon recovery.
