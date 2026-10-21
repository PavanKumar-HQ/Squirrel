import Foundation
import Darwin

/// Validated metadata for a file that passed pre-flight safety checks.
public struct ValidatedFileMeta: Equatable, Sendable {
    public let deviceId: dev_t
    public let inode: ino_t
    public let size: Int64
    public let isDirectory: Bool

    public init(deviceId: dev_t, inode: ino_t, size: Int64, isDirectory: Bool) {
        self.deviceId = deviceId
        self.inode = inode
        self.size = size
        self.isDirectory = isDirectory
    }
}

/// Result of pre-flight safety verification before any cleanup action.
public enum ValidationOutcome: Equatable, Sendable {
    case passed(meta: ValidatedFileMeta)
    case failed(reason: String)
}

/// Validates file state immediately prior to modification or deletion to prevent TOCTOU and symlink attacks.
public struct SafetyValidator {
    public static func validate(
        path: String,
        expectedDeviceId: dev_t? = nil,
        expectedInode: ino_t? = nil,
        expectedSize: Int64? = nil
    ) -> ValidationOutcome {
        // 1. Path must not be empty or root
        guard !path.isEmpty, path != "/", path != "/System", path != "/Library", path != "/usr" else {
            return .failed(reason: "Attempted action on protected system root path: \(path)")
        }

        // 2. Perform lstat to inspect actual filesystem node without following symlinks
        var statBuf = stat()
        let result = lstat(path, &statBuf)
        guard result == 0 else {
            return .failed(reason: "File no longer exists or is inaccessible (errno: \(errno))")
        }

        // 3. Prohibit symbolic links from being deleted as regular files
        let isSymlink = (statBuf.st_mode & S_IFMT) == S_IFLNK
        if isSymlink {
            return .failed(reason: "Target path is a symbolic link; potential TOCTOU symlink substitution detected.")
        }

        // 4. Verify device and inode if known
        if let expectedDev = expectedDeviceId, statBuf.st_dev != expectedDev {
            return .failed(reason: "Filesystem device ID mismatch (expected \(expectedDev), found \(statBuf.st_dev))")
        }
        if let expectedIno = expectedInode, statBuf.st_ino != expectedIno {
            return .failed(reason: "Inode mismatch: file was replaced since scan (expected \(expectedIno), found \(statBuf.st_ino))")
        }

        // 5. Verify size has not ballooned unexpectedly
        if let expectedS = expectedSize, statBuf.st_size > expectedS * 2 && statBuf.st_size > 10 * 1024 * 1024 {
            return .failed(reason: "File size changed significantly since scan; concurrent writing suspected.")
        }

        let isDir = (statBuf.st_mode & S_IFMT) == S_IFDIR
        let meta = ValidatedFileMeta(
            deviceId: statBuf.st_dev,
            inode: statBuf.st_ino,
            size: Int64(statBuf.st_size),
            isDirectory: isDir
        )
        return .passed(meta: meta)
    }
}
