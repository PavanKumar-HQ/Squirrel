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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            var snapshots: [LocalSnapshot] = []
            let lines = output.components(separatedBy: .newlines)

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
                    snapshots.append(LocalSnapshot(
                        name: trimmed,
                        dateString: "APFS Snapshot",
                        isTimeMachine: false
                    ))
                }
            }

            return snapshots
        } catch {
            return []
        }
    }

    /// Deletes a specific snapshot by date string using tmutil.
    public func deleteSnapshot(_ snapshot: LocalSnapshot) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["deletelocalsnapshots", snapshot.dateString]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

