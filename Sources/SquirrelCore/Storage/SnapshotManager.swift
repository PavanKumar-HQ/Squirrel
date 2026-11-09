import Foundation

/// Represents a local APFS snapshot (Time Machine or third-party backup).
public struct LocalSnapshot: Identifiable, Sendable, Codable, Equatable {
    public var id: String { name }
    public let name: String
    public let dateString: String
    public let isTimeMachine: Bool

    public init(name: String, dateString: String, isTimeMachine: Bool) {
        self.name = name
        self.dateString = dateString
        self.isTimeMachine = isTimeMachine
    }
}

/// Actor managing inspection and deletion of APFS local snapshots via tmutil.
public actor SnapshotManager {
    public static let shared = SnapshotManager()

    public init() {}

    /// Discovers local APFS snapshots pinning storage on the root mount.
    public func listLocalSnapshots() async -> [LocalSnapshot] {
        let result = await SafeProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tmutil"),
            arguments: ["listlocalsnapshots", "/"],
            timeoutSeconds: 5.0
        )

        guard result.isSuccess else {
            return []
        }

        var snapshots: [LocalSnapshot] = []
        let lines = result.stdout.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // tmutil outputs lines like:
            // com.apple.TimeMachine.2024-05-10-142030.local
            // Snapshots for volume /:
            if trimmed.contains("com.apple.TimeMachine.") {
                let parts = trimmed.components(separatedBy: "com.apple.TimeMachine.")
                if parts.count > 1 {
                    let datePart = parts[1].replacingOccurrences(of: ".local", with: "")
                    snapshots.append(LocalSnapshot(
                        name: trimmed,
                        dateString: datePart,
                        isTimeMachine: true
                    ))
                }
            } else if trimmed.contains("com.") || trimmed.contains(".") {
                // Third-party snapshots (Carbon Copy Cloner, Synology, etc.)
                let datePart = trimmed.components(separatedBy: ".").last ?? trimmed
                snapshots.append(LocalSnapshot(
                    name: trimmed,
                    dateString: datePart,
                    isTimeMachine: false
                ))
            }
        }

        return snapshots
    }

    /// Deletes a specific snapshot by date string using tmutil.
    public func deleteSnapshot(_ snapshot: LocalSnapshot) async -> Bool {
        guard !snapshot.dateString.isEmpty else { return false }
        let result = await SafeProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tmutil"),
            arguments: ["deletelocalsnapshots", snapshot.dateString],
            timeoutSeconds: 10.0
        )
        return result.isSuccess
    }
}
