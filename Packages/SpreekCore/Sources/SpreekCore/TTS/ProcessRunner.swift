import Foundation

public struct ProcessOutput: Sendable, Hashable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data

    public init(status: Int32, stdout: Data = Data(), stderr: Data = Data()) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs an external command. Abstracted so tests never spawn processes.
public protocol ProcessRunning: Sendable {
    /// Throws `TTSError.timedOut` (after terminating the process) when `timeout` elapses.
    func run(executable: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) async throws -> ProcessOutput
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let once = ResumeOnce()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessOutput, Error>) in
                once.set(continuation)
                // Drain pipes concurrently so large output (e.g. --list-voices) can't block the child.
                let group = DispatchGroup()
                let stdout = LockedBox(Data())
                let stderr = LockedBox(Data())
                group.enter()
                DispatchQueue.global().async {
                    stdout.value = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    stderr.value = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                process.terminationHandler = { finished in
                    group.notify(queue: .global()) {
                        once.resume(with: .success(ProcessOutput(
                            status: finished.terminationStatus, stdout: stdout.value, stderr: stderr.value
                        )))
                    }
                }
                do {
                    try process.run()
                } catch {
                    once.resume(with: .failure(error))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    // Resume before terminating: otherwise the termination handler can win the race
                    // and report the SIGTERM exit as a normal result.
                    once.resume(with: .failure(TTSError.timedOut(seconds: timeout)))
                    process.terminate()
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
            once.resume(with: .failure(CancellationError()))
        }
    }
}

/// Resumes a continuation at most once, from whichever path finishes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessOutput, Error>?
    private var pending: Result<ProcessOutput, Error>?
    private var done = false

    func set(_ continuation: CheckedContinuation<ProcessOutput, Error>) {
        lock.lock()
        if let pending, !done {
            done = true
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<ProcessOutput, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        guard let continuation else {
            // Cancelled before the continuation existed.
            pending = result
            lock.unlock()
            return
        }
        done = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    /// Reads and mutates in one critical section.
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.withLock { body(&stored) }
    }
}
