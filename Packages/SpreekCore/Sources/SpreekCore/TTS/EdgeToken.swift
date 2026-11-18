import Foundation

/// The `Sec-MS-GEC` query value the Edge read-aloud service requires (v2 format,
/// `<16 hex CS64>-<64 hex SHA-256>`), re-implemented from the protocol used by edge-tts 7.3.
///
/// The input is the current Windows file time, rounded down to 5 minutes, followed by the
/// trusted client token. The SHA-256 part hashes a fixed 57-byte secret prefix plus that input;
/// the prefix is only available as a precomputed midstate (the constants below). The CS64 part is
/// a keyed checksum over the input, keyed by the digest. Both halves change every 5 minutes.
public enum EdgeToken {
    /// Seconds between 1601-01-01 (Windows epoch) and 1970-01-01.
    static let windowsEpochOffset: Int64 = 11_644_473_600

    /// Token for `date` (already corrected for clock skew).
    public static func secMSGEC(at date: Date) -> String {
        secMSGEC(unixTime: date.timeIntervalSince1970)
    }

    public static func secMSGEC(unixTime: TimeInterval) -> String {
        var seconds = Int64(unixTime.rounded(.down)) + windowsEpochOffset
        seconds -= seconds % 300
        let input = Array("\(seconds * 10_000_000)\(EdgeEndpoint.trustedClientToken)".utf8)
        let digest = sha256(input)
        let (low, high) = cs64(input, digest: digest)
        return hex(littleEndian(low) + littleEndian(high)) + "-" + hex(digest)
    }

    // MARK: SHA-256 with a secret prefix

    private static let initialHash: [UInt32] = [
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    ]
    /// Working registers after the first 14 rounds over the secret prefix.
    private static let prefixState: [UInt32] = [
        0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A, 0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
    ]
    /// Prefix-only contributions to message schedule words 16…29.
    private static let prefixSchedule: [UInt32] = [
        0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, 0xC0DD25A0,
        0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33, 0xD258B060, 0x72766564,
    ]
    private static let roundConstants: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
    ]
    /// Folds the prefix's share of word 14 into round constant 14 for the first block.
    private static let adjustment: UInt32 = 0xC9DC06A7
    private static let sigma0Adjustment: UInt32 = 0x059C0B80
    private static let sigma1Adjustment: UInt32 = 0x000B92C0
    private static let prefixLength = 57

    /// SHA-256(prefix ‖ input). `input` needs at least 7 bytes (they complete the first block).
    static func sha256(_ input: [UInt8]) -> [UInt8] {
        precondition(input.count >= 7, "token input must have at least 7 bytes")
        var state = firstBlockState(Array(input[0..<7]))
        let length = prefixLength + input.count
        var tail = Array(input[7...]) + [0x80]
        tail += [UInt8](repeating: 0, count: ((55 - length) % 64 + 64) % 64)
        tail += bigEndian(UInt64(length * 8))
        for offset in stride(from: 0, to: tail.count, by: 64) {
            var words = (0..<16).map { i in
                tail[offset + 4 * i ..< offset + 4 * i + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            }
            expandSchedule(&words, from: 16)
            let working = rounds(state, words, from: 0, constants: roundConstants)
            state = zip(state, working).map { $0 &+ $1 }
        }
        return state.flatMap(bigEndian)
    }

    /// Hash state after the first block: 57 prefix bytes (precomputed) + the first 7 input bytes.
    private static func firstBlockState(_ head: [UInt8]) -> [UInt32] {
        var words = [UInt32](repeating: 0, count: 14)
        words.append(head[0..<3].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        words.append(head[3..<7].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        for index in 16..<30 {
            var value = prefixSchedule[index - 16]
            if index - 2 >= 14 {
                let s1 = smallSigma1(words[index - 2])
                value &+= index == 16 ? s1 ^ sigma1Adjustment : s1
            }
            if index - 7 >= 14 { value &+= words[index - 7] }
            if index - 15 >= 14 {
                let s0 = smallSigma0(words[index - 15])
                value &+= index == 29 ? s0 ^ sigma0Adjustment : s0
            }
            words.append(value)
        }
        words.append(smallSigma1(words[28]) &+ words[23] &+ smallSigma0(words[15]) &+ words[14]
            &+ adjustment &- roundConstants[14])
        expandSchedule(&words, from: 31)
        var constants = roundConstants
        constants[14] = adjustment
        let working = rounds(prefixState, words, from: 14, constants: constants)
        return zip(initialHash, working).map { $0 &+ $1 }
    }

    private static func expandSchedule(_ words: inout [UInt32], from first: Int) {
        for index in first..<64 {
            words.append(smallSigma1(words[index - 2]) &+ words[index - 7] &+ smallSigma0(words[index - 15]) &+ words[index - 16])
        }
    }

    /// Standard SHA-256 compression rounds `first..<64`, without the final feed-forward.
    private static func rounds(_ state: [UInt32], _ words: [UInt32], from first: Int, constants: [UInt32]) -> [UInt32] {
        var (a, b, c, d, e, f, g, h) = (state[0], state[1], state[2], state[3], state[4], state[5], state[6], state[7])
        for index in first..<64 {
            let t1 = h &+ (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) &+ (g ^ (e & (f ^ g))) &+ constants[index] &+ words[index]
            let t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) &+ ((a & b) | (c & (a | b)))
            (h, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
        }
        return [a, b, c, d, e, f, g, h]
    }

    private static func smallSigma0(_ x: UInt32) -> UInt32 { rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3) }
    private static func smallSigma1(_ x: UInt32) -> UInt32 { rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10) }
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { x >> n | x << (32 - n) }

    // MARK: CS64

    private static let cs64Coefficients: [(UInt32, UInt32)] = [
        (0xE82E91B1, 0xB32700D0), (0x44DE24C6, 0x88DFF51D), (0x3BEB65BC, 0x29514038), (0xC89C5933, 0xB328CBDF),
        (0x8D1EC211, 0xD405B4D5), (0x314EF5D5, 0x26E55F3C), (0xE92491B1, 0x607801C6), (0xF0A5B9D5, 0x82B2C1FB),
        (0x06064CF3, 0xFA51A3DA), (0xDA79FA60, 0x207CC464), (0xBED20560, 0x3C3C74F3), (0x89F9C9F8, 0xD2D14B61),
        (0x35FA38C6, 0xBB04A2C1), (0xCB49E3C6, 0xC5626167),
    ]
    private static let cs64Factor: UInt32 = 0x82893933
    private static let cs64Adjustment0: UInt32 = 0xF2F90B1A
    private static let cs64Adjustment1: UInt32 = 0x0B1A0000

    static func cs64(_ input: [UInt8], digest: [UInt8]) -> (UInt32, UInt32) {
        let keyA = littleEndianWord(digest, at: 0) | 1
        let keyB = littleEndianWord(digest, at: 4) | 1
        let factors = [keyA &* cs64Factor, keyB &* cs64Factor]
        var terms = cs64Coefficients.enumerated().map { $1.0 &* factors[$0 % 2] }
        var offsets = cs64Coefficients.map(\.1)

        // Little-endian words of 0x00 ‖ input, zero-padded to an even number of words.
        var bytes = [UInt8(0)] + input
        bytes += [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4)
        var words = stride(from: 0, to: bytes.count, by: 4).map { littleEndianWord(bytes, at: $0) }
        if words.count % 2 == 1 { words.append(0) }
        for (index, word) in words.enumerated() {
            let even = index % 2 == 0
            var term = word &* (even ? keyA : keyB)
            var offset = rol16(word) &* (even ? 0xEF0569FB : 0xC31713DB)
            if index == 0 {
                term &+= cs64Adjustment0 &* factors[0]
                offset &+= cs64Adjustment1
            }
            terms.append(term)
            offsets.append(offset)
        }

        var swapAcc: UInt32 = 0, swapLast: UInt32 = 0, state: UInt32 = 0, acc: UInt32 = 0
        for index in stride(from: 0, to: terms.count, by: 2) {
            let x = terms[index], y = terms[index + 1]
            var q = rol16(offsets[index] &+ x) &* 0x76F50F34
            swapAcc &+= rol16(q) &* 0xC3EFEA97 &+ q
            q = rol16(offsets[index + 1] &+ y) &* 0x1881CE3C
            swapLast = rol16(q) &* 0x35BD1EC9 &+ q
            swapAcc &+= swapLast

            state = state &* keyA &+ x
            state = rol16(state) &* 0xCF98B111
            state = rol16(state) &* 0x87085B9F
            state = rol16(state) &* 0x12CEB96D
            state = rol16(state) &* 0x257E1D83
            acc &+= state
            var t = state &* keyB &+ y
            t = rol16(t) &* 0xA27416F5
            t = rol16(t) &* 0xD38396FF
            state = rol16(rol16(t) &* 0x7C932B89) &* 0xBFA49F69
            acc &+= state
        }
        return (swapLast ^ state, swapAcc ^ acc)
    }

    private static func rol16(_ x: UInt32) -> UInt32 { x << 16 | x >> 16 }

    // MARK: Bytes

    private static func littleEndianWord(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    private static func bigEndian(_ value: UInt64) -> [UInt8] {
        (0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
