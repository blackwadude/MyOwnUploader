//
//  CustomCameraVC.swift
//  Runner
//

import UIKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

final class CustomCameraVC: UIViewController {

  // MARK: – callback  (videoPath, thumbPath)
  var completion: ((String?, String?) -> Void)?

  // MARK: – capture
  private let session = AVCaptureSession()
  private let movieOutput = AVCaptureMovieFileOutput()
  private var currentInput: AVCaptureDeviceInput?
  private var previewLayer: AVCaptureVideoPreviewLayer!
  private let sessionQueue = DispatchQueue(label: "camera.session")

  // MARK: – timer
  private var timerLabel: UILabel!
  private var timer: Timer?
  private var seconds = 0

  // MARK: – buttons & ring
  private let shutter = UIButton(type: .custom)
  private let flipCam = UIButton(type: .system)
  private let torch   = UIButton(type: .system)
  private let gallery = UIButton(type: .system)
  private var ringLayer: CAShapeLayer?

  // MARK: loader
  private var loader: UIActivityIndicatorView?
  private func showLoader() {
    guard loader == nil else { return }
    let sp = UIActivityIndicatorView(style: .large)
    sp.color = .white; sp.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(sp); loader = sp
    NSLayoutConstraint.activate([
      sp.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      sp.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    sp.startAnimating()
  }
  private func hideLoader() {
    loader?.stopAnimating(); loader?.removeFromSuperview(); loader = nil
  }

  // MARK: – lifecycle
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .black
    sessionQueue.async { [weak self] in
      self?.configureSession(); self?.session.startRunning()
    }
    configurePreview(); configureOverlay(); configureTapToFocus()
  }
  override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); Haptics.prime() }
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [weak self] in
      if self?.session.isRunning == true { self?.session.stopRunning() }
    }
    stopTimer(); removeRing()
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    sessionQueue.async { [weak self] in
      if !(self?.session.isRunning ?? true) { self?.session.startRunning() }
    }
  }

  // MARK: – session
  private func configureSession() {
    session.beginConfiguration()
    session.sessionPreset = .high

    guard
      let cam  = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
      let camIn = try? AVCaptureDeviceInput(device: cam),
      session.canAddInput(camIn)
    else { session.commitConfiguration(); return }
    session.addInput(camIn)
    currentInput = camIn

    if let mic = AVCaptureDevice.default(for: .audio),
       let micIn = try? AVCaptureDeviceInput(device: mic),
       session.canAddInput(micIn) { session.addInput(micIn) }

    if session.canAddOutput(movieOutput) {
      session.addOutput(movieOutput)
      if let conn = movieOutput.connection(with: .video),
         conn.isVideoOrientationSupported {
        conn.videoOrientation = .portrait
        conn.isVideoMirrored  = (cam.position == .front)
      }
      movieOutput.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)
    }
    session.commitConfiguration()
  }

  // MARK: – preview
  private func configurePreview() {
    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.frame = view.bounds
    previewLayer.videoGravity = .resizeAspectFill
    if let conn = previewLayer.connection,
       currentInput?.device.position == .front {
      conn.automaticallyAdjustsVideoMirroring = false
      conn.isVideoMirrored = true
    }
    view.layer.addSublayer(previewLayer)
  }

  // MARK: – overlay
  private func configureOverlay() {
    shutter.backgroundColor = .white
    shutter.layer.cornerRadius = 35
    shutter.translatesAutoresizingMaskIntoConstraints = false
    shutter.contentEdgeInsets = .init(top:20,left:20,bottom:20,right:20)
    shutter.addTarget(self,action:#selector(shutterTapped),for:.touchUpInside)
    view.addSubview(shutter)

    gallery.setImage(UIImage(systemName:"photo.on.rectangle"),for:.normal)
    gallery.tintColor = .white; gallery.translatesAutoresizingMaskIntoConstraints = false
    gallery.addTarget(self,action:#selector(openGallery),for:.touchUpInside)
    view.addSubview(gallery)

    flipCam.setImage(UIImage(systemName:"arrow.triangle.2.circlepath"),for:.normal)
    flipCam.tintColor = .white; flipCam.translatesAutoresizingMaskIntoConstraints = false
    flipCam.addTarget(self,action:#selector(switchCamera),for:.touchUpInside)
    view.addSubview(flipCam)

    torch.setImage(UIImage(systemName:"bolt"),for:.normal)
    torch.tintColor = .white; torch.translatesAutoresizingMaskIntoConstraints = false
    torch.addTarget(self,action:#selector(toggleTorch),for:.touchUpInside)
    view.addSubview(torch)

    let close = UIButton(type:.system)
    close.setImage(UIImage(systemName:"xmark"),for:.normal)
    close.tintColor = .white; close.translatesAutoresizingMaskIntoConstraints = false
    close.addTarget(self,action:#selector(cancel),for:.touchUpInside)
    view.addSubview(close)

    timerLabel = UILabel()
    timerLabel.font = .monospacedDigitSystemFont(ofSize:16,weight:.semibold)
    timerLabel.textColor = .systemRed; timerLabel.textAlignment = .center
    timerLabel.text = "00:00"; timerLabel.isHidden = true
    timerLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(timerLabel)

    NSLayoutConstraint.activate([
      shutter.centerXAnchor.constraint(equalTo:view.centerXAnchor),
      shutter.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-40),
      shutter.widthAnchor.constraint(equalToConstant:70),
      shutter.heightAnchor.constraint(equalTo:shutter.widthAnchor),

      gallery.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),
      gallery.centerYAnchor.constraint(equalTo:shutter.centerYAnchor),
      gallery.widthAnchor.constraint(equalToConstant:44),
      gallery.heightAnchor.constraint(equalTo:gallery.widthAnchor),

      close.leadingAnchor.constraint(equalTo:gallery.leadingAnchor),
      close.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:20),

      flipCam.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),
      flipCam.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:20),

      torch.trailingAnchor.constraint(equalTo:flipCam.trailingAnchor),
      torch.topAnchor.constraint(equalTo:flipCam.bottomAnchor,constant:16),

      timerLabel.centerXAnchor.constraint(equalTo:view.centerXAnchor),
      timerLabel.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:20)
    ])
  }

  // MARK: – focus/tap
  private func configureTapToFocus() {
    view.addGestureRecognizer(UITapGestureRecognizer(target:self,
                                                     action:#selector(focusTap(_:))))
  }
  @objc private func focusTap(_ g: UITapGestureRecognizer) {
    Haptics.tap()
    guard let dev = currentInput?.device else { return }
    let pt = previewLayer.captureDevicePointConverted(fromLayerPoint:g.location(in:view))
    sessionQueue.async {
      if dev.isFocusPointOfInterestSupported {
        try? dev.lockForConfiguration()
        dev.focusPointOfInterest = pt; dev.focusMode = .autoFocus
        if dev.isExposurePointOfInterestSupported {
          dev.exposurePointOfInterest = pt; dev.exposureMode = .continuousAutoExposure
        }
        dev.unlockForConfiguration()
      }
    }
  }

  // MARK: – shutter
  @objc private func shutterTapped() {
    Haptics.tap()
    if movieOutput.isRecording {
      movieOutput.stopRecording(); removeRing(); stopTimer()
    } else {
      if let conn = movieOutput.connection(with: .video) {
        if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
        if conn.isVideoMirroringSupported {
          conn.isVideoMirrored = (currentInput?.device.position == .front)
        }
      }
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".mov")
      movieOutput.startRecording(to:url, recordingDelegate:self)
      addRing(); startTimer()
    }
  }
  private func addRing() {
    removeRing()
    let r: CGFloat = 35, center = CGPoint(x:r,y:r)
    let ring = CAShapeLayer()
    ring.path = UIBezierPath(arcCenter:center,radius:r,
                             startAngle:-.pi/2,endAngle:1.5*CGFloat.pi,
                             clockwise:true).cgPath
    ring.fillColor = UIColor.clear.cgColor
    ring.strokeColor = UIColor.systemRed.cgColor
    ring.lineWidth = 4; ring.strokeEnd = 0
    shutter.layer.addSublayer(ring); ringLayer = ring
    let dur = CMTimeGetSeconds(movieOutput.maxRecordedDuration)
    let anim = CABasicAnimation(keyPath:"strokeEnd")
    anim.fromValue = 0; anim.toValue = 1; anim.duration = dur
    anim.timingFunction = CAMediaTimingFunction(name:.linear)
    ring.add(anim, forKey:"progress"); ring.strokeEnd = 1
  }
  private func removeRing() { ringLayer?.removeAllAnimations(); ringLayer?.removeFromSuperlayer(); ringLayer = nil }

  // MARK: – gallery / flip / torch / cancel
  @objc public func openGallery() {
    Haptics.tap()
    var cfg = PHPickerConfiguration(); cfg.filter = .videos; cfg.selectionLimit = 1
    let picker = PHPickerViewController(configuration:cfg)
    picker.delegate = self; present(picker, animated:true)
  }

  @objc private func switchCamera() { flipCamTapped() }
  private func flipCamTapped() {
    sessionQueue.async { [weak self] in
      guard let self, let current = self.currentInput else { return }
      self.session.beginConfiguration(); self.session.removeInput(current)
      let pos: AVCaptureDevice.Position = current.device.position == .back ? .front : .back
      guard let newDev = AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:pos),
            let newIn  = try? AVCaptureDeviceInput(device:newDev),
            self.session.canAddInput(newIn) else {
        self.session.addInput(current); self.session.commitConfiguration(); return
      }
      self.session.addInput(newIn); self.currentInput = newIn
      self.session.commitConfiguration()
    }
  }

  @objc private func toggleTorch() { toggleTorchImpl() }
  private func toggleTorchImpl() {
    guard let dev = currentInput?.device, dev.hasTorch else { return }
    sessionQueue.async {
      try? dev.lockForConfiguration()
      if dev.torchMode == .off {
        try? dev.setTorchModeOn(level:1)
        DispatchQueue.main.async { self.torch.setImage(UIImage(systemName:"bolt.fill"),for:.normal) }
      } else {
        dev.torchMode = .off
        DispatchQueue.main.async { self.torch.setImage(UIImage(systemName:"bolt"),for:.normal) }
      }
      dev.unlockForConfiguration()
    }
  }

  @objc private func cancel() {
    Haptics.error()
    dismiss(animated:true) { self.completion?(nil,nil) }
  }

  // MARK: – timer
  private func startTimer() {
    seconds = 0; timerLabel.text = "00:00"; timerLabel.isHidden = false
    timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
      guard let self else { return }
      seconds += 1
      timerLabel.text = String(format:"%02d:%02d",seconds/60,seconds%60)
    }
  }
  private func stopTimer() { timer?.invalidate(); timer=nil; timerLabel.isHidden = true }

  // MARK: – editor
  private func showEditor(url:URL, fromGallery:Bool) {
    let editor = PostEditorVC(videoURL:url, fromGallery:fromGallery)
    editor.modalPresentationStyle = .fullScreen
    editor.completion = { [weak self] vidURL, thumbURL in
      guard let self else { return }
      Haptics.ok()
      self.dismiss(animated:true) {
        self.completion?(vidURL.path, thumbURL?.path)
      }
    }
    present(editor, animated:true)
  }
}

// MARK: – recording delegate
extension CustomCameraVC: AVCaptureFileOutputRecordingDelegate {
  func fileOutput(_ output:AVCaptureFileOutput, didFinishRecordingTo outputFileURL:URL,
                  from _: [AVCaptureConnection], error:Error?) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      removeRing(); stopTimer()
      if error == nil { self.showEditor(url:outputFileURL, fromGallery:false) }
      else { Haptics.error() }
    }
  }
}

// MARK: – gallery picker
extension CustomCameraVC: PHPickerViewControllerDelegate {
  func picker(_ picker:PHPickerViewController, didFinishPicking results:[PHPickerResult]) {

    guard let item = results.first?.itemProvider,
          item.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
      picker.dismiss(animated:true); return }

    let spinner = UIActivityIndicatorView(style:.large)
    spinner.translatesAutoresizingMaskIntoConstraints = false
    picker.view.addSubview(spinner)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo:picker.view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo:picker.view.centerYAnchor)])
    spinner.startAnimating()

    item.loadFileRepresentation(forTypeIdentifier:UTType.movie.identifier) { [weak self] url,_ in
      guard let self, let src = url else {
        DispatchQueue.main.async {
          spinner.stopAnimating(); picker.dismiss(animated:true)
        }
        return
      }
      let dest = FileManager.default.temporaryDirectory
                  .appendingPathComponent(UUID().uuidString + ".mov")
      try? FileManager.default.copyItem(at:src,to:dest)
      DispatchQueue.main.async {
        spinner.stopAnimating()
        picker.dismiss(animated:false) {
          self.showEditor(url:dest, fromGallery:true)
        }
      }
    }
  }
}
