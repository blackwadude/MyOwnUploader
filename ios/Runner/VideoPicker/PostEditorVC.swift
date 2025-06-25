//
//  PostEditorVC.swift
//  Runner
//
//  Updated: 2025-06-26
//

import UIKit
import AVFoundation
import PhotosUI
import Photos
import CoreImage
import Metal

// MARK: – CIFilter compositor (unchanged)
final class FilterCompositor: NSObject, AVVideoCompositing {

  static var filterName: String?
  static var preferredTransform = CGAffineTransform.identity
  private var needsFlip: Bool { Self.preferredTransform.d >= 0 }

  private let q = DispatchQueue(label: "filter.render")
  private var ctx: AVVideoCompositionRenderContext?

  var sourcePixelBufferAttributes: [String: Any]? {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }
  var requiredPixelBufferAttributesForRenderContext: [String: Any] {
    sourcePixelBufferAttributes!
  }
  func renderContextChanged(_ new: AVVideoCompositionRenderContext) { q.sync { ctx = new } }

  func startRequest(_ r: AVAsynchronousVideoCompositionRequest) {
    autoreleasepool {
      guard let src = r.sourceFrame(byTrackID: r.sourceTrackIDs[0].int32Value),
            let dst = ctx?.newPixelBuffer() else {
        r.finish(with: NSError(domain: "FilterCompositor", code: 0)); return }

      var img = CIImage(cvPixelBuffer: src)
      img = img.transformed(by: Self.preferredTransform)
      img = img.transformed(by: .init(translationX: -img.extent.origin.x,
                                      y: -img.extent.origin.y))
      if let s = ctx?.size, needsFlip {
        img = img.transformed(by: .init(scaleX: 1, y: -1).translatedBy(x: 0, y: -s.height))
        img = img.cropped(to: .init(origin: .zero, size: s))
      }
      if let n = Self.filterName, let f = CIFilter(name: n) {
        f.setValue(img, forKey: kCIInputImageKey)
        img = f.outputImage ?? img
      }
      CIContext().render(img, to: dst)
      r.finish(withComposedVideoFrame: dst)
    }
  }
}

// MARK: – main
final class PostEditorVC: UIViewController {

  // MARK: completion
  var completion: ((URL, URL?) -> Void)?

  // MARK: init
  private let fromGallery: Bool
  init(videoURL: URL, fromGallery: Bool) {
    self.videoURL = videoURL; self.fromGallery = fromGallery
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }

  // MARK: video
  private var videoURL: URL
  private var player: AVPlayer!
  private var playerItem: AVPlayerItem!
  private var playerLayer: AVPlayerLayer!
  private var wasPlayingBeforeTrim = false

  // MARK: overlays & filters
  private var captions: [EditableCaption] = []
  private var stickers: [DraggableSticker] = []
  private let filters: [(title: String, ciName: String?)] = [
    ("None", nil), ("Mono","CIPhotoEffectMono"), ("Noir","CIPhotoEffectNoir"),
    ("Fade","CIPhotoEffectFade"), ("Instant","CIPhotoEffectInstant"),
    ("Process","CIPhotoEffectProcess"), ("Chrome","CIPhotoEffectChrome"),
    ("Transfer","CIPhotoEffectTransfer"), ("Tonal","CIPhotoEffectTonal")
  ]
  private var currentFilterName: String?
  private var filterBar: UICollectionView?
  private var startupLoader: UIActivityIndicatorView?

  // MARK: loader helpers
  private func showStartupLoader() {
    guard startupLoader == nil else { return }
    let sp = UIActivityIndicatorView(style: .large)
    sp.color = .white; sp.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(sp); startupLoader = sp
    NSLayoutConstraint.activate([
      sp.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      sp.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    sp.startAnimating()
  }
  private func hideStartupLoader() {
    startupLoader?.stopAnimating()
    startupLoader?.removeFromSuperview()
    startupLoader = nil
  }

  // MARK: UI refs
  private var nextBtn: UIButton!

  // MARK: overlay container (full-screen)
  private let overlayContainer: UIView = {
    let v = UIView(); v.backgroundColor = .clear; v.isUserInteractionEnabled = true; return v }()

  // MARK: loader / toast
  private var loader: UIView?
  private func showLoader(_ message: String? = nil) {
    guard loader == nil else { return }
    let bg = UIView(frame: view.bounds)
    bg.backgroundColor = UIColor.black.withAlphaComponent(0.55)

    let sp = UIActivityIndicatorView(style: .large)
    sp.color = .white; sp.translatesAutoresizingMaskIntoConstraints = false; sp.startAnimating()
    bg.addSubview(sp)

    if let msg = message {
      let l = UILabel(); l.text = msg; l.font = .systemFont(ofSize: 15, weight: .medium)
      l.textColor = .white; l.translatesAutoresizingMaskIntoConstraints = false; bg.addSubview(l)
      NSLayoutConstraint.activate([
        sp.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
        sp.centerYAnchor.constraint(equalTo: bg.centerYAnchor, constant: -12),
        l.topAnchor.constraint(equalTo: sp.bottomAnchor, constant: 12),
        l.centerXAnchor.constraint(equalTo: bg.centerXAnchor)
      ])
    } else {
      NSLayoutConstraint.activate([
        sp.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
        sp.centerYAnchor.constraint(equalTo: bg.centerYAnchor)
      ])
    }
    view.addSubview(bg); loader = bg
  }
  private func hideLoader() { loader?.removeFromSuperview(); loader = nil }

  private func toast(_ text: String) {
    let lbl = UILabel()
    lbl.text = text; lbl.font = .systemFont(ofSize: 14, weight: .semibold)
    lbl.textColor = .white; lbl.textAlignment = .center
    lbl.backgroundColor = UIColor.black.withAlphaComponent(0.8)
    lbl.layer.cornerRadius = 8; lbl.clipsToBounds = true
    lbl.alpha = 0
    lbl.frame = .init(x: 40, y: view.bounds.height*0.25,
                      width: view.bounds.width-80, height: 36)
    view.addSubview(lbl)
    UIView.animate(withDuration:0.3,animations:{ lbl.alpha = 1 }){ _ in
      UIView.animate(withDuration:0.3,delay:1.2,options:[]){ lbl.alpha = 0 } completion:{ _ in
        lbl.removeFromSuperview()}}
  }

  // MARK: life-cycle
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .black
    showStartupLoader()
    setupPlayer()
    view.addSubview(overlayContainer)
    setupUI()
    Haptics.prime()

    // tap to dismiss keyboard / hide filter bar
    let tap = UITapGestureRecognizer(target:self,
                                     action:#selector(backgroundTapped(_:)))
    tap.cancelsTouchesInView = false; view.addGestureRecognizer(tap)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    playerLayer.frame = view.bounds
    playerLayer.videoGravity = .resizeAspect
    overlayContainer.frame = view.bounds
  }

  // MARK: player
  private func setupPlayer() {
    playerItem = AVPlayerItem(url: videoURL)
    player = AVPlayer(playerItem: playerItem)
    player.actionAtItemEnd = .none

    playerItem.asset.loadValuesAsynchronously(forKeys: ["playable"]) { [weak self] in
      DispatchQueue.main.async {
        guard let self else { return }
        self.hideStartupLoader()
        self.player.play()
      }
    }

    NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                           object: playerItem, queue: .main) { [weak self] _ in
      self?.player.seek(to: .zero); self?.player.play() }

    playerLayer = AVPlayerLayer(player: player)
    view.layer.insertSublayer(playerLayer, at: 0)
  }

  // MARK: UI setup
  private func setupUI() {
    let items:[(String,String,Selector)] = [
      ("Aa","textformat",#selector(addTextTapped)),
      ("🙂","face.smiling",#selector(stickerTapped)),
      ("Fx","sparkles",#selector(filterTapped)),
      ("✂︎","scissors",#selector(trimTapped)),
      ("↓","arrow.down.circle",#selector(downloadTapped))]
    let tray = UIStackView(); tray.axis = .vertical; tray.spacing = 22; tray.alignment = .center
    tray.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(tray)
    items.forEach{ _,sf,sel in
      let b = UIButton(type:.system)
      b.setImage(UIImage(systemName:sf),for:.normal)
      b.tintColor = .white
      b.widthAnchor.constraint(equalToConstant:32).isActive = true
      b.heightAnchor.constraint(equalTo:b.widthAnchor).isActive = true
      b.addTarget(self,action:sel,for:.touchUpInside)
      tray.addArrangedSubview(b) }
    NSLayoutConstraint.activate([
      tray.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-16),
      tray.centerYAnchor.constraint(equalTo:view.centerYAnchor)])

    // bottom bar
    let bottom = UIView()
    bottom.backgroundColor = UIColor.black.withAlphaComponent(0.85)
    bottom.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(bottom)
    nextBtn = UIButton(type:.system)
    nextBtn.setTitle("Next",for:.normal)
    nextBtn.titleLabel?.font = .boldSystemFont(ofSize:15)
    nextBtn.tintColor = .white; nextBtn.backgroundColor = .black
    nextBtn.layer.cornerRadius = 22; nextBtn.layer.borderWidth = 2
    nextBtn.layer.borderColor = UIColor.white.cgColor
    nextBtn.addTarget(self,action:#selector(nextPressed),for:.touchUpInside)
    nextBtn.translatesAutoresizingMaskIntoConstraints = false; bottom.addSubview(nextBtn)
    NSLayoutConstraint.activate([
      bottom.leadingAnchor.constraint(equalTo:view.leadingAnchor),
      bottom.trailingAnchor.constraint(equalTo:view.trailingAnchor),
      bottom.bottomAnchor.constraint(equalTo:view.bottomAnchor),
      bottom.heightAnchor.constraint(equalToConstant:90),
      nextBtn.trailingAnchor.constraint(equalTo:bottom.trailingAnchor,constant:-20),
      nextBtn.centerYAnchor.constraint(equalTo:bottom.centerYAnchor),
      nextBtn.widthAnchor.constraint(equalToConstant:120),
      nextBtn.heightAnchor.constraint(equalToConstant:44)])

    // back
    let back = UIButton(type:.system)
    back.setImage(UIImage(systemName:"chevron.backward"),for:.normal)
    back.tintColor = .white; back.translatesAutoresizingMaskIntoConstraints = false
    back.addTarget(self,action:#selector(backPressed),for:.touchUpInside)
    view.addSubview(back)
    NSLayoutConstraint.activate([
      back.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:16),
      back.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:16)])
  }

  // MARK: quick-tool taps
  @objc private func addTextTapped() {
    Haptics.tap()
    let c = EditableCaption()
    c.delegate = self; c.actionDelegate = self
    c.frame = .init(x:0,y:0,width:200,height:50)
    c.center = overlayContainer.center
    overlayContainer.addSubview(c); captions.append(c)
  }
  @objc private func stickerTapped() {
    Haptics.tap()
    let picker = EmojiPickerVC(); picker.delegate = self; present(picker, animated: true)
  }
  private func addSticker(_ img: UIImage) {
    let s = DraggableSticker(image: img)
    s.center = overlayContainer.center
    s.actionDelegate = self
    overlayContainer.addSubview(s); stickers.append(s)
  }
  @objc private func filterTapped() { Haptics.tap(); toggleFilterBar() }

  // MARK: trim
  @objc private func trimTapped() {
    Haptics.tap()
    guard UIVideoEditorController.canEditVideo(atPath: videoURL.path) else { Haptics.error(); return }
    wasPlayingBeforeTrim = player.timeControlStatus == .playing
    player.pause()
    let ed = UIVideoEditorController()
    ed.videoPath = videoURL.path; ed.videoQuality = .typeHigh; ed.delegate = self
    present(ed, animated: true)
  }

  // MARK: download
  @objc private func downloadTapped() {
    Haptics.tap(); showLoader("Exporting…")
    exportVideo { [weak self] url,_ in
      guard let self else { return }
      self.hideLoader(); guard let url else { Haptics.error(); return }
      PHPhotoLibrary.requestAuthorization { status in
        guard status == .authorized || status == .limited else { Haptics.error(); return }
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:url)
        }) { ok,_ in DispatchQueue.main.async{
            ok ? self.toast("Saved to Photos") : self.toast("Save failed")
            ok ? Haptics.ok() : Haptics.error()
        }}
      }
    }
  }

  // MARK: next
  @objc private func nextPressed() {
    Haptics.tap(); showLoader("Exporting…")
    exportVideo { [weak self] vid, thumb in
      guard let self else { return }
      self.hideLoader(); guard let vid else { Haptics.error(); return }
      self.dismiss(animated:true){ self.completion?(vid, thumb) }
    }
  }

  // MARK: back
  @objc private func backPressed() {
    Haptics.error()
    dismiss(animated:true) {
      if self.fromGallery,
         let cam = self.presentingViewController as? CustomCameraVC { cam.openGallery() }
    }
  }

  // MARK: bg tap → dismiss keyboard / hide filter bar
  @objc private func backgroundTapped(_ g: UITapGestureRecognizer) {
    view.endEditing(true)
    if let fb = filterBar,
       !fb.frame.contains(g.location(in: view)) { toggleFilterBar() }
  }

  // MARK: filter bar toggle
  private func toggleFilterBar() {
    if let fb = filterBar { fb.removeFromSuperview(); filterBar = nil; return }
    let lo = UICollectionViewFlowLayout()
    lo.scrollDirection = .horizontal; lo.itemSize = .init(width:80,height:34)
    lo.minimumLineSpacing = 12; lo.sectionInset = .init(top:0,left:16,bottom:0,right:16)
    let fb = UICollectionView(frame:.zero,collectionViewLayout:lo)
    fb.backgroundColor = UIColor.black.withAlphaComponent(0.4)
    fb.layer.cornerRadius = 18; fb.showsHorizontalScrollIndicator = false
    fb.dataSource = self; fb.delegate = self
    fb.register(UICollectionViewCell.self, forCellWithReuseIdentifier:"chip")
    fb.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(fb); filterBar = fb
    NSLayoutConstraint.activate([
      fb.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),
      fb.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),
      fb.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-100),
      fb.heightAnchor.constraint(equalToConstant:50)])
  }

  // MARK: apply filter (live preview)
  private func applyFilter(named ciName:String?) {
    currentFilterName = ciName; FilterCompositor.filterName = ciName
    let newItem = AVPlayerItem(asset: playerItem.asset)
    if let name = ciName, let f = CIFilter(name:name) {
      let comp = AVMutableVideoComposition(asset: playerItem.asset){ req in
        let src = req.sourceImage.clampedToExtent()
        f.setValue(src, forKey:kCIInputImageKey)
        let out = (f.outputImage ?? src).cropped(to: req.sourceImage.extent)
        req.finish(with: out, context: nil) }
      if let track = playerItem.asset.tracks(withMediaType:.video).first {
        let s = track.naturalSize.applying(track.preferredTransform)
        comp.renderSize = .init(width:abs(s.width),height:abs(s.height))
        comp.sourceTrackIDForFrameTiming = track.trackID }
      newItem.videoComposition = comp }
    player.replaceCurrentItem(with:newItem); player.play()
  }

  // MARK: – thumbnail
  private func makeThumbnail(for video: URL) -> URL? {
    let asset     = AVAsset(url: video)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    guard let cg = try? generator.copyCGImage(at: .init(seconds:0, preferredTimescale:600),
                                              actualTime:nil) else { return nil }
    let data  = UIImage(cgImage: cg).jpegData(compressionQuality:0.8)
    let out   = FileManager.default.temporaryDirectory
                 .appendingPathComponent(UUID().uuidString + ".jpg")
    try? data?.write(to: out)
    return out
  }

  // MARK: EXPORT
  private func exportVideo(completion:@escaping(URL?,URL?)->Void){
    DispatchQueue.global(qos:.userInitiated).async { [weak self] in
      guard let self else { return }

      // base comp
      let asset = AVAsset(url:self.videoURL)
      let comp  = AVMutableComposition()
      guard let vSrc = asset.tracks(withMediaType:.video).first,
            let vTrack = comp.addMutableTrack(withMediaType:.video,
                     preferredTrackID:kCMPersistentTrackID_Invalid) else {
        DispatchQueue.main.async{ completion(nil,nil) }; return }
      try? vTrack.insertTimeRange(.init(start:.zero,duration:asset.duration),
                                  of:vSrc,at:.zero)
      if let aSrc = asset.tracks(withMediaType:.audio).first,
         let aTrack = comp.addMutableTrack(withMediaType:.audio,
                     preferredTrackID:kCMPersistentTrackID_Invalid){
        try? aTrack.insertTimeRange(.init(start:.zero,duration:asset.duration),
                                    of:aSrc,at:.zero)
      }

      // renderSize
      let renderSize = self.overlayContainer.bounds.size

      // aspect-fit transform
      let nat  = vSrc.naturalSize.applying(vSrc.preferredTransform)
      let srcW = abs(nat.width), srcH = abs(nat.height)
      let scale = min(renderSize.width/srcW, renderSize.height/srcH)
      let trans = CGAffineTransform(scaleX:scale,y:scale)
        .concatenating(vSrc.preferredTransform)
        .concatenating(.init(translationX:(renderSize.width-srcW*scale)/2,
                             y:(renderSize.height-srcH*scale)/2))

      let vc = AVMutableVideoComposition()
      vc.renderSize = renderSize; vc.frameDuration = CMTime(value:1,timescale:30)
      let instr = AVMutableVideoCompositionInstruction()
      instr.timeRange = .init(start:.zero,duration:comp.duration)
      let lInstr = AVMutableVideoCompositionLayerInstruction(assetTrack:vTrack)
      lInstr.setTransform(trans,at:.zero)
      instr.layerInstructions = [lInstr]; vc.instructions = [instr]

      // overlays
      let parent = CALayer(); parent.frame = .init(origin:.zero,size:renderSize)
      let videoLayer = CALayer(); videoLayer.frame = parent.frame; parent.addSublayer(videoLayer)

      func overlay(from v: UIView) -> CALayer {
        let cg = v.snapshotImage().cgImage!
        let ly = CALayer(); ly.contents = cg

        let ov = self.overlayContainer.bounds
        let sx = renderSize.width  / ov.width
        let sy = renderSize.height / ov.height
        ly.bounds   = .init(x:0,y:0,width: v.bounds.width*sx, height: v.bounds.height*sy)
        ly.position = .init(x: v.center.x*sx, y: (ov.height - v.center.y)*sy)
        ly.anchorPoint = .init(x:0.5,y:0.5)

        let t   = v.transform
        let rot = atan2(t.b,t.a)
        let sX  = sqrt(t.a*t.a + t.c*t.c)
        let sY  = sqrt(t.b*t.b + t.d*t.d)

        ly.setAffineTransform(CGAffineTransform(rotationAngle:-rot).scaledBy(x:sX,y:sY))
        return ly
      }
      captions.forEach{ parent.addSublayer(overlay(from:$0)) }
      stickers.forEach{ parent.addSublayer(overlay(from:$0)) }
      vc.animationTool = AVVideoCompositionCoreAnimationTool(
                           postProcessingAsVideoLayer:videoLayer, in:parent)

      // export
      guard let ex = AVAssetExportSession(asset:comp,
                    presetName:AVAssetExportPresetHighestQuality) else {
        DispatchQueue.main.async{ completion(nil,nil) }; return }
      let out = FileManager.default.temporaryDirectory
                 .appendingPathComponent(UUID().uuidString + ".mov")
      ex.outputURL = out; ex.outputFileType = .mov
      ex.videoComposition = vc; ex.shouldOptimizeForNetworkUse = true
      ex.exportAsynchronously { [weak self] in
        guard let self else { DispatchQueue.main.async{ completion(nil,nil) }; return }
        if ex.status == .completed {
          let thumb = self.makeThumbnail(for: out)
          DispatchQueue.main.async { completion(out, thumb) }
        } else {
          DispatchQueue.main.async { completion(nil,nil) }
        }
      }
    }
  }

  // MARK: reload preview after trimming
  private func reloadPreview(with url: URL) {
    player.pause()
    playerItem = AVPlayerItem(url: url)
    player.replaceCurrentItem(with: playerItem)
    player.seek(to: .zero)
  }
}

// ───────────────── helpers / delegates
private extension UIView{
  func snapshotImage()->UIImage{
    UIGraphicsImageRenderer(bounds:bounds).image{ ctx in
      layer.render(in:ctx.cgContext) }
  }
}

// UITextView auto-size
extension PostEditorVC:UITextViewDelegate{
  func textViewDidChange(_ tv:UITextView){
    let sz = tv.sizeThatFits(.init(width:overlayContainer.bounds.width-40,
                                   height:.greatestFiniteMagnitude))
    tv.bounds.size = sz
  }
}

// EditableCaption delegate + colour
extension PostEditorVC: EditableCaptionDelegate, UIColorPickerViewControllerDelegate {
  func captionDidRequestDelete(_ cap: EditableCaption) {
    Haptics.error(); cap.removeFromSuperview()
    captions.removeAll{ $0 === cap }
  }
  func captionDidRequestColourPicker(_ cap: EditableCaption) {
    let p = UIColorPickerViewController()
    p.selectedColor = cap.textColor ?? .white
    p.delegate = self; colourTarget = cap; present(p, animated: true)
  }
  func colorPickerViewControllerDidSelectColor(_ vc: UIColorPickerViewController) {
    colourTarget?.textColor = vc.selectedColor
  }
  private var colourTarget: EditableCaption? {
    get { objc_getAssociatedObject(self, &ctKey) as? EditableCaption }
    set { objc_setAssociatedObject(self, &ctKey, newValue, .OBJC_ASSOCIATION_ASSIGN) }
  }
}
private var ctKey = 0

// DraggableSticker delete
extension PostEditorVC: DraggableStickerDelegate {
  func stickerDidRequestDelete(_ st: DraggableSticker) {
    Haptics.error(); st.removeFromSuperview()
    stickers.removeAll{ $0 === st }
  }
}

// Emoji picker
extension PostEditorVC: EmojiPickerDelegate {
  func emojiPicker(_ p: EmojiPickerVC, didPick image: UIImage) { addSticker(image) }
}

// PHPicker
extension PostEditorVC: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController,
              didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let item = results.first?.itemProvider,
          item.canLoadObject(ofClass: UIImage.self) else { return }
    item.loadObject(ofClass: UIImage.self) { [weak self] obj,_ in
      guard let self, let img = obj as? UIImage else { return }
      DispatchQueue.main.async { self.addSticker(img) }
    }
  }
}

// filter chips
extension PostEditorVC: UICollectionViewDataSource, UICollectionViewDelegate {
  func collectionView(_ cv: UICollectionView, numberOfItemsInSection _: Int) -> Int { filters.count }
  func collectionView(_ cv: UICollectionView,
                      cellForItemAt i: IndexPath) -> UICollectionViewCell {
    let c = cv.dequeueReusableCell(withReuseIdentifier:"chip", for:i)
    c.contentView.subviews.forEach{ $0.removeFromSuperview() }
    let l = UILabel(frame:c.contentView.bounds)
    l.autoresizingMask = [.flexibleWidth,.flexibleHeight]
    l.font = .systemFont(ofSize:13,weight:.medium)
    l.textAlignment = .center; l.textColor = .white
    l.text = filters[i.item].title; c.contentView.addSubview(l)
    c.layer.cornerRadius = 17
    c.backgroundColor = currentFilterName == filters[i.item].ciName
      ? UIColor.systemPink.withAlphaComponent(0.7)
      : UIColor.darkGray.withAlphaComponent(0.6)
    return c
  }
  func collectionView(_ cv: UICollectionView, didSelectItemAt i: IndexPath) {
    applyFilter(named: filters[i.item].ciName); cv.reloadData()
  }
}

// Apple Trimmer
extension PostEditorVC: UINavigationControllerDelegate,
                         UIVideoEditorControllerDelegate {
  func videoEditorController(_ e: UIVideoEditorController,
                             didSaveEditedVideoToPath path: String) {
    e.dismiss(animated: true) {
      let newURL = URL(fileURLWithPath: path)
      self.videoURL = newURL
      self.reloadPreview(with: newURL)
      self.applyFilter(named: self.currentFilterName)
      if self.wasPlayingBeforeTrim { self.player.play() }
      Haptics.ok()
    }
  }
  func videoEditorControllerDidCancel(_ e: UIVideoEditorController) {
    e.dismiss(animated: true) { if self.wasPlayingBeforeTrim { self.player.play() } }
  }
  func videoEditorController(_ e: UIVideoEditorController, didFailWithError _: Error) {
    e.dismiss(animated: true) { if self.wasPlayingBeforeTrim { self.player.play() }; Haptics.error() }
  }
}
