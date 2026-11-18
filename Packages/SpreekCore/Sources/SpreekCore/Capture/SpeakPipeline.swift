import CoreGraphics
import Foundation
import Observation

/// How the selected text was obtained.
public enum CaptureMethod: String, Sendable, Hashable {
    /// `kAXSelectedTextAttribute` of the focused element.
    case accessibility
    /// Synthesized ⌘C with the clipboard restored afterwards.
    case copy
    /// Handed to us by the Services menu.
    case services
    /// The clipboard's text (Speak clipboard shortcut).
    case clipboard
}

/// Selected text plus where it came from.
public struct CapturedSelection: Sendable, Hashable {
    public let text: String
    public let method: CaptureMethod
    public let appName: String?
    public let bundleID: String?
    /// Page URL when the source is a browser and it was cheap to read.
    public let url: URL?
    /// Where the selected text is on screen (Cocoa coordinates), when the app reports it.
    /// Settings › Position › Near selection puts the bar next to it.
    public let bounds: CGRect?

    public init(text: String, method: CaptureMethod, appName: String? = nil, bundleID: String? = nil, url: URL? = nil, bounds: CGRect? = nil) {
        self.text = text
        self.method = method
        self.appName = appName
        self.bundleID = bundleID
        self.url = url
        self.bounds = bounds
    }
}

/// Reads the current selection in the frontmost app.
@MainActor
public protocol SelectionCapturing {
    func captureSelection() async -> CapturedSelection?
}

/// Normalized text, the detected language and the request that will be synthesized.
public struct PreparedSpeech: Sendable, Hashable {
    public let detection: DetectionResult
    public let request: SpeechRequest

    public var text: String { request.text }
}

/// Selection → `TextNormalizer` → `LanguageDetector` → `SpeechController`.
@MainActor
@Observable
public final class SpeakPipeline {
    public enum Outcome: Sendable, Hashable {
        case speaking(PreparedSpeech)
        /// The reader found no selection (or wasn't allowed to look).
        case nothingSelected
        /// The selection was only whitespace / invisible characters.
        case empty
    }

    /// Rate used by the "speak slower" shortcut.
    public static let slowerRate = 0.8

    public private(set) var lastCapture: CapturedSelection?
    public private(set) var lastOutcome: Outcome?

    private let reader: any SelectionCapturing
    private let speech: SpeechController

    public init(reader: any SelectionCapturing, speech: SpeechController) {
        self.reader = reader
        self.speech = speech
    }

    /// Captures the selection and speaks it. `rate` overrides the controller's rate for this request.
    @discardableResult
    public func speakSelection(rate: Double? = nil) async -> Outcome {
        guard let capture = await reader.captureSelection() else {
            lastOutcome = .nothingSelected
            return .nothingSelected
        }
        return speak(capture, rate: rate)
    }

    /// Speaks already-captured text (Services menu, tests).
    @discardableResult
    public func speak(_ capture: CapturedSelection, rate: Double? = nil) -> Outcome {
        let outcome: Outcome
        if let prepared = speech.prepare(text: capture.text, rate: rate) {
            lastCapture = capture
            speech.speak(prepared, source: capture.method == .services ? .services : .selection)
            outcome = .speaking(prepared)
        } else {
            outcome = .empty
        }
        lastOutcome = outcome
        return outcome
    }
}
