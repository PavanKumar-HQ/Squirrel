import Foundation
import Darwin

/// Result of a safe process execution.
public struct ProcessExecutionResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let didTimeout: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, didTimeout: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.didTimeout = didTimeout
    }

    public var isSuccess: Bool {
        exitCode == 0 && !didTimeout
    }
}

/// Thread-safe accumulator for process streaming output.
private final class LockedOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func extractString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Actor providing timeout-bounded, deadlock-free process execution for macOS CLI tools.
/// Prevents pipe buffer deadlock by draining stdout/stderr asynchronously while the process executes.
public actor SafeProcessRunner {
    public static let shared = SafeProcessRunner()

    public init() {}

    /// Executes an executable with arguments, draining output concurrently and enforcing a strict timeout.
    public static func run(
        executableURL: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval = 10.0,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async -> ProcessExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let wd = workingDirectory {
            process.currentDirectoryURL = wd
        }
        if let env = environment {
            process.environment = env
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let stdoutBuffer = LockedOutputBuffer()
        let stderrBuffer = LockedOutputBuffer()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF reached: must remove handler to prevent dispatch source tight loop
                handle.readabilityHandler = nil
            } else {
                stdoutBuffer.append(chunk)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF reached: must remove handler to prevent dispatch source tight loop
                handle.readabilityHandler = nil
            } else {
                stderrBuffer.append(chunk)
            }
        }

        do {
            try process.run()
            // Crucial POSIX fix: parent must close write handles so child holds the only write end.
            // This prevents readDataToEndOfFile() from hanging indefinitely waiting for EOF.
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ProcessExecutionResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var timedOut = false

        while process.isRunning {
            if Date() > deadline {
                timedOut = true
                process.terminate()
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms check
        }

        if timedOut {
            // Give 100ms for SIGTERM, then force SIGKILL
            for _ in 0..<5 {
                if !process.isRunning { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                for _ in 0..<5 {
                    if !process.isRunning { break }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        }

        // Clean up readability handlers first to prevent deadlocks
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        // Drain any remaining non-blocking available bytes without hanging
        let remainingOut = outPipe.fileHandleForReading.availableData
        let remainingErr = errPipe.fileHandleForReading.availableData

        if !remainingOut.isEmpty { stdoutBuffer.append(remainingOut) }
        if !remainingErr.isEmpty { stderrBuffer.append(remainingErr) }

        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()

        let exitCode = process.isRunning ? -1 : process.terminationStatus

        return ProcessExecutionResult(
            exitCode: exitCode,
            stdout: stdoutBuffer.extractString(),
            stderr: stderrBuffer.extractString(),
            didTimeout: timedOut
        )
    }
}
