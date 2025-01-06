import AVFoundation
import os.log

@objc(TransparentVideoViewManager)
class TransparentVideoViewManager: RCTViewManager {

  override func view() -> TransparentVideoView {
    return TransparentVideoView()
  }

  @objc override static func requiresMainQueueSetup() -> Bool {
    return false
  }
}

class TransparentVideoView: UIView {

  private var source: VideoSource?
  private var playerView: AVPlayerView?
  private var videoAutoplay: Bool?
  private var videoLoop: Bool?

  @objc var loop: Bool = false {
    didSet {
      // Set up looping behavior
      if let playerView = self.playerView {
        playerView.isLoopingEnabled = loop

        // Start playing immediately if autoplay is enabled and loop is set
        if loop && (playerView.player?.rate == 0 || playerView.player?.error != nil) {
          playerView.player?.play()
        }
      }
    }
  }

  @objc var src: NSDictionary = NSDictionary() {
    didSet {
      // Update the video source and reload video
      self.source = VideoSource(src)
      guard let uri = self.source?.uri, let itemUrl = URL(string: uri) else { return }
      loadVideoPlayer(itemUrl: itemUrl)
    }
  }

  @objc var autoplay: Bool = false {
    didSet {
      self.videoAutoplay = autoplay
      if let player = self.playerView?.player, autoplay && (player.rate == 0 || player.error != nil) {
        player.play()
      }
    }
  }

  func loadVideoPlayer(itemUrl: URL) {
    if self.playerView == nil {
      let playerView = AVPlayerView(frame: .zero)
      addSubview(playerView)

      // Use Auto Layout anchors to center our playerView
      playerView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        playerView.topAnchor.constraint(equalTo: self.topAnchor),
        playerView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        playerView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        playerView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
      ])

      // Setup playerLayer to hold a pixel buffer format with "alpha"
      let playerLayer: AVPlayerLayer = playerView.playerLayer
      playerLayer.pixelBufferAttributes = [
        (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA
      ]

      // Setup looping for video
      playerView.isLoopingEnabled = self.videoLoop ?? true

      // Observers for app lifecycle
      NotificationCenter.default.addObserver(self, selector: #selector(appEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
      NotificationCenter.default.addObserver(self, selector: #selector(appEnteredForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

      self.playerView = playerView
    }

    // Load player item
    loadItem(url: itemUrl)
  }

  deinit {
    playerView?.player?.pause()
    playerView?.player?.replaceCurrentItem(with: nil)
    playerView?.removeFromSuperview()
    playerView = nil
  }

  // MARK: - Player Item Configuration

  private func loadItem(url: URL) {
    setUpAsset(with: url) { [weak self] asset in
      self?.setUpPlayerItem(with: asset)
    }
  }

  private func setUpAsset(with url: URL, completion: @escaping (AVAsset) -> Void) {
    let asset = AVAsset(url: url)
    asset.loadValuesAsynchronously(forKeys: ["metadata"]) {
      var error: NSError? = nil
      let status = asset.statusOfValue(forKey: "metadata", error: &error)
      switch status {
      case .loaded:
        completion(asset)
      case .failed:
        print("Asset loading failed.")
      case .cancelled:
        print("Asset loading cancelled.")
      default:
        print("Asset loading default case.")
      }
    }
  }

  private func setUpPlayerItem(with asset: AVAsset) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let playerItem = AVPlayerItem(asset: asset)
      playerItem.seekingWaitsForVideoCompositionRendering = true

      // Apply a custom video composition filter
      playerItem.videoComposition = self.createVideoComposition(for: asset)

      self.playerView?.loadPlayerItem(playerItem) { result in
        switch result {
        case .failure(let error):
          print("Failed to load video:", error)
        case .success(let player):
          if self.videoAutoplay ?? false {
            player.play() // Autoplay when ready
          } else {
            player.pause() // Don't play if autoplay is off
          }
        }
      }
    }
  }

  func createVideoComposition(for asset: AVAsset) -> AVVideoComposition {
    let filter = AlphaFrameFilter(renderingMode: .builtInFilter)
    let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
      do {
        let (inputImage, maskImage) = request.sourceImage.verticalSplit()
        let outputImage = try filter.process(inputImage, mask: maskImage)
        return request.finish(with: outputImage, context: nil)
      } catch {
        os_log("Error processing video composition: %@", error.localizedDescription)
        return request.finish(with: error)
      }
    })

    composition.renderSize = asset.videoSize.applying(CGAffineTransform(scaleX: 1.0, y: 0.5))
    return composition
  }

  // MARK: - Lifecycle Callbacks

  @objc func appEnteredBackground() {
    if let player = self.playerView?.player,
        let tracks = player.currentItem?.tracks {
      for track in tracks {
        if track.assetTrack?.hasMediaCharacteristic(.visual) == true {
          track.isEnabled = false
        }
      }
    }
  }

  @objc func appEnteredForeground() {
    if let player = self.playerView?.player,
        let tracks = player.currentItem?.tracks {
      for track in tracks {
        if track.assetTrack?.hasMediaCharacteristic(.visual) == true {
          track.isEnabled = true
        }
      }
    }
  }
}
