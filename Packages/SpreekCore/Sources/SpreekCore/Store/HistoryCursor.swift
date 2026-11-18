/// Backward / forward through the history from the popover and the floating bar.
///
/// Replaying a sentence moves it to the top of the history, so stepping walks a snapshot taken
/// when navigation starts instead of the live list.
public struct HistoryCursor<ID: Hashable> {
    /// Snapshot, most recently played first.
    public let items: [ID]
    /// Position in `items`; `-1` = before the newest (the current sentence isn't in the snapshot).
    public private(set) var index: Int

    public init(items: [ID], current: ID?) {
        self.items = items
        index = current.flatMap { items.firstIndex(of: $0) } ?? -1
    }

    public var current: ID? { items.indices.contains(index) ? items[index] : nil }

    /// Steps to the previous (older) item; `nil` at the oldest.
    public mutating func older() -> ID? {
        guard index + 1 < items.count else { return nil }
        index += 1
        return items[index]
    }

    /// Steps to the next (newer) item; `nil` at the newest.
    public mutating func newer() -> ID? {
        guard index > 0 else { return nil }
        index -= 1
        return items[index]
    }
}
