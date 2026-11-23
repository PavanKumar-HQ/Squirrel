import Foundation

/// Represents an active network listening port or background server process on macOS.
public struct ListeningPortRecord: Identifiable, Sendable, Equatable {
    public var id: String { "\(pid)_\(port)_\(protocolType)" }
    public let command: String
    public let pid: Int32
    public let user: String
    public let port: Int
    public let protocolType: String // "TCP" or "UDP"
    public let address: String
    public let isSystemProtected: Bool
    public let isDevServer: Bool

    public init(
        command: String,
        pid: Int32,
        user: String,
        port: Int,
        protocolType: String,
        address: String,
        isSystemProtected: Bool = false,
        isDevServer: Bool = false
    ) {
        self.command = command
        self.pid = pid
        self.user = user
        self.port = port
        self.protocolType = protocolType
        self.address = address
        self.isSystemProtected = isSystemProtected
        self.isDevServer = isDevServer
    }
}

/// Discovers and terminates orphaned dev servers and active listening ports.
/// Directly queries macOS `lsof` with strict protections for Apple system daemons.
public actor ServerPortManager {
    public static let shared = ServerPortManager()

    /// Apple system daemons and critical macOS services that MUST NOT be killed.
    private static let protectedCommands: Set<String> = [
        "launchd", "kernel_task", "rapportd", "ControlCenter", "ControlCe",
        "AirPlayXPCHelper", "sharingd", "identityservicesd", "mDNSResponder",
        "netbiosd", "SystemUIServer", "WindowServer", "loginwindow", "Finder"
    ]

    /// Known web/dev server process names.
    private static let devCommands: Set<String> = [
        "node", "next", "vite", "webpack", "npm", "yarn", "pnpm", "bun",
        "python", "python3", "flask", "django", "uvicorn", "gunicorn",
        "ruby", "rails", "puma", "go", "main", "cargo", "rust",
        "docker", "com.docker.backend", "nginx", "caddy", "postgres", "redis-server"
    ]

    public init() {}

    /// Discovers all currently listening TCP/UDP ports.
    public func listListeningPorts() async -> [ListeningPortRecord] {
        let outcome = await SafeProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"],
            timeoutSeconds: 4.0
        )

        guard outcome.isSuccess else { return [] }

        var records: [ListeningPortRecord] = []
        let lines = outcome.stdout.components(separatedBy: .newlines)

        // Header: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        for line in lines.dropFirst() {
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard tokens.count >= 9 else { continue }

            let command = tokens[0]
            guard let pid = Int32(tokens[1]) else { continue }
            let user = tokens[2]
            let node = tokens[8] // e.g., "*:7000" or "127.0.0.1:3000"

            guard let colonIdx = node.lastIndex(of: ":") else { continue }
            let portStr = String(node[node.index(after: colonIdx)...])
            guard let port = Int(portStr) else { continue }
            let address = String(node[..<colonIdx])

            let isProtected = Self.protectedCommands.contains(command) || user == "root"
            let isDev = Self.devCommands.contains(command.lowercased()) || (port >= 3000 && port <= 9999)

            records.append(ListeningPortRecord(
                command: command,
                pid: pid,
                user: user,
                port: port,
                protocolType: "TCP",
                address: address,
                isSystemProtected: isProtected,
                isDevServer: isDev
            ))
        }

        // Return deduplicated by id and sorted by port number
        var seen = Set<String>()
        return records.filter { record in
            if seen.contains(record.id) { return false }
            seen.insert(record.id)
            return true
        }.sorted { $0.port < $1.port }
    }

    /// Kills an orphaned or user-selected server process by PID.
    /// Strictly refuses to kill protected Apple system daemons or PID <= 1.
    public func terminateProcess(pid: Int32, command: String) -> (success: Bool, message: String) {
        guard pid > 1 else {
            return (false, "Cannot terminate PID <= 1.")
        }
        guard !Self.protectedCommands.contains(command) else {
            return (false, "Cannot terminate system daemon '\(command)' (Protected by macOS).")
        }

        // First send SIGTERM
        let termRes = kill(pid, SIGTERM)
        if termRes == 0 {
            // Wait up to 100ms
            usleep(100_000)
            if kill(pid, 0) != 0 {
                return (true, "Process \(command) (PID \(pid)) terminated.")
            }
        }

        // Force SIGKILL
        let killRes = kill(pid, SIGKILL)
        if killRes == 0 {
            return (true, "Process \(command) (PID \(pid)) forcefully terminated.")
        } else {
            return (false, "Failed to terminate process (code \(errno)).")
        }
    }
}

