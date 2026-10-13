import Foundation

/// Command-line tools the app drives. They are not bundled;
/// install with `brew install colima docker docker-compose`.
enum ExternalTool: String, CaseIterable {
    case colima
    case docker

    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                              NSHomeDirectory() + "/.local/bin"]

    var url: URL? {
        // Apps launched from Finder get a minimal PATH, so look in the usual places first.
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in Self.searchPaths + envPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(rawValue)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static var missing: [ExternalTool] { allCases.filter { $0.url == nil } }

    /// PATH for child processes: colima needs limactl, docker needs its compose plugin.
    static var childPath: String {
        (searchPaths + ["/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
            + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")
    }
}

enum ToolError: LocalizedError {
    case notInstalled(ExternalTool)
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notInstalled(let tool): return tr("No se encuentra %@. Instálalo con: brew install %@", tool.rawValue, tool.rawValue)
        case .failed(let message): return message
        case .cancelled: return tr("Cancelado.")
        }
    }
}

/// Collects output lines from a background reader.
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }
}

/// Runs a tool, streaming its output line by line. Cancelling the Swift task
/// terminates the process.
final class ToolProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var errorTail: [String] = []

    /// Runs `tool` and returns its standard output lines.
    static func lines(_ tool: ExternalTool, _ arguments: [String],
                      environment: [String: String] = [:]) async throws -> [String] {
        let collector = LineCollector()
        try await run(tool, arguments, environment: environment) { collector.append($0) }
        return collector.all
    }

    /// Runs `tool` and calls `onLine` (on a background queue) for each stdout line,
    /// and for stderr lines too when `includeErrors` is set.
    static func run(_ tool: ExternalTool, _ arguments: [String],
                    environment: [String: String] = [:],
                    includeErrors: Bool = false,
                    onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        guard let executable = tool.url else { throw ToolError.notInstalled(tool) }
        let runner = ToolProcess()
        try await withTaskCancellationHandler {
            try await runner.start(executable: executable, arguments: arguments, environment: environment,
                                   includeErrors: includeErrors, onLine: onLine)
        } onCancel: {
            runner.process.terminate()
        }
    }

    private func start(executable: URL, arguments: [String], environment: [String: String],
                       includeErrors: Bool, onLine: @escaping @Sendable (String) -> Void) async throws {
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExternalTool.childPath
        for (key, value) in environment { env[key] = value }
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Blocking readers on background threads; both finish at EOF, after the process exits.
        let readers = DispatchGroup()
        read(out.fileHandleForReading, group: readers) { line in onLine(line) }
        read(err.fileHandleForReading, group: readers) { [weak self] line in
            self?.remember(line)
            if includeErrors { onLine(line) }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { [weak self] process in
                readers.notify(queue: .global()) {
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: ToolError.cancelled)
                    } else if process.terminationStatus != 0 {
                        let detail = self?.lastLines() ?? ""
                        continuation.resume(throwing: ToolError.failed(
                            detail.isEmpty
                                ? tr("%@ terminó con error %d.", executable.lastPathComponent, Int(process.terminationStatus))
                                : detail))
                    } else {
                        continuation.resume()
                    }
                }
            }
            do {
                try process.run()
                // Writers stay open in the child only.
                try? out.fileHandleForWriting.close()
                try? err.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func read(_ handle: FileHandle, group: DispatchGroup, onLine: @escaping (String) -> Void) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let index = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<index]
                    buffer.removeSubrange(buffer.startIndex...index)
                    onLine(Self.decode(lineData))
                }
            }
            if !buffer.isEmpty { onLine(Self.decode(buffer)) }
            group.leave()
        }
    }

    private static func decode(_ data: Data) -> String {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        return line
    }

    private func remember(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        errorTail.append(trimmed)
        if errorTail.count > 8 { errorTail.removeFirst() }
    }

    private func lastLines() -> String {
        lock.lock(); defer { lock.unlock() }
        return errorTail.joined(separator: "\n")
    }
}

/// Removes ANSI colour and cursor escape sequences.
func stripANSI(_ text: String) -> String {
    guard text.contains("\u{1B}") else { return text }
    return text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
}
