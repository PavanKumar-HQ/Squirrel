import Foundation
import Darwin

/// Extended attribute definitions for Darwin APFS clone detection (sys/attr.h).
/// Ported from Mole's `clone_darwin.go` to provide kernel-level Copy-on-Write (CoW)
/// duplicate detection and avoid double-counting zero-cost APFS cloned storage.
public struct APFSCloneDetector {
    private static let attrCmnextCloneID: UInt32 = 0x00000100
    private static let attrCmnextExtFlags: UInt32 = 0x00000200
    private static let efSharesAllBlocks: UInt64 = 0x00000040

    public struct CloneInfo: Sendable, Equatable {
        public let isCloned: Bool
        public let cloneId: UInt64
        public let sharesAllBlocks: Bool
        public let isHardlink: Bool
        public let inode: UInt64

        public init(isCloned: Bool, cloneId: UInt64, sharesAllBlocks: Bool, isHardlink: Bool, inode: UInt64) {
            self.isCloned = isCloned
            self.cloneId = cloneId
            self.sharesAllBlocks = sharesAllBlocks
            self.isHardlink = isHardlink
            self.inode = inode
        }
    }

    /// Queries Darwin kernel getattrlist to inspect whether a file is an APFS CoW clone
    /// or a POSIX hardlink that shares physical blocks with another file.
    public static func inspectClone(at path: String) -> CloneInfo {
        var statBuf = stat()
        guard lstat(path, &statBuf) == 0 else {
            return CloneInfo(isCloned: false, cloneId: 0, sharesAllBlocks: false, isHardlink: false, inode: 0)
        }

        let isHardlink = statBuf.st_nlink > 1
        let inode = UInt64(statBuf.st_ino)

        // Only regular files on APFS can be CoW clones
        guard (statBuf.st_mode & S_IFMT) == S_IFREG else {
            return CloneInfo(isCloned: false, cloneId: 0, sharesAllBlocks: false, isHardlink: isHardlink, inode: inode)
        }

        // Setup getattrlist attrlist for extended common attributes
        var alist = attrlist()
        alist.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        alist.forkattr = attrCmnextCloneID | attrCmnextExtFlags

        // Buffer: UInt32 length + UInt64 cloneId + UInt64 extFlags = 20 bytes
        var buffer = (length: UInt32(0), cloneId: UInt64(0), extFlags: UInt64(0))

        let rc = getattrlist(
            path,
            &alist,
            &buffer,
            MemoryLayout.size(ofValue: buffer),
            UInt32(FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED)
        )

        guard rc == 0, buffer.length >= 20 else {
            return CloneInfo(isCloned: false, cloneId: 0, sharesAllBlocks: false, isHardlink: isHardlink, inode: inode)
        }

        let cloneId = buffer.cloneId
        let sharesAll = (buffer.extFlags & efSharesAllBlocks) != 0
        let isCloned = cloneId != 0 || sharesAll

        return CloneInfo(
            isCloned: isCloned,
            cloneId: cloneId,
            sharesAllBlocks: sharesAll,
            isHardlink: isHardlink,
            inode: inode
        )
    }
}

