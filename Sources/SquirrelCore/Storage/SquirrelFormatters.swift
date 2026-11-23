import Foundation

/// High-precision byte formatter tailored for macOS storage optimization.
/// Displays precise fractional values with MB continuation for GB quantities
/// so users always see the exact live byte changes (e.g. "1.42 GB (1,454.2 MB)").
public enum SquirrelFormatters {

    /// Formats bytes into human-readable representation with high precision and MB continuation for GB values.
    /// Examples:
    /// - 1,524,682,752 bytes -> "1.42 GB (1,454.1 MB)"
    /// - 149,422,080 bytes  -> "142.50 MB"
    /// - 425,984 bytes      -> "416.0 KB"
    /// - 0 bytes            -> "0 B"
    public static func formatPrecise(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let d = Double(bytes)
        let kb = d / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        let tb = gb / 1024.0

        if tb >= 1.0 {
            return String(format: "%.2f TB (%.1f GB)", tb, gb)
        } else if gb >= 1.0 {
            return String(format: "%.2f GB (%.1f MB)", gb, mb)
        } else if mb >= 1.0 {
            return String(format: "%.2f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    /// Single compact unit with 2-decimal precision (e.g. for narrow table cells).
    /// Examples:
    /// - 1,524,682,752 bytes -> "1.42 GB"
    /// - 149,422,080 bytes  -> "142.50 MB"
    /// - 425,984 bytes      -> "416.0 KB"
    public static func formatExactSingle(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let d = Double(bytes)
        let kb = d / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        let tb = gb / 1024.0

        if tb >= 1.0 {
            return String(format: "%.2f TB", tb)
        } else if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.2f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    /// Explicit dual representation with both GB and MB shown with 2-decimal accuracy.
    /// Example: "1.42 GB • 1,454.18 MB"
    public static func formatDualGBandMB(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let d = Double(bytes)
        let mb = d / (1024.0 * 1024.0)
        let gb = mb / 1024.0

        if gb >= 1.0 {
            return String(format: "%.2f GB • %.2f MB", gb, mb)
        } else {
            return String(format: "%.2f MB", mb)
        }
    }
}

