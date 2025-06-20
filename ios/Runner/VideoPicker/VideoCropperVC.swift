//
//  VideoCropperVC.swift
//  Runner
//
//  Presents a full-screen crop UI, exports the cropped video,
//  and returns the new file URL via delegate callbacks.
//

import UIKit
import AVFoundation

// MARK: - Delegate
protocol VideoCropperDelegate: AnyObject {
  func videoCropper(_ vc: VideoCropperVC, didFinishWith url: URL)
  func videoCropperDidCancel(_ vc: VideoCropperVC)
}

// MARK: - View-Controller
final class VideoCropperVC: UIViewController {

  // ───────── Public ─────────
  let sourceURL: URL
  weak var delegate: VideoCropperDelegate?

  // ───────── Private ─────────
  private var player: AVPlayer!
  private var playerLayer: AVPlayerLayer!
  private var overlay: CropOverlayView!
  private var exportTask: AVAssetExportSession?

  // MARK: init
  init(source: URL) {
    self.sourceURL = source
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }
  required init?(coder: NSCoder) { fatalError() }

  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    setupPlayer()
    setupOverlay()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    playerLayer.frame = view.bounds
    overlay.frame       = view.bounds
  }

  // MARK: - UI helpers
  private func setupPlayer() {
    let item  = AVPlayerItem(url: sourceURL)
    player    = AVPlayer(playerItem: item)
    playerLayer = AVPlayerLayer(player: player)
    playerLayer.videoGravity = .resizeAspect
    playerLayer.frame = view.bounds
    view.layer.addSublayer(playerLayer)
    player.play()
  }

  private func setupOverlay() {
    overlay = CropOverlayView(frame: view.bounds)      // full-frame default
    overlay.onDone   = { [weak self] rect in self?.exportCrop(rectInView: rect) }
    overlay.onCancel = { [weak self] in  self?.cancel() }
    view.addSubview(overlay)
  }

  // MARK: - Cancel
  private func cancel() {
    exportTask?.cancelExport()   // correct name
    delegate?.videoCropperDidCancel(self)
  }

  // MARK: - Export logic
  private func exportCrop(rectInView viewRect: CGRect) {
    player.pause()
    overlay.isUserInteractionEnabled = false

    let asset = AVAsset(url: sourceURL)
    guard let track = asset.tracks(withMediaType: .video).first else { cancel(); return }

    // Convert view-space → video-space
    let natural = track.naturalSize.applying(track.preferredTransform)
    let videoW  = abs(natural.width)
    let videoH  = abs(natural.height)
    let norm    = CGRect(x: viewRect.minX / view.bounds.width,
                         y: viewRect.minY / view.bounds.height,
                         width: viewRect.width  / view.bounds.width,
                         height: viewRect.height / view.bounds.height)
    let cropR   = CGRect(x: norm.minX * videoW,
                         y: (1 - norm.maxY) * videoH,
                         width: norm.width  * videoW,
                         height: norm.height * videoH)

    // Build composition that crops every frame
    let comp = AVMutableVideoComposition(asset: asset) { req in
      let img = req.sourceImage.cropped(to: cropR)
      req.finish(with: img, context: nil)
    }
    comp.renderSize = cropR.size
    comp.frameDuration = CMTime(value: 1, timescale: 30)
    comp.sourceTrackIDForFrameTiming = track.trackID

    // Export
    let outURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".mov")
    let exp = AVAssetExportSession(asset: asset,
                                   presetName: AVAssetExportPresetHighestQuality)!
    exp.videoComposition = comp
    exp.outputURL        = outURL
    exp.outputFileType   = .mov
    exportTask = exp

    exp.exportAsynchronously { [weak self] in
      DispatchQueue.main.async {
        guard let self else { return }
        if exp.status == .completed {
          self.delegate?.videoCropper(self, didFinishWith: outURL)
        } else {
          self.cancel()
        }
      }
    }
  }
}
