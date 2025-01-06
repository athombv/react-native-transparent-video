import AVFoundation
import UIKit

/// A custom UIView subclass that encapsulates an AVPlayerLayer to handle video playback with additional features.
public class AVPlayerView: UIView {

    deinit {
        playerItem = nil
    }

    public override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    public private(set) var player: AVPlayer? {
        get { return playerLayer.player }
        set { playerLayer.player = newValue }
    }

    /// When enabled, the player view automatically restarts playback when it ends.
    /// - Warning: Enabling this does not ensure a smooth looping experience.
    public var isLoopingEnabled: Bool = false {
        didSet { setupLooping() }
    }

    /// When set to `true`, the audio of the video will be muted. Defaults to `true`.
    public var isMuted: Bool = true {
        didSet { player?.isMuted = isMuted }
    }

    private var playerItemStatusObserver: NSKeyValueObservation?
    private var didPlayToEndTimeObserver: NSObjectProtocol? = nil {
        willSet {
            // Automatically remove the old observer before setting a new one.
            if let observer = didPlayToEndTimeObserver, didPlayToEndTimeObserver !== newValue {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    private(set) var playerItem: AVPlayerItem? = nil {
        didSet {
            setupLooping()
        }
    }

    /**
     Loads a new AVPlayerItem and prepares the player for playback.

     - Parameters:
        - playerItem: The AVPlayerItem to be loaded.
        - onReady: A closure invoked when the player is ready or if an error occurs.
     */
    public func loadPlayerItem(_ playerItem: AVPlayerItem, onReady: ((Result<AVPlayer, Error>) -> Void)? = nil) {
        let player = AVPlayer(playerItem: playerItem)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }

        // Configure player settings
        player.isMuted = true

        // Prevent video player from disabling display sleep when idle
        if #available(iOS 12.0, *) {
            player.preventsDisplaySleepDuringVideoPlayback = false
        } else {
            // Fallback on earlier versions
        };

        self.player = player
        self.playerItem = playerItem

        guard let completion = onReady else {
            playerItemStatusObserver = nil
            return
        }

        playerItemStatusObserver = playerItem.observe(\.status) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                completion(.success(player))
                self?.playerItemStatusObserver = nil
            case .failed:
                completion(.failure(item.error ?? NSError(domain: "Unknown Error", code: -1, userInfo: nil)))
            case .unknown:
                break
            @unknown default:
                fatalError("Unhandled AVPlayerItem status case.")
            }
        }
    }

    private func setupLooping() {
        guard isLoopingEnabled, let playerItem = self.playerItem, let player = self.player else {
            didPlayToEndTimeObserver = nil
            return
        }

        didPlayToEndTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: nil
        ) { _ in
            player.seek(to: .zero) { _ in
                player.play()
            }
        }
    }
}
