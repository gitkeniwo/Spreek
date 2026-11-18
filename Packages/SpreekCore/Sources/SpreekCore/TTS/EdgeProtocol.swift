import Foundation

/// The Edge read-aloud service: the unofficial endpoint Microsoft Edge's "Read aloud" uses.
/// Values match edge-tts 7.3.1; when Microsoft changes them, this is the place to update.
public enum EdgeEndpoint {
    static let host = "speech.platform.bing.com"
    static let basePath = "/consumer/speech/synthesize/readaloud"
    static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4" // gitleaks:allow (public client token shared by every Edge client)
    static let chromiumFullVersion = "143.0.3650.75"
    static var chromiumMajorVersion: String { String(chromiumFullVersion.prefix { $0 != "." }) }
    static var secMSGECVersion: String { "2-\(chromiumFullVersion)" }
    static let outputFormat = "audio-24khz-48kbitrate-mono-mp3"
    /// The output format is constant-bitrate, so audio bytes convert exactly to time.
    static let bitsPerSecond = 48_000
    static let ticksPerSecond = 10_000_000.0
    /// Maximum escaped text per SSML request.
    public static let maxChunkBytes = 4096

    public static func synthesisURL(connectionID: String, token: String) -> URL {
        url(scheme: "wss", path: "/edge/v1", items: [
            URLQueryItem(name: "TrustedClientToken", value: trustedClientToken),
            URLQueryItem(name: "ConnectionId", value: connectionID),
            URLQueryItem(name: "Sec-MS-GEC", value: token),
            URLQueryItem(name: "Sec-MS-GEC-Version", value: secMSGECVersion),
        ])
    }

    public static func voicesURL(token: String) -> URL {
        url(scheme: "https", path: "/voices/list", items: [
            URLQueryItem(name: "trustedclienttoken", value: trustedClientToken),
            URLQueryItem(name: "Sec-MS-GEC", value: token),
            URLQueryItem(name: "Sec-MS-GEC-Version", value: secMSGECVersion),
        ])
    }

    private static func url(scheme: String, path: String, items: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = basePath + path
        components.queryItems = items
        return components.url!
    }

    static var userAgent: String {
        let major = chromiumMajorVersion
        return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/\(major).0.0.0 Safari/537.36 Edg/\(major).0.0.0"
    }

    /// Headers for the WebSocket handshake. `muid` is a random 32-hex cookie per connection.
    /// (URLSession adds the `Sec-WebSocket-*` headers itself.)
    public static func socketHeaders(muid: String) -> [String: String] {
        [
            "Pragma": "no-cache",
            "Cache-Control": "no-cache",
            "Origin": "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
            "User-Agent": userAgent,
            "Accept-Language": "en-US,en;q=0.9",
            "Cookie": "muid=\(muid);",
        ]
    }

    public static func voiceListHeaders(muid: String) -> [String: String] {
        let major = chromiumMajorVersion
        return [
            "Authority": host,
            "Sec-CH-UA": "\" Not;A Brand\";v=\"99\", \"Microsoft Edge\";v=\"\(major)\", \"Chromium\";v=\"\(major)\"",
            "Sec-CH-UA-Mobile": "?0",
            "Accept": "*/*",
            "Sec-Fetch-Site": "none",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "User-Agent": userAgent,
            "Accept-Language": "en-US,en;q=0.9",
            "Cookie": "muid=\(muid);",
        ]
    }

    /// 32 uppercase hex digits.
    static func randomHexID(uppercase: Bool = true) -> String {
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return uppercase ? hex : hex.lowercased()
    }
}

/// Builds the text messages sent to the service.
public enum EdgeMessages {
    /// JavaScript-style UTC date (`Wed Oct 15 2026 01:02:03 GMT+0000 (Coordinated Universal Time)`).
    public static func timestamp(_ date: Date) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(weekday: .abbreviated) \(month: .abbreviated) \(day: .twoDigits) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
                locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt, calendar: Calendar(identifier: .gregorian)
            )
        ) + " GMT+0000 (Coordinated Universal Time)"
    }

    /// `speech.config`: MP3 output with word or sentence boundary metadata. Some voices only work
    /// with sentence boundaries (the edge-tts CLI asks for those).
    public static func speechConfig(date: Date, wordBoundaries: Bool = true) -> String {
        "X-Timestamp:\(timestamp(date))\r\n"
            + "Content-Type:application/json; charset=utf-8\r\n"
            + "Path:speech.config\r\n\r\n"
            + #"{"context":{"synthesis":{"audio":{"metadataoptions":{"#
            + #""sentenceBoundaryEnabled":"\#(wordBoundaries ? "false" : "true")","#
            + #""wordBoundaryEnabled":"\#(wordBoundaries ? "true" : "false")"},"#
            + #""outputFormat":"\#(EdgeEndpoint.outputFormat)"}}}}"#
            + "\r\n"
    }

    /// The SSML request. `escapedText` must already be XML-escaped (see `escape`).
    /// The trailing `Z` after the timestamp is what Edge itself sends.
    public static func ssmlRequest(requestID: String, date: Date, voice: String, rate: String, escapedText: String) -> String {
        "X-RequestId:\(requestID)\r\n"
            + "Content-Type:application/ssml+xml\r\n"
            + "X-Timestamp:\(timestamp(date))Z\r\n"
            + "Path:ssml\r\n\r\n"
            + ssml(voice: voice, rate: rate, escapedText: escapedText)
    }

    public static func ssml(voice: String, rate: String, escapedText: String) -> String {
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(escape(serviceVoiceName(voice)))'>"
            + "<prosody pitch='+0Hz' rate='\(escape(rate))' volume='+0%'>"
            + escapedText
            + "</prosody></voice></speak>"
    }

    /// `nl-NL-FennaNeural` → `Microsoft Server Speech Text to Speech Voice (nl-NL, FennaNeural)`,
    /// the long form Edge sends. Region suffixes move into the locale
    /// (`zh-CN-liaoning-XiaobeiNeural` → `(zh-CN-liaoning, XiaobeiNeural)`). Other strings pass through.
    public static func serviceVoiceName(_ shortName: String) -> String {
        let parts = shortName.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, parts[0].count >= 2, parts[0].allSatisfy(\.isLowercase),
              parts[1].count >= 2, parts[1].allSatisfy(\.isUppercase), shortName.hasSuffix("Neural")
        else { return shortName }
        var region = parts[1]
        var name = parts[2...].joined(separator: "-")
        if let dash = name.firstIndex(of: "-") {
            region += "-" + name[..<dash]
            name = String(name[name.index(after: dash)...])
        }
        return "Microsoft Server Speech Text to Speech Voice (\(parts[0])-\(region), \(name))"
    }

    /// XML-escapes text and replaces control characters the service rejects (vertical tab from
    /// OCR'd PDFs, …) with spaces. Each replacement keeps one character per character, so word
    /// texts still line up with the original.
    public static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\u{0}"..."\u{8}", "\u{B}", "\u{C}", "\u{E}"..."\u{1F}": result += " "
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Reverses `escape`'s entities (word texts in metadata come back escaped).
    public static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Splits escaped text into pieces of at most `maxBytes` UTF-8 bytes, preferring newlines,
    /// then spaces, never cutting a character or an `&…;` entity. Pieces are trimmed; empty
    /// ones are dropped.
    public static func split(_ escaped: String, maxBytes: Int = EdgeEndpoint.maxChunkBytes) -> [String] {
        precondition(maxBytes > 0)
        var bytes = Array(escaped.utf8)[...]
        var pieces: [String] = []
        func emit(_ slice: ArraySlice<UInt8>) {
            let piece = String(decoding: slice, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
        }
        while bytes.count > maxBytes {
            let window = bytes.prefix(maxBytes)
            var cut = window.lastIndex(of: UInt8(ascii: "\n")) ?? window.lastIndex(of: UInt8(ascii: " "))
                ?? safeUTF8Cut(bytes, limit: window.endIndex)
            // Don't split inside an entity: move back to its `&` while it's unterminated.
            while cut > bytes.startIndex, let amp = bytes[..<cut].lastIndex(of: UInt8(ascii: "&")),
                  !bytes[amp..<cut].contains(UInt8(ascii: ";")) {
                cut = amp
            }
            if cut == bytes.startIndex { cut = bytes.index(after: cut) }
            emit(bytes[..<cut])
            bytes = bytes[cut...]
        }
        emit(bytes)
        return pieces
    }

    /// The largest cut ≤ `limit` that doesn't fall inside a multi-byte character: step back over
    /// continuation bytes (10xxxxxx) to the lead byte of the character at `limit`.
    private static func safeUTF8Cut(_ bytes: ArraySlice<UInt8>, limit: Int) -> Int {
        var cut = limit
        while cut > bytes.startIndex, cut < bytes.endIndex, bytes[cut] & 0xC0 == 0x80 { cut -= 1 }
        return cut
    }
}

/// One message received from the service.
public enum EdgeFrame: Equatable, Sendable {
    /// `audio.metadata` word boundaries (offset/duration in 100-ns ticks, text unescaped).
    case wordBoundaries([EdgeWordBoundary])
    /// MP3 bytes from a binary `audio` frame.
    case audio(Data)
    case turnStart
    case response
    case turnEnd
    /// A frame that carries nothing to act on (the empty end-of-stream audio frame, `SessionEnd`).
    case ignored

    /// Parses a text frame: `Header:Value\r\n…\r\n\r\nbody`.
    public static func parse(text: String) throws -> EdgeFrame {
        let data = Data(text.utf8)
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw EdgeNativeError.unexpectedResponse("text frame without headers")
        }
        let headers = parseHeaders(data[..<separator.lowerBound])
        let body = data[separator.upperBound...]
        switch headers["Path"] {
        case "turn.start": return .turnStart
        case "response": return .response
        case "turn.end": return .turnEnd
        case "audio.metadata": return try parseMetadata(body)
        default: throw EdgeNativeError.unexpectedResponse("unknown path \(headers["Path"] ?? "(none)")")
        }
    }

    /// Parses a binary frame: 2-byte big-endian header length, headers, MP3 bytes.
    public static func parse(binary data: Data) throws -> EdgeFrame {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw EdgeNativeError.unexpectedResponse("binary frame without header length") }
        let headerLength = Int(bytes[0]) << 8 | Int(bytes[1])
        guard 2 + headerLength <= bytes.count else {
            throw EdgeNativeError.unexpectedResponse("binary header length exceeds frame")
        }
        let headers = parseHeaders(Data(bytes[2 ..< 2 + headerLength]))
        let body = Data(bytes[(2 + headerLength)...])
        guard headers["Path"] == "audio" else {
            throw EdgeNativeError.unexpectedResponse("binary frame with path \(headers["Path"] ?? "(none)")")
        }
        switch headers["Content-Type"] {
        case nil where body.isEmpty: return .ignored
        case "audio/mpeg" where !body.isEmpty: return .audio(body)
        default: throw EdgeNativeError.unexpectedResponse("unexpected audio frame")
        }
    }

    private static func parseHeaders(_ data: Data) -> [String: String] {
        var headers: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon])] = String(line[line.index(after: colon)...])
        }
        return headers
    }

    private struct Metadata: Decodable {
        struct Item: Decodable {
            let type: String
            let data: Payload?
            enum CodingKeys: String, CodingKey { case type = "Type", data = "Data" }
        }
        struct Payload: Decodable {
            let offset: Int64
            let duration: Int64
            let text: Text
            enum CodingKeys: String, CodingKey { case offset = "Offset", duration = "Duration", text }
        }
        struct Text: Decodable {
            let text: String
            enum CodingKeys: String, CodingKey { case text = "Text" }
        }
        let metadata: [Item]
        enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
    }

    private static func parseMetadata(_ body: Data) throws -> EdgeFrame {
        let metadata: Metadata
        do {
            metadata = try JSONDecoder().decode(Metadata.self, from: body)
        } catch {
            throw EdgeNativeError.unexpectedResponse("unreadable audio.metadata")
        }
        let words = metadata.metadata.compactMap { item -> EdgeWordBoundary? in
            guard item.type == "WordBoundary" || item.type == "SentenceBoundary", let data = item.data else { return nil }
            return EdgeWordBoundary(offset: data.offset, duration: data.duration, text: EdgeMessages.unescape(data.text.text))
        }
        return words.isEmpty ? .ignored : .wordBoundaries(words)
    }
}

/// A word the service reported, timed in 100-ns ticks from the start of the audio.
public struct EdgeWordBoundary: Equatable, Sendable {
    public let offset: Int64
    public let duration: Int64
    public let text: String

    public init(offset: Int64, duration: Int64, text: String) {
        self.offset = offset
        self.duration = duration
        self.text = text
    }

    /// Ticks of audio in `byteCount` bytes of the 48 kbit/s CBR stream: where the next chunk's
    /// offsets start when long text is sent in several requests.
    public static func ticks(forAudioBytes byteCount: Int) -> Int64 {
        Int64(byteCount) * 8 * Int64(EdgeEndpoint.ticksPerSecond) / Int64(EdgeEndpoint.bitsPerSecond)
    }

    /// Marks for `original`: each boundary's text is found in order, starting after the previous
    /// one. One that can't be found (the service sometimes normalizes text) is skipped.
    public static func marks(
        from words: [EdgeWordBoundary], in original: String, granularity: BoundaryMark.Granularity = .word
    ) -> [BoundaryMark] {
        var cursor = original.startIndex
        var marks: [BoundaryMark] = []
        for word in words {
            let needle = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }
            let found = original.range(of: needle, range: cursor..<original.endIndex)
                ?? original.range(
                    of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    range: cursor..<original.endIndex
                )
            guard let found else { continue }
            cursor = found.upperBound
            let start = Double(word.offset) / EdgeEndpoint.ticksPerSecond
            marks.append(BoundaryMark(
                start: start, end: start + Double(word.duration) / EdgeEndpoint.ticksPerSecond,
                range: TextRange(found, in: original), granularity: granularity
            ))
        }
        return marks
    }
}
