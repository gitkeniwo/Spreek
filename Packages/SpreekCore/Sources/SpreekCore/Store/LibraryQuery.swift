import Foundation

/// Which sentences a dashboard list shows before searching.
public enum LibraryScope {
    case history
    case favorites
    case folder(Folder)
    case tag(Tag)
}

/// "7d" / "30d" / "All" next to the dashboard search field.
public enum LibraryRange: String, CaseIterable, Codable, Sendable {
    case week, month, all

    /// Days including today; `nil` = no limit.
    public var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .all: nil
        }
    }

    /// Mono label in the search field.
    public var shortLabel: String {
        switch self {
        case .week: "7d"
        case .month: "30d"
        case .all: "All"
        }
    }

}

/// Footer chart window length, independent of the list's `LibraryRange`.
public enum ChartRange: Int, CaseIterable, Codable, Sendable {
    case days30 = 30
    case days90 = 90

    public var days: Int { rawValue }
    public var title: String { "Last \(rawValue) days" }
}

/// One chart column.
public struct DailyActivity: Sendable, Hashable, Identifiable {
    /// Start of the day.
    public let day: Date
    public let plays: Int
    public let saves: Int
    public var id: Date { day }

    public init(day: Date, plays: Int, saves: Int) {
        self.day = day
        self.plays = plays
        self.saves = saves
    }
}

/// The footer chart's data for one window: one column per day, oldest first.
public struct ActivitySummary: Sendable, Hashable {
    public let window: DateInterval
    public let days: [DailyActivity]

    public init(window: DateInterval, days: [DailyActivity]) {
        self.window = window
        self.days = days
    }

    public var totalPlays: Int { days.reduce(0) { $0 + $1.plays } }
    public var totalSaves: Int { days.reduce(0) { $0 + $1.saves } }
    /// Both halves scale to the busiest day in range (at least 1).
    public var scale: Int { max(days.map { max($0.plays, $0.saves) }.max() ?? 0, 1) }
}

/// List order. The same date also groups the day headers and drives the 7d / 30d range.
public enum LibrarySort: String, CaseIterable, Codable, Sendable {
    /// When the sentence was first recorded (`createdAt`), newest first. Default.
    case firstRecorded
    /// When it was last played (`lastPlayedAt`), newest first.
    case lastPlayed

    public var title: String {
        switch self {
        case .firstRecorded: "First Recorded"
        case .lastPlayed: "Last Played"
        }
    }

    public func date(of sentence: Sentence) -> Date {
        switch self {
        case .firstRecorded: sentence.createdAt
        case .lastPlayed: sentence.lastPlayedAt
        }
    }
}

/// Search field state: text, language filter, range and order.
public struct LibraryQuery: Sendable, Hashable {
    /// Matched against the sentence and its note, ignoring case and diacritics.
    public var text: String
    /// Matched against `Sentence.effectiveLanguage`; `nil` = all languages.
    public var language: LanguageCode?
    public var range: LibraryRange
    public var sort: LibrarySort

    public init(text: String = "", language: LanguageCode? = nil, range: LibraryRange = .all, sort: LibrarySort = .firstRecorded) {
        self.text = text
        self.language = language
        self.range = range
        self.sort = sort
    }
}

extension LibraryStore {
    /// The scope's sentences that match `query`, newest first by `query.sort`.
    public func sentences(in scope: LibraryScope, matching query: LibraryQuery = LibraryQuery()) -> [Sentence] {
        let base: [Sentence] = switch scope {
        case .history: recent()
        case .favorites: favorites()
        case .folder(let folder): sentences(in: folder)
        case .tag(let tag): sentences(with: tag)
        }
        let sort = query.sort
        // Stable: ties keep the scope's own (last played) order.
        let sorted = base.enumerated().sorted { a, b in
            let (da, db) = (sort.date(of: a.element), sort.date(of: b.element))
            return da != db ? da > db : a.offset < b.offset
        }.map(\.element)
        return filter(sorted, by: query)
    }

    /// Applies text, language and range filters, keeping the order.
    public func filter(_ sentences: [Sentence], by query: LibraryQuery) -> [Sentence] {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let since = query.range.days.map { lastDays($0).start }
        return sentences.filter { sentence in
            if let language = query.language, sentence.effectiveLanguage != language { return false }
            if let since, query.sort.date(of: sentence) < since { return false }
            guard !needle.isEmpty else { return true }
            return Self.matches(sentence.text, needle) || Self.matches(NoteFormat.plainText(fromMarkdown: sentence.note), needle)
        }
    }

    /// Groups sentences by their `sort` date (last played by default), keeping their order
    /// inside a day. Days come out newest first: "Today", "Yesterday", then dates.
    public func dayBuckets(_ sentences: [Sentence], by sort: LibrarySort = .lastPlayed) -> [DayBucket] {
        let today = calendar.startOfDay(for: now())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var order: [Date] = []
        var byDay: [Date: [Sentence]] = [:]
        for sentence in sentences {
            let day = calendar.startOfDay(for: sort.date(of: sentence))
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(sentence)
        }
        return order.sorted(by: >).map { day in
            let label: DayBucket.Label = day == today ? .today : day == yesterday ? .yesterday : .date(day)
            return DayBucket(day: day, label: label, sentences: byDay[day] ?? [])
        }
    }

    /// Plays per day for the row mini bars: `days` entries ending today, oldest first.
    public func miniBars(for sentence: Sentence, days: Int = 7) -> [Int] {
        let window = lastDays(days)
        let first = window.start
        var counts = Array(repeating: 0, count: max(days, 1))
        for event in sentence.playEvents where event.date >= first && event.date <= window.end {
            let index = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: event.date)).day ?? -1
            if counts.indices.contains(index) { counts[index] += 1 }
        }
        return counts
    }

    /// The footer chart window: `days` days ending today, moved back `offset` whole windows
    /// (`offset` 0 = the current window; past windows end at the end of their last day).
    public func chartWindow(days: Int, offset: Int) -> DateInterval {
        let current = lastDays(days)
        guard offset > 0,
              let start = calendar.date(byAdding: .day, value: -days * offset, to: current.start),
              let end = calendar.date(byAdding: .day, value: days, to: start)
        else { return current }
        return DateInterval(start: start, end: end.addingTimeInterval(-1))
    }

    /// Chart data for `range`, `offset` whole windows back (0 = ending today).
    public func activity(_ range: ChartRange, offset: Int = 0) -> ActivitySummary {
        let window = chartWindow(days: range.days, offset: offset)
        let days = dailyCounts(range: window).map { DailyActivity(day: $0.day, plays: $0.plays, saves: $0.saves) }
        return ActivitySummary(window: window, days: days)
    }

    /// Changes the detected language (used when the sentence isn't in a folder).
    public func setLanguage(_ language: LanguageCode, for sentence: Sentence) {
        sentence.language = language
        save()
    }
}
