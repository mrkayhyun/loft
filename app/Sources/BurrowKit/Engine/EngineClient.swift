import Foundation

public enum EngineError: LocalizedError, Sendable {
    case notFound
    case failed(String)
    case exited(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "The Burrow engine could not be found. Reinstall Burrow."
        case .failed(let message):
            message
        case .exited(let status, let stderr):
            stderr.isEmpty ? "The engine stopped unexpectedly (\(status))." : stderr
        }
    }
}

/// Runs the bundled `burrow` binary and streams its NDJSON events.
public struct EngineClient: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// Locate the engine: `BURROW_ENGINE`, the app bundle, then a dev build.
    public static func locate(bundle: Bundle = .main) -> EngineClient? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["BURROW_ENGINE"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let bundled = bundle.url(forResource: "burrow", withExtension: nil) {
            candidates.append(bundled)
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Engine
            .deletingLastPathComponent() // BurrowKit
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // app
            .deletingLastPathComponent() // repo root
        for profile in ["release", "debug"] {
            candidates.append(repo.appending(path: "engine/target/\(profile)/burrow"))
        }
        return candidates
            .first { fm.isExecutableFile(atPath: $0.path) }
            .map(EngineClient.init(executable:))
    }

    /// Stream events. The stream finishes after the final report, throws on an
    /// engine `error` event, and terminates the process when cancelled.
    public func stream(_ arguments: [String], input: Data? = nil) -> AsyncThrowingStream<EngineEvent, Error> {
        let executable = self.executable
        return AsyncThrowingStream { continuation in
            let run = EngineRun(executable: executable, arguments: ["--json"] + arguments)
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await run.start(input: input) { event in
                        if case .error(let message) = event {
                            throw EngineError.failed(message)
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                run.terminate()
            }
        }
    }

    /// Collect every event of a short command.
    public func events(_ arguments: [String], input: Data? = nil) async throws -> [EngineEvent] {
        var collected: [EngineEvent] = []
        for try await event in stream(arguments, input: input) {
            collected.append(event)
        }
        return collected
    }
}

/// Owns one engine process. `Process` is not Sendable, so access is confined
/// to this box and guarded by a lock.
private final class EngineRun: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
    }

    func start(input: Data?, onEvent: (EngineEvent) throws -> Void) async throws {
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        lock.withLock {
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        }
        try lock.withLock { try process.run() }
        if let input {
            try stdin.fileHandleForWriting.write(contentsOf: input)
            try stdin.fileHandleForWriting.close()
        }
        for try await line in stdout.fileHandleForReading.bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }
            try onEvent(try EngineEvent.decode(line: Data(line.utf8)))
        }
        process.waitUntilExit()
        let status = process.terminationStatus
        guard status == 0 || Task.isCancelled else {
            let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw EngineError.exited(status, message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func terminate() {
        lock.withLock {
            if process.isRunning { process.terminate() }
        }
    }
}
