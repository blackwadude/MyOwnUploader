//
//  PostEditorVC.swift
//  Runner
//
//  Updated: 2025-06-10 – exports video + PNG thumbnail + quick “download” button
//

import UIKit
import AVFoundation
import PhotosUI
import Photos
import CoreImage


// MARK: – CIFilter video compositor
// MARK: – CIFilter video compositor
final class FilterCompositor: NSObject, AVVideoCompositing {

  static var filterName: String?
  static var preferredTransform: CGAffineTransform = .identity
    
    private var needsExtraYFlip: Bool {
        Self.preferredTransform.d >= 0     //  +1  ➜  still needs the CI→AV flip
    }

  // ───────── boiler-plate ─────────
  private let queue = DispatchQueue(label: "filter.render")
  private var ctx: AVVideoCompositionRenderContext?

  var sourcePixelBufferAttributes: [String : Any]? {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }
  var requiredPixelBufferAttributesForRenderContext: [String : Any] {
    sourcePixelBufferAttributes!
  }
  func renderContextChanged(_ new: AVVideoCompositionRenderContext) {
    queue.sync { ctx = new }
  }
    

  // ───────── main render loop ─────────
  func startRequest(_ req: AVAsynchronousVideoCompositionRequest) {
    autoreleasepool {
      guard
        let src = req.sourceFrame(byTrackID: req.sourceTrackIDs[0].int32Value),
        let dst = ctx?.newPixelBuffer()
      else {
        req.finish(with: NSError(domain:"FilterCompositor", code:0)); return
      }

      //-------------------------------------------
      // 1️⃣ start with raw frame
      //-------------------------------------------
      var img = CIImage(cvPixelBuffer: src)

      //-------------------------------------------
      // 2️⃣ rotate into portrait
      //-------------------------------------------
      img = img.transformed(by: Self.preferredTransform)

      //-------------------------------------------
      // 3️⃣ translate to origin, then Y-flip
      //-------------------------------------------
      let ext   = img.extent
      let shift = CGAffineTransform(translationX: -ext.origin.x,
                                    y: -ext.origin.y)
      img = img.transformed(by: shift)

        // ----------------------------------------------------
        // 4) Flip only if the incoming frame is NOT already
        //    vertically mirrored (d = +1 means “upright”)  👇
        // ----------------------------------------------------
        if let canvas = ctx?.size {
            if needsExtraYFlip {                      // <─── only when required
                let flip = CGAffineTransform(scaleX: 1, y: -1)
                              .translatedBy(x: 0, y: -canvas.height)
                img = img.transformed(by: flip)
            }
            img = img.cropped(to: CGRect(origin: .zero, size: canvas))
        }

      //-------------------------------------------
      // 4️⃣ optional CIFilter
      //-------------------------------------------
      if let name = Self.filterName,
         let f    = CIFilter(name: name) {
        f.setValue(img, forKey: kCIInputImageKey)
        img = f.outputImage ?? img
      }

      //-------------------------------------------
      // 5️⃣ render
      //-------------------------------------------
      CIContext().render(img, to: dst)
      req.finish(withComposedVideoFrame: dst)
    }
  }
}




// MARK: – main
final class PostEditorVC: UIViewController {

  // MARK: – completion  (videoURL, thumbnailPNGURL?)
  var completion: ((URL, URL?) -> Void)?

  // MARK: – init
  private let fromGallery: Bool
  init(videoURL: URL, fromGallery: Bool) {
    self.videoURL = videoURL
    self.fromGallery = fromGallery
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }

  // MARK: – video state
  private var videoURL: URL
  private var player: AVPlayer!
  private var playerItem: AVPlayerItem!
  private var wasPlayingBeforeTrim = false
  private var playerLayer: AVPlayerLayer!


  // MARK: – overlays & filters
  private var captions: [EditableCaption] = []
  private var stickers: [DraggableSticker] = []
  private let filters: [(title: String, ciName: String?)] = [
    ("None", nil), ("Mono", "CIPhotoEffectMono"), ("Noir", "CIPhotoEffectNoir"),
    ("Fade", "CIPhotoEffectFade"), ("Instant", "CIPhotoEffectInstant"),
    ("Process", "CIPhotoEffectProcess")
  ]
  private var currentFilterName: String?
  private var filterBar: UICollectionView?

  // MARK: – UI refs
  private var nextBtn: UIButton!
    
    // MARK: – loader / toast
    private var loader: UIView?

    private func showLoader(_ message: String? = nil) {
      guard loader == nil else { return }
      let bg = UIView(frame: view.bounds)
      bg.backgroundColor = UIColor.black.withAlphaComponent(0.55)

      let spinner = UIActivityIndicatorView(style: .large)
      spinner.color = .white
      spinner.translatesAutoresizingMaskIntoConstraints = false
      spinner.startAnimating()
      bg.addSubview(spinner)

      if let msg = message {
        let label = UILabel()
        label.text = msg
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(label)

        NSLayoutConstraint.activate([
          spinner.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
          spinner.centerYAnchor.constraint(equalTo: bg.centerYAnchor, constant: -12),
          label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
          label.centerXAnchor.constraint(equalTo: bg.centerXAnchor)
        ])
      } else {
        NSLayoutConstraint.activate([
          spinner.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
          spinner.centerYAnchor.constraint(equalTo: bg.centerYAnchor)
        ])
      }

      view.addSubview(bg)
      loader = bg
    }

    private func hideLoader() {
      loader?.removeFromSuperview()
      loader = nil
    }

    /// Quick one-line toast
    private func toast(_ text: String) {
      let lbl = UILabel()
      lbl.text = text
      lbl.font = .systemFont(ofSize: 14, weight: .semibold)
      lbl.textColor = .white
      lbl.backgroundColor = UIColor.black.withAlphaComponent(0.8)
      lbl.textAlignment = .center
      lbl.layer.cornerRadius = 8
      lbl.clipsToBounds = true
      lbl.alpha = 0
      lbl.frame = CGRect(x: 40,
                         y: view.bounds.height * 0.25,
                         width: view.bounds.width - 80,
                         height: 36)
      view.addSubview(lbl)

      UIView.animate(withDuration: 0.3, animations: { lbl.alpha = 1 }) { _ in
        UIView.animate(withDuration: 0.3, delay: 1.2, options: []) {
          lbl.alpha = 0
        } completion: { _ in lbl.removeFromSuperview() }
      }
    }


  // MARK: – life-cycle
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    setupPlayer()
    setupSideTray()
    setupBottomBar()
    setupBackButton()

    let tap = UITapGestureRecognizer(target: self,
                                     action: #selector(handleViewTap(_:)))
    tap.cancelsTouchesInView = false
    view.addGestureRecognizer(tap)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Haptics.prime()
  }

  // MARK: – player
  private func setupPlayer() {
    playerItem = AVPlayerItem(url: videoURL)
    player = AVPlayer(playerItem: playerItem)
    player.actionAtItemEnd = .none
    NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: playerItem,
      queue: .main) { [weak self] _ in
        self?.player.seek(to: .zero); self?.player.play()
      }

      playerLayer = AVPlayerLayer(player: player)
      playerLayer.frame         = view.bounds
      playerLayer.videoGravity  = .resizeAspectFill
      view.layer.addSublayer(playerLayer)
    player.play()
  }

  // MARK: – side tray
  private func setupSideTray() {
    let items: [(String,String,Selector)] = [
      ("Aa","textformat",          #selector(textTapped)),
      ("Fx","sparkles",            #selector(filterTapped)),
      ("🙂","face.smiling",        #selector(stickerTapped)),
      ("✂︎","scissors",            #selector(trimTapped)),
      ("↓","arrow.down.circle",    #selector(downloadTapped)) // NEW
    ]

    let stack = UIStackView()
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 22
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    items.forEach { _, sf, sel in
      let b = UIButton(type: .system)
      b.setImage(UIImage(systemName: sf), for: .normal)
      b.tintColor = .white
      b.widthAnchor.constraint(equalToConstant: 32).isActive = true
      b.heightAnchor.constraint(equalTo: b.widthAnchor).isActive = true
      b.addTarget(self, action: sel, for: .touchUpInside)
      stack.addArrangedSubview(b)
    }
    NSLayoutConstraint.activate([
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
  }

  // MARK: – bottom bar (“Next”)
  private func setupBottomBar() {
    let bar = UIView()
    bar.backgroundColor = UIColor.black.withAlphaComponent(0.85)
    bar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bar)

    nextBtn = makePill("Next", #selector(nextPressed))
    nextBtn.translatesAutoresizingMaskIntoConstraints = false
    bar.addSubview(nextBtn)

    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      bar.heightAnchor.constraint(equalToConstant: 90),

      nextBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
      nextBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

      
      nextBtn.widthAnchor.constraint(equalToConstant: 120),
      nextBtn.heightAnchor.constraint(equalToConstant: 44)
    ])
  }
  private func makePill(_ title: String, _ action: Selector) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(title, for: .normal)
    b.titleLabel?.font = .boldSystemFont(ofSize: 15)
    b.tintColor = .white
    b.backgroundColor = .black
    b.layer.cornerRadius = 22
    b.layer.borderWidth = 2
    b.layer.borderColor = UIColor.white.cgColor
    b.addTarget(self, action: action, for: .touchUpInside)
    return b
  }

  // MARK: – back button
  private func setupBackButton() {
    let back = UIButton(type: .system)
    back.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
    back.tintColor = .white
    back.translatesAutoresizingMaskIntoConstraints = false
    back.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
    view.addSubview(back)
    NSLayoutConstraint.activate([
      back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
    ])
  }

  // MARK: – quick-tool taps
  @objc private func textTapped() {
    Haptics.tap()
    let c = EditableCaption()
    c.delegate = self
    c.actionDelegate = self
    c.frame = CGRect(x: 0, y: 0, width: 200, height: 50)
    c.center = view.center
    view.addSubview(c)
    captions.append(c)
  }
  @objc private func filterTapped() { Haptics.tap(); toggleFilterBar() }
    
    @objc private func stickerTapped() {
        Haptics.tap()

        let picker = EmojiPickerVC()
        picker.delegate = self

        // Pop-over on iPad, sheet on iPhone
        picker.modalPresentationStyle = traitCollection.userInterfaceIdiom == .pad
            ? .popover : .pageSheet
        if let pop = picker.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX,
                                    y: view.bounds.maxY - 80,
                                    width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(picker, animated: true)
    }

  // MARK: – heavy-tool tap (trim)
  @objc private func trimTapped() {
    Haptics.tap()
    guard UIVideoEditorController.canEditVideo(atPath: videoURL.path) else {
      Haptics.error(); return
    }
    wasPlayingBeforeTrim = player.timeControlStatus == .playing
    player.pause()
    let editor = UIVideoEditorController()
    editor.videoPath = videoURL.path
    editor.videoQuality = .typeHigh
    editor.delegate = self
    present(editor, animated: true)
  }

  // MARK: – quick “download” (save to Photos)
    @objc private func downloadTapped() {
      Haptics.tap()
      showLoader("Exporting…")
      exportVideo { [weak self] url, _ in
        guard let self else { return }
        hideLoader()
        guard let url else { Haptics.error(); return }

        // save to Photos
        PHPhotoLibrary.requestAuthorization { status in
          guard status == .authorized || status == .limited else { Haptics.error(); return }
          PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
          }) { ok, _ in
            DispatchQueue.main.async {
              ok ? self.toast("Saved to Photos") : Haptics.error()
              if ok { Haptics.ok() }
            }
          }
        }
      }
    }


  // MARK: – “Next” button
    @objc private func nextPressed() {
      Haptics.tap()
      showLoader("Exporting…")
      exportVideo { [weak self] vidURL, pngURL in
        guard let self else { return }
        hideLoader()
        guard let vidURL else { Haptics.error(); return }
        // completion pops PostEditorVC; CustomCameraVC then dismisses itself
          // 1️⃣ Pop the editor itself …
             self.dismiss(animated: true) {
               // 2️⃣ … then tell CustomCameraVC we’re done.
               self.completion?(vidURL, pngURL)
             }
      }
    }
    
    
  // MARK: – background tap
  @objc private func handleViewTap(_ g: UITapGestureRecognizer) {
    view.endEditing(true)
    if let bar = filterBar {
      let pt = g.location(in: view)
      if !bar.frame.contains(pt) { toggleFilterBar() }
    }
  }

  // MARK: – filter bar toggle
  private func toggleFilterBar() {
    if let bar = filterBar { bar.removeFromSuperview(); filterBar = nil; return }

    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.itemSize = CGSize(width: 80, height: 34)
    layout.minimumLineSpacing = 12
    layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    let bar = UICollectionView(frame: .zero, collectionViewLayout: layout)
    bar.backgroundColor = UIColor.black.withAlphaComponent(0.4)
    bar.layer.cornerRadius = 18
    bar.showsHorizontalScrollIndicator = false
    bar.dataSource = self; bar.delegate = self
    bar.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "chip")
    bar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bar)
    filterBar = bar

    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
      bar.heightAnchor.constraint(equalToConstant: 50)
    ])
  }

  // MARK: – live filter preview
  private func applyFilter(named ciName: String?) {
    currentFilterName = ciName
    let newItem = AVPlayerItem(asset: playerItem.asset)

    if let name = ciName, let f = CIFilter(name: name) {
      let comp = AVMutableVideoComposition(asset: playerItem.asset) { req in
        let src = req.sourceImage.clampedToExtent()
        f.setValue(src, forKey: kCIInputImageKey)
        let out = (f.outputImage ?? src).cropped(to: req.sourceImage.extent)
        req.finish(with: out, context: nil)
      }
      if let track = playerItem.asset.tracks(withMediaType: .video).first {
        let s = track.naturalSize.applying(track.preferredTransform)
        comp.renderSize = CGSize(width: abs(s.width), height: abs(s.height))
        comp.sourceTrackIDForFrameTiming = track.trackID
      }
      newItem.videoComposition = comp
    }
    player.replaceCurrentItem(with: newItem)
    player.actionAtItemEnd = .none
    NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: newItem,
      queue: .main) { [weak self] _ in
        self?.player.seek(to: .zero); self?.player.play()
      }
    player.play()
  }

  // MARK: – sticker helper
  private func addSticker(_ img: UIImage) {
    let st = DraggableSticker(image: img)
    st.center = view.center
    st.actionDelegate = self
    view.addSubview(st)
    stickers.append(st)
  }

  // MARK: – EXPORT (video + thumbnail PNG)
    // MARK: – EXPORT (video + thumbnail PNG)
    private func exportVideo(completion: @escaping (URL?, URL?) -> Void) {
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else { return }

        // ───────── 1. Build AVMutableComposition (video + audio) ─────────
        let asset = AVAsset(url: self.videoURL)
        let comp  = AVMutableComposition()

        guard
          let vSrc   = asset.tracks(withMediaType: .video).first,
          let vTrack = comp.addMutableTrack(withMediaType: .video,
                                            preferredTrackID: kCMPersistentTrackID_Invalid)
        else { DispatchQueue.main.async { completion(nil, nil) }; return }

        try? vTrack.insertTimeRange(.init(start: .zero, duration: asset.duration),
                                    of: vSrc, at: .zero)
          
        
          // ─── 1.  First figure out width/height using the *original* matrix ───
          let baseSize   = vSrc.naturalSize.applying(vSrc.preferredTransform)
          let wOriginal  = abs(baseSize.width)
          let hOriginal  = abs(baseSize.height)

          // ─── 2.  Build the final transform ───
          var fixedTransform = vSrc.preferredTransform
          if fromGallery,
             fixedTransform.a == -1, fixedTransform.d == -1,
             fixedTransform.b == 0,  fixedTransform.c == 0 {
              fixedTransform = CGAffineTransform(scaleX: -1, y: -1)
                                 .translatedBy(x: wOriginal, y: hOriginal)
          }

          // ─── 3.  *Now* compute oriented size from that final matrix ───
          let oriented = vSrc.naturalSize.applying(fixedTransform)
          let w = abs(oriented.width)
          let h = abs(oriented.height)

          // 4. Apply the transform only ONCE  (compositor *or* metadata, never both)
          let usingCompositor = (currentFilterName != nil)   // true when a CI filter is picked

          if usingCompositor {
              // a) A CIFilter is chosen → the custom compositor will rotate the pixels.
              vTrack.preferredTransform           = .identity          // clear metadata
              FilterCompositor.preferredTransform = fixedTransform     // compositor gets it
          } else {
              // b) No filter → rely on normal AVFoundation metadata path.
              vTrack.preferredTransform           = fixedTransform     // keep metadata
              FilterCompositor.preferredTransform = .identity          // compositor not used
          }

        if let aSrc = asset.tracks(withMediaType: .audio).first,
           let aTrack = comp.addMutableTrack(withMediaType: .audio,
                                             preferredTrackID: kCMPersistentTrackID_Invalid) {
          try? aTrack.insertTimeRange(.init(start: .zero, duration: asset.duration),
                                      of: aSrc, at: .zero)
        }


        // ───────── 2. AVMutableVideoComposition (rotation + overlays) ─────────
        let vc = AVMutableVideoComposition()
        vc.renderSize    = CGSize(width: abs(oriented.width),
                                  height: abs(oriented.height))
        vc.frameDuration = CMTime(value: 1, timescale: 30)

        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = .init(start: .zero, duration: comp.duration)
        let layerInstr  = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
          
//        layerInstr.setTransform(fixedTransform, at: .zero)
        instr.layerInstructions = [layerInstr]
        vc.instructions         = [instr]

        // ───────── 3. CoreAnimation overlays (captions / stickers) ─────────
        let parent     = CALayer()
        parent.frame   = CGRect(origin: .zero, size: vc.renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        let pvFrame = self.playerLayer.frame             // preview size on screen
        func overlay(from v: UIView) -> CALayer {
          let L = CALayer()
          L.contents = v.snapshotImage().cgImage

          // convert to preview-local coords
          var r = v.frame
          r.origin.x -= pvFrame.minX
          r.origin.y -= pvFrame.minY
          let bottomGap = pvFrame.height - (r.minY + r.height)

          // scale into export pixels
          let sx = vc.renderSize.width  / pvFrame.width
          let sy = vc.renderSize.height / pvFrame.height
          L.frame = CGRect(x: r.minX * sx,
                           y: bottomGap * sy,
                           width:  r.width  * sx,
                           height: r.height * sy)
          return L
        }
        self.captions.forEach { parent.addSublayer(overlay(from: $0)) }
        self.stickers.forEach { parent.addSublayer(overlay(from: $0)) }

        vc.animationTool = AVVideoCompositionCoreAnimationTool(
          postProcessingAsVideoLayer: videoLayer,
          in: parent
        )


          // ───────── 4. Custom compositor (rotation + optional filter) ─────────
          if let name = currentFilterName {          // a filter is chosen
              FilterCompositor.filterName        = name
              vc.customVideoCompositorClass      = FilterCompositor.self
          } else {                                  // no filter
              FilterCompositor.filterName = nil
              layerInstr.setTransform(fixedTransform, at: .zero)   // metadata path
          }
          
        // ───────── 5. Export session ─────────
        guard let export = AVAssetExportSession(
                asset: comp,                                  // AVAsset
                presetName: AVAssetExportPresetHighestQuality)
        else { DispatchQueue.main.async { completion(nil, nil) }; return }

        let outURL = FileManager.default.temporaryDirectory
                      .appendingPathComponent(UUID().uuidString + ".mov")
        export.outputURL        = outURL
        export.outputFileType   = .mov
        export.videoComposition = vc                         // overlays + filter

        export.exportAsynchronously {
          guard export.status == .completed else {
            DispatchQueue.main.async { completion(nil, nil) }; return
          }

          // ───────── 6. Thumbnail ─────────
          let gen = AVAssetImageGenerator(asset: AVAsset(url: outURL))
          gen.appliesPreferredTrackTransform = true
          let cg = try? gen.copyCGImage(at: .zero, actualTime: nil)
          var thumb: URL?
          if let cg, let data = UIImage(cgImage: cg).pngData() {
            let u = FileManager.default.temporaryDirectory
                      .appendingPathComponent(UUID().uuidString + ".png")
            try? data.write(to: u); thumb = u
          }
          DispatchQueue.main.async { completion(outURL, thumb) }
        }
      }
    }




  // MARK: – playback helpers
  private func reloadPreview(with url: URL) {
    player.pause()
    playerItem = AVPlayerItem(url: url)
    player.replaceCurrentItem(with: playerItem)
    player.seek(to: .zero); player.play()
  }
  private func resumeIfNeeded() {
    if wasPlayingBeforeTrim { player.seek(to: .zero); player.play() }
  }

  // MARK: – back
  @objc private func backPressed() {
    Haptics.error()
    dismiss(animated: true) {
      if self.fromGallery,
         let cam = self.presentingViewController as? CustomCameraVC {
        cam.openGallery()
      }
    }
  }
}

// MARK: – helpers
private extension UIView {
  func snapshotImage() -> UIImage {
    UIGraphicsImageRenderer(bounds: bounds)
      .image { ctx in layer.render(in: ctx.cgContext) }
  }
}

// MARK: – UITextView auto-size
extension PostEditorVC: UITextViewDelegate {
  func textViewDidChange(_ tv: UITextView) {
    let sz = tv.sizeThatFits(.init(width: view.bounds.width - 40,
                                   height: .greatestFiniteMagnitude))
    tv.bounds.size = sz
  }
}

// MARK: – EditableCaption delete

extension PostEditorVC: EditableCaptionDelegate, UIColorPickerViewControllerDelegate {

    // already had this:
    func captionDidRequestDelete(_ cap: EditableCaption) {
      Haptics.error()
      cap.removeFromSuperview()
      captions.removeAll { $0 === cap }
    }

    // NEW – colour picker
    func captionDidRequestColourPicker(_ cap: EditableCaption) {
        let picker = UIColorPickerViewController()
        picker.selectedColor = cap.textColor ?? .white
        picker.delegate      = self
        colourTarget = cap                     // keep a pointer
        present(picker, animated: true)
    }

    // UIColorPicker delegate
    func colorPickerViewControllerDidSelectColor(_ vc: UIColorPickerViewController) {
        colourTarget?.textColor = vc.selectedColor
    }
    private var colourTarget: EditableCaption? {
        get { objc_getAssociatedObject(self, &ctKey) as? EditableCaption }
        set { objc_setAssociatedObject(self, &ctKey, newValue, .OBJC_ASSOCIATION_ASSIGN) }
    }
}
private var ctKey = 0


// MARK: – DraggableSticker delete
extension PostEditorVC: DraggableStickerDelegate {
  func stickerDidRequestDelete(_ st: DraggableSticker) {
    Haptics.error()
    st.removeFromSuperview()
    stickers.removeAll { $0 === st }
  }
}

// MARK: – PHPicker delegate
extension PostEditorVC: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let item = results.first?.itemProvider,
          item.canLoadObject(ofClass: UIImage.self) else { return }
    item.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
      guard let self, let img = obj as? UIImage else { return }
      DispatchQueue.main.async { self.addSticker(img) }
    }
  }
}

// MARK: – filter bar collection
extension PostEditorVC: UICollectionViewDataSource, UICollectionViewDelegate {
  func collectionView(_ cv: UICollectionView, numberOfItemsInSection _: Int) -> Int { filters.count }
  func collectionView(_ cv: UICollectionView,
                      cellForItemAt idx: IndexPath) -> UICollectionViewCell {
    let cell = cv.dequeueReusableCell(withReuseIdentifier: "chip", for: idx)
    cell.contentView.subviews.forEach { $0.removeFromSuperview() }

    let l = UILabel(frame: cell.contentView.bounds)
    l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    l.font = .systemFont(ofSize: 13, weight: .medium)
    l.textAlignment = .center; l.textColor = .white
    l.text = filters[idx.item].title
    cell.contentView.addSubview(l)

    cell.backgroundColor = currentFilterName == filters[idx.item].ciName
      ? UIColor.systemPink.withAlphaComponent(0.7)
      : UIColor.darkGray.withAlphaComponent(0.6)
    cell.layer.cornerRadius = 17
    return cell
  }
  func collectionView(_ cv: UICollectionView, didSelectItemAt idx: IndexPath) {
    applyFilter(named: filters[idx.item].ciName)
    cv.reloadData()
  }
}

// MARK: – Apple trimmer delegate
extension PostEditorVC: UINavigationControllerDelegate, UIVideoEditorControllerDelegate {
  func videoEditorController(_ e: UIVideoEditorController,
                             didSaveEditedVideoToPath path: String) {
    e.dismiss(animated: true) {
      let newURL = URL(fileURLWithPath: path)
      self.videoURL = newURL
      self.reloadPreview(with: newURL)
      self.applyFilter(named: self.currentFilterName)
      self.resumeIfNeeded(); Haptics.ok()
    }
  }
  func videoEditorControllerDidCancel(_ e: UIVideoEditorController) {
    e.dismiss(animated: true) { self.resumeIfNeeded() }
  }
  func videoEditorController(_ e: UIVideoEditorController, didFailWithError _: Error) {
    e.dismiss(animated: true) { self.resumeIfNeeded(); Haptics.error() }
  }
}


extension PostEditorVC: EmojiPickerDelegate {
    func emojiPicker(_ picker: EmojiPickerVC, didPick image: UIImage) {
        addSticker(image)          // you already have this helper
    }
}
