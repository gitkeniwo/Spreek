#if DEBUG
import Foundation
import SpreekCore
import SwiftData

/// Sample folders, tags and sentences for trying the
/// UI without speaking dozens of sentences first. Debug builds only; release builds seed nothing.
@MainActor
enum SampleLibrary {
    private struct SampleSentence {
        let language: LanguageCode
        let text: String
        let favorite: Bool
        /// 0 = today, 1 = yesterday.
        let daysAgo: Int
        let folder: String?
        let tags: [String]
        var note = ""
        var sourceApp: String?
        var sourceURL: String?
        /// Plays per day, oldest first, ending on `daysAgo`.
        let plays: [Int]
    }

    private static let folders: [(name: String, color: String, symbol: String, language: LanguageCode?, note: String)] = [
        ("Reddit", "orange", "bubble.left.fill", .nl, "来自 *r/thenetherlands* 的句子。很多是**口语和粗话**，自己用之前先确认语气。"),
        ("Werk & post", "blue", "briefcase.fill", .nl, ""),
        ("Duits A2", "green", "book.fill", .de, ""),
        ("Anime", "pink", "sparkles", .ja, ""),
        ("Podcasts", "purple", "music.note", nil, ""),
    ]

    private static let bundleIDs = ["Safari": "com.apple.Safari", "Mail": "com.apple.mail"]

    private static let tags: [(name: String, color: String)] = [
        ("informeel", "pink"), ("uitdrukking", "blue"), ("grammatica", "green"), ("keigo", "yellow"),
    ]

    private static let sentences: [SampleSentence] = [
        SampleSentence(
            language: .nl, text: "Dit. Gezeik blijft maar doorgaan.", favorite: true, daysAgo: 0,
            folder: "Reddit", tags: ["informeel", "uitdrukking"],
            note: """
            **Dit.** — 单独成句，是 Reddit 上表示“同意楼上”的说法，相当于英语的 *This.*

            **gezeik** (het) — 口语、偏粗俗：没完没了的抱怨、破事。来自动词 *zeiken*。

            **blijft maar doorgaan** — *blijven* + 不定式表示“一直在……”；这里的 *maar* 加强了“没完没了、让人烦”的语气。整句大意：“对。这破事就是没完没了。”
            """,
            sourceApp: "Safari",
            sourceURL: "https://www.reddit.com/r/thenetherlands/comments/1g4k2xq/gezeik_over_de_ns_blijft_maar_doorgaan_wat_vinden_jullie/",
            plays: [0, 1, 0, 2, 1, 1, 2]
        ),
        SampleSentence(language: .nl, text: "Ik geloof het pas als ie klaar is.", favorite: false, daysAgo: 0, folder: "Reddit", tags: ["informeel"], plays: [1, 3, 0, 4, 6, 2, 9]),
        SampleSentence(language: .nl, text: "Zo activeer je Mijn Albert Heijn Premium", favorite: false, daysAgo: 0, folder: "Werk & post", tags: [], sourceApp: "Mail", plays: [0, 2, 5, 3, 1, 7, 4]),
        SampleSentence(
            language: .de, text: "Das kommt ganz darauf an.", favorite: true, daysAgo: 0, folder: "Duits A2", tags: ["uitdrukking"],
            note: "*Es kommt darauf an* = het hangt ervan af. **ganz** maakt het sterker.", plays: [3, 1, 4, 2, 6, 3, 5]
        ),
        SampleSentence(
            language: .nl, text: "Ja, nee, dat valt mee hoor.", favorite: true, daysAgo: 1, folder: "Reddit", tags: ["uitdrukking"],
            note: "**Ja, nee** — typisch Nederlands: *ja* erkent, *nee* ontkent het probleem.", plays: [6, 4, 8, 3, 2, 5]
        ),
        SampleSentence(language: .nl, text: "Ah toe, geef nou.", favorite: false, daysAgo: 1, folder: nil, tags: ["informeel"], plays: [2, 0, 3, 5, 1, 4]),
        SampleSentence(language: .ja, text: "よろしくお願いします。", favorite: false, daysAgo: 1, folder: "Anime", tags: ["keigo"], plays: [4, 2, 0, 1, 3, 6]),
        SampleSentence(
            language: .ko, text: "개맛도리야", favorite: true, daysAgo: 1, folder: nil, tags: ["informeel"],
            note: "*개* + *맛도리*: slang voor „echt superlekker”.", plays: [1, 1, 2, 0, 4, 2]
        ),
        SampleSentence(language: .de, text: "Ich hätte gern einen Kaffee.", favorite: false, daysAgo: 1, folder: "Duits A2", tags: ["grammatica"], plays: [0, 3, 1, 2, 2, 5]),
        // Older rows (5b): fill the 30-day chart and show the new languages.
        SampleSentence(
            language: .enUS, text: "That's a whole different kettle of fish.", favorite: true, daysAgo: 3, folder: nil, tags: ["uitdrukking"],
            sourceApp: "Mail", plays: [1, 0, 2, 3, 0, 1, 4, 2, 0, 0, 3, 1, 2, 5, 1, 0, 2, 1, 3, 0, 1, 2]
        ),
        SampleSentence(
            language: .zhCN, text: "这件事说来话长。", favorite: false, daysAgo: 6, folder: nil, tags: [],
            plays: [2, 1, 0, 4, 2, 1, 0, 3, 2, 6, 1, 0, 2, 3, 1, 2, 0, 1, 2, 4]
        ),
        SampleSentence(
            language: .fr, text: "Ça ne vaut pas le coup.", favorite: true, daysAgo: 12, folder: nil, tags: ["informeel"],
            plays: [0, 2, 1, 3, 0, 2, 1, 1, 4, 2, 0, 1, 3, 2, 1]
        ),
        SampleSentence(
            language: .ja, text: "お疲れ様でした。", favorite: true, daysAgo: 20, folder: "Anime", tags: ["keigo"],
            plays: [3, 1, 2, 0, 5, 2, 1, 3]
        ),
    ]

    /// Sentences from a phrase to a paragraph, one per detail-title size step, plus wide scripts.
    private static let longSentences: [SampleSentence] = [
        SampleSentence(
            language: .nl, text: "Goedemorgen, zullen we straks samen koffie drinken bij de bakker?",
            favorite: false, daysAgo: 0, folder: nil, tags: [], plays: [1]
        ),
        SampleSentence(
            language: .nl,
            text: "Als je morgen toch naar de stad gaat, kun je dan even langs de bibliotheek fietsen om mijn boeken terug te brengen?",
            favorite: false, daysAgo: 0, folder: nil, tags: [], plays: [2]
        ),
        SampleSentence(
            language: .nl,
            text: "De gemeente heeft besloten dat de oude brug over het kanaal volgend voorjaar wordt vervangen, waardoor fietsers en voetgangers maandenlang een omweg van bijna twee kilometer moeten maken.",
            favorite: false, daysAgo: 0, folder: nil, tags: [], plays: [1]
        ),
        SampleSentence(
            language: .de,
            text: "Obwohl der Zug wegen einer Signalstörung fast eine Stunde Verspätung hatte, kamen wir noch rechtzeitig zum Konzert, weil die Veranstalter den Beginn freundlicherweise um zwanzig Minuten verschoben hatten, damit alle Gäste ihre Plätze finden konnten.",
            favorite: false, daysAgo: 0, folder: nil, tags: [], plays: [1]
        ),
        SampleSentence(
            language: .enUS,
            text: "When the committee finally published its report, it turned out that most of the recommendations had already been put into practice by the local volunteers, who had spent the previous two winters quietly repairing the footpaths, replanting the hedgerows and persuading the bus company to add an early-morning service for people working in the harbour, all without asking anyone for permission or, for that matter, for money.",
            favorite: false, daysAgo: 0, folder: nil, tags: [], plays: [1]
        ),
        SampleSentence(
            language: .ja,
            text: "駅前の小さな本屋は来月で閉店するそうですが、店主は最後の日まで毎朝いつもと同じ時間にシャッターを開けると話していました。",
            favorite: false, daysAgo: 0, folder: "Anime", tags: [], plays: [1]
        ),
        SampleSentence(
            language: .zhCN,
            text: "虽然天气预报说下午会下大雨，但我们还是决定按原计划去爬山，结果一路上阳光明媚，反而是回到家以后才开始打雷。",
            favorite: false, daysAgo: 0, folder: nil, tags: [], plays: [1]
        ),
        SampleSentence(
            language: .ko,
            text: "오늘 회의에서 결정된 내용은 내일 아침까지 정리해서 팀 전체에 공유하겠습니다.",
            favorite: false, daysAgo: 0, folder: nil, tags: [], plays: [1]
        ),
    ]

    /// Adds `longSentences` to any library, the real one too, skipping ones already there:
    /// `-SpreekDebugSeedLongSentences YES`.
    static func seedLongSentences(into library: LibraryStore) {
        let existing = Set((try? library.context.fetch(FetchDescriptor<Sentence>()))?.map(\.normalizedText) ?? [])
        let now = Date()
        for (index, sample) in longSentences.enumerated()
        where !existing.contains(LibraryStore.normalizedKey(for: sample.text)) {
            let date = now.addingTimeInterval(-Double(index + 1) * 60)
            let sentence = Sentence(
                text: sample.text, normalizedText: LibraryStore.normalizedKey(for: sample.text), language: sample.language,
                createdAt: date, voiceID: sample.language.info.defaultEdgeVoice
            )
            library.context.insert(sentence)
            sentence.lastPlayedAt = date
            sentence.playCount = 1
            library.context.insert(PlayEvent(sentence: sentence, date: date))
        }
        try? library.context.save()
    }

    /// `count` generated sentences with five plays each over the last 60 days, for memory and
    /// speed checks on a big library: `-SpreekDebugSeedBulk 5000` (use with an in-memory library).
    static func seedBulk(_ count: Int, into library: LibraryStore) {
        let now = Date()
        let languages: [LanguageCode] = [.nl, .de, .ja]
        for index in 0..<count {
            let language = languages[index % languages.count]
            let text = "Voorbeeldzin nummer \(index): een gewone zin van een redelijke lengte om te oefenen."
            let date = now.addingTimeInterval(-Double(index) * 997)
            let sentence = Sentence(
                text: text, normalizedText: LibraryStore.normalizedKey(for: text), language: language,
                createdAt: date, voiceID: language.info.defaultEdgeVoice
            )
            library.context.insert(sentence)
            sentence.lastPlayedAt = date
            sentence.playCount = 5
            for play in 0..<5 {
                library.context.insert(PlayEvent(sentence: sentence, date: date.addingTimeInterval(-Double(play) * 86_400 * 12)))
            }
        }
        try? library.context.save()
    }

    /// Inserts the sample library. Returns `false` (and changes nothing) if it's already there.
    @discardableResult
    static func seed(into library: LibraryStore) -> Bool {
        guard !library.folders().contains(where: { $0.name == "Reddit" }) else { return false }
        let context = library.context
        let calendar = library.calendar
        let now = Date()
        let today = calendar.startOfDay(for: now)

        var foldersByName: [String: Folder] = [:]
        for (index, sample) in folders.enumerated() {
            let folder = library.createFolder(name: sample.name, color: sample.color, symbol: sample.symbol, language: sample.language)
            folder.createdAt = calendar.date(byAdding: .day, value: -42 + index, to: today) ?? now
            folder.note = sample.note
            if sample.name == "Reddit" { folder.speed = 0.9 }
            foldersByName[sample.name] = folder
        }
        var tagsByName: [String: Tag] = [:]
        for sample in tags {
            tagsByName[sample.name] = library.createTag(name: sample.name, color: sample.color)
        }

        for (index, sample) in (sentences + longSentences).enumerated() {
            var events: [Date] = []
            for (offset, count) in sample.plays.enumerated() {
                let daysAgo = sample.daysAgo + sample.plays.count - 1 - offset
                for play in 0..<count {
                    events.append(time(daysAgo: daysAgo, slot: play + index, today: today, now: now, calendar: calendar))
                }
            }
            if events.isEmpty { events.append(time(daysAgo: sample.daysAgo, slot: index, today: today, now: now, calendar: calendar)) }
            events.sort()

            let sentence = Sentence(
                text: sample.text, normalizedText: LibraryStore.normalizedKey(for: sample.text), language: sample.language,
                createdAt: events[0], voiceID: sample.language.info.defaultEdgeVoice,
                sourceApp: sample.sourceApp, sourceURL: sample.sourceURL,
                sourceBundleID: sample.sourceApp.flatMap { bundleIDs[$0] }
            )
            context.insert(sentence)
            sentence.lastPlayedAt = events[events.count - 1]
            sentence.playCount = events.count
            sentence.note = sample.note
            if sample.favorite {
                sentence.isFavorite = true
                sentence.favoritedAt = sentence.lastPlayedAt
            }
            sentence.folder = sample.folder.flatMap { foldersByName[$0] }
            sentence.tags = sample.tags.compactMap { tagsByName[$0] }
            for date in events { context.insert(PlayEvent(sentence: sentence, date: date)) }
        }
        try? context.save()
        return true
    }

    /// A plausible play time: earlier today counting back from now, or daytime on past days.
    private static func time(daysAgo: Int, slot: Int, today: Date, now: Date, calendar: Calendar) -> Date {
        if daysAgo == 0 {
            return max(today, now.addingTimeInterval(-Double(slot + 1) * 7 * 60))
        }
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        return day.addingTimeInterval(9 * 3600 + Double(slot % 40) * 17 * 60)
    }
}
#endif
