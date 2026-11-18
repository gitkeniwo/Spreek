import Foundation

/// What a failed Edge request says about who is at fault: the voice (in one boundary mode, or
/// altogether) or the service. A pure function over the error, so it is easy to test; the chain
/// decides what to remember from it.
public enum EdgeFailure: Equatable, Sendable {
    /// The service accepted the connection and then misbehaved for this voice: a reset, a stall,
    /// a turn that ended without audio.
    case voice
    /// Nothing works, whatever the voice.
    case service(ServiceProblem)
    /// Nothing to learn about Edge (cancelled, empty text, edge-tts not installed).
    case unrelated

    public enum ServiceProblem: Equatable, Sendable {
        /// No network, DNS failure, nothing answered before the handshake. Usually passes soon,
        /// so it is not remembered between requests.
        case unreachable
        /// The service answered and refused (handshake not 101 even after the clock-skew retry,
        /// voice list refused) or spoke a protocol we don't know. Stays broken until Spreek or
        /// Microsoft changes something, so it is remembered.
        case refused
    }

    /// Whether the problem is worth remembering between requests.
    public var isRemembered: Bool {
        switch self {
        case .voice, .service(.refused): true
        case .service(.unreachable), .unrelated: false
        }
    }

    public static func classify(_ error: any Error) -> EdgeFailure {
        if error is CancellationError { return .unrelated }
        if let tagged = error as? EdgeAfterHandshakeError { return classify(afterHandshake: tagged.underlying) }
        switch error {
        case let error as EdgeNativeError:
            switch error {
            case .rejected, .unexpectedResponse: return .service(.refused)
            case .connectionClosed: return .voice
            }
        case let error as TTSError:
            switch error {
            case .noAudioProduced: return .voice
            // Nothing arrived before the deadline: the connection never got going.
            case .timedOut: return .service(.unreachable)
            case .executableNotFound, .noVoice, .emptyText, .processFailed: return .unrelated
            }
        default:
            return isNetworkError(error) ? .service(.unreachable) : .unrelated
        }
    }

    /// After the handshake a reset, stall or early close is the voice's doing; only a refusal or an
    /// unknown protocol still points at the service.
    private static func classify(afterHandshake error: any Error) -> EdgeFailure {
        if error is CancellationError { return .unrelated }
        if let native = error as? EdgeNativeError, case .rejected = native { return .service(.refused) }
        if let native = error as? EdgeNativeError, case .unexpectedResponse = native { return .service(.refused) }
        return .voice
    }

    /// URLSession / POSIX errors that mean "the network is not there" before a connection works.
    static func isNetworkError(_ error: any Error) -> Bool {
        let ns = error as NSError
        switch ns.domain {
        case NSURLErrorDomain:
            return [
                NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorTimedOut,
                NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed, NSURLErrorSecureConnectionFailed,
                NSURLErrorCannotLoadFromNetwork,
            ].contains(ns.code)
        case NSPOSIXErrorDomain:
            // ENETDOWN, ENETUNREACH, ECONNRESET, ETIMEDOUT, ECONNREFUSED, EHOSTDOWN, EHOSTUNREACH
            return [50, 51, 54, 60, 61, 64, 65].contains(ns.code)
        default:
            return false
        }
    }
}
