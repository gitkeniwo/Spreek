@preconcurrency import AVFoundation

/// Minimal playback surface so `SpeechController` can be tested with a fake clock.
@MainActor
public protocol AudioPlaying: AnyObject {
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    /// Silences output; survives `load(_:)`.
    var isMuted: Bool { get set }
    /// Called when playback reaches the end on its own (not after `stop()`).
    var onFinish: (@MainActor () -> Void)? { get set }

    func load(_ url: URL) throws
    func play()
    func pause()
    func stop()
    /// Moves the playhead without changing whether it plays.
    func seek(to time: TimeInterval)
}

/// `AVAudioPlayer`-backed implementation.
@MainActor
public final class AudioPlayer: NSObject, AudioPlaying, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    public var onFinish: (@MainActor () -> Void)?
    public var isMuted = false {
        didSet { player?.volume = isMuted ? 0 : 1 }
    }

    override public init() {
        super.init()
    }

    public var currentTime: TimeInterval { player?.currentTime ?? 0 }
    public var duration: TimeInterval { player?.duration ?? 0 }
    public var isPlaying: Bool { player?.isPlaying ?? false }

    public func load(_ url: URL) throws {
        player?.stop()
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.volume = isMuted ? 0 : 1
        player.prepareToPlay()
        self.player = player
    }

    public func play() { player?.play() }
    public func pause() { player?.pause() }
    public func seek(to time: TimeInterval) { player?.currentTime = time }

    public func stop() {
        player?.stop()
        player?.currentTime = 0
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(finished)
        Task { @MainActor in
            // Ignore a late callback from a player that has since been replaced.
            guard let player = self.player, ObjectIdentifier(player) == id else { return }
            self.onFinish?()
        }
    }
}
