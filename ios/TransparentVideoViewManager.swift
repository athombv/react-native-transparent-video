import AVFoundation
import os.log
import React

@objc(TransparentVideoViewManager)
class TransparentVideoViewManager: RCTViewManager {

  override func view() -> UIView {
    return TransparentVideoView()
  }

  @objc override static func requiresMainQueueSetup() -> Bool {
    return false
  }
}

class TransparentVideoView: UIView {

  private var source: VideoSource?
  private var playerView: AVPlayerView?
  private var videoAutoplay: Bool = false
  private var videoLoop: Bool = false

  @objc var loop: Bool = false {
    didSet {
      self.videoLoop = loop
      self.playerView?.isLoopingEnabled = loop

      if loop, let player = self.playerView?.player, player.rate == 0 || player.error != nil {
        player.play()
      }
    }
  }

  @objc var src: NSDictionary = NSDictionary() {
    didSet {
      self.source = VideoSource(src)
      guard let uri = self.source?.uri, let itemUrl = URL(string: uri) else { return }
      loadVideoPlayer(itemUrl: itemUrl)
    }
  }

  @objc var autoplay: Bool = false {
    didSet {
      self.videoAutoplay = autoplay
      if autoplay, let player = self.playerView?.player, player.rate == 0 || player.error != nil {
        player.play()
      }
    }
  }

  func loadVideoPlayer(itemUrl: URL) {
    if self.playerView == nil {
      let playerView = AVPlayerView(frame: .zero)
      addSubview(playerView)

      playerView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        playerView.topAnchor.constraint(equalTo: self.topAnchor),
        playerView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        playerView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        playerView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
      ])

      let playerLayer: AVPlayerLayer = playerView.playerLayer
      playerLayer.pixelBufferAttributes = [
        (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA
      ]

      playerView.isLoopingEnabled = self.videoLoop

      NotificationCenter.default.addObserver(self, selector: #selector(appEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
      NotificationCenter.default.addObserver(self, selector: #selector(appEnteredForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

      self.playerView = playerView
    }

    loadItem(url: itemUrl)
  }

  deinit {
    // Remove specific observers
    NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)

    // Stop and remove player resources
    playerView?.player?.pause()
    playerView?.player?.replaceCurrentItem(with: nil)
    playerView?.removeFromSuperview()
    playerView = nil
  }

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
      case .failed, .cancelled:
        print("Asset loading failed.")
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

      playerItem.videoComposition = self.createVideoComposition(for: asset)

      self.playerView?.loadPlayerItem(playerItem) { result in
        switch result {
        case .failure(let error):
          print("Failed to load video:", error)
        case .success(let player):
          if self.videoAutoplay {
            player.play()
          } else {
            player.pause()
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
