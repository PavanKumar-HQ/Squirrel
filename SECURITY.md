# Security Architecture & Safeguards
**Stage 0 Baseline**

---

## 1. Core Principles

- **Fail-Closed Execution:** If an item cannot be conclusively validated prior to modification, the operation aborts immediately.
- **Unprivileged Execution:** Squirrel executes strictly within the unprivileged user context. It never invokes `sudo`, never prompts for root credentials, and never bypasses SIP.
- **Strictly Local-First Privacy:** Zero network sockets are opened. No telemetry or analytics payloads are compiled or transmitted.

---

## 2. Filesystem Defenses

1. **Time-of-Check to Time-of-Use (TOCTOU) Defenses:**
   - Between the scan phase and the cleanup action, files could be concurrently modified, replaced, or swapped with symlinks.
   - *Safeguard:* Immediately prior to any action, Squirrel calls `lstat()` and `URLResourceValues` to verify:
     - The target is **NOT** a symbolic link.
     - The item's device ID (`st_dev`) and inode (`st_ino`) match the scanned finding.
     - The file size and modification timestamps have not unexpectedly changed.
     - The path does not resolve to protected system roots (`/`, `/System`, `/Library`, `/usr`).

2. **Symlink and Directory Cycle Protection:**
   - All directory traversals use canonicalized real paths (`resolvingSymlinksInPath`).
   - The scanner never follows symlinks outside the designated scan root and never traverses recursive directory cycles.

3. **Managed Quarantine Security:**
   - Quarantine directory: `~/Library/Application Support/com.localfirst.squirrel/Quarantine/`.
   - Permissions set to `0700` (owner only), with quarantined files set to `0600`.
   - Recovery manifest records SHA-256 checksums to verify payload integrity prior to restoration.

4. **Operation Journal Sanitization:**
   - Operation history records action types, statuses, byte counts, and sanitized names.
   - Private document contents and sensitive query strings are excluded from persistent logs.
