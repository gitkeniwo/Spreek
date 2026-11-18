import Foundation

/// Everything on a pasteboard: one entry per item, each mapping a type identifier to its data.
public struct PasteboardSnapshot: Sendable, Hashable {
    public var items: [[String: Data]]

    public init(items: [[String: Data]]) {
        self.items = items
    }
}

/// The parts of `NSPasteboard` the ⌘C fallback needs, so it can be tested with a fake.
@MainActor
public protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    /// Replaces the contents with `snapshot` (clearing it when the snapshot is empty).
    func restore(_ snapshot: PasteboardSnapshot)
    func readString() -> String?
}

/// Reads the selection by synthesizing ⌘C, leaving the user's clipboard as it was.
public enum CopyCapture {
    /// Snapshots `pasteboard`, calls `sendCopy`, waits up to `timeout` for the change count to
    /// move, reads the string and restores the snapshot.
    ///
    /// When ⌘C produced nothing (no change within `timeout`) the pasteboard is left untouched,
    /// so a restore can never clobber something that arrives later.
    @MainActor
    public static func capture(
        from pasteboard: some PasteboardAccess,
        timeout: Duration = .milliseconds(250),
        pollInterval: Duration = .milliseconds(10),
        sendCopy: () -> Void
    ) async -> String? {
        let snapshot = pasteboard.snapshot()
        let before = pasteboard.changeCount
        sendCopy()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while pasteboard.changeCount == before {
            guard clock.now < deadline, !Task.isCancelled else { return nil }
            try? await Task.sleep(for: pollInterval)
        }

        let text = pasteboard.readString()
        pasteboard.restore(snapshot)
        return text
    }
}
