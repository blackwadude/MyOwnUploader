//
//  VideoEditVC.swift
//

import UIKit
import AVFoundation
import PhotosUI
import CoreImage

/// Full-screen editor that combines the quick tools you already had
/// (Text, Filter, Sticker) with new heavy tools we’ll wire in next
/// (Trim, Crop, Flip, Aspect).  Heavy tools are TODO stubs for now.
final class VideoEditVC: UIViewController {

    // MARK: – public
    var completion: ((URL) -> Void)?

    // MARK: – init / video
    private var videoURL: URL
    init(videoURL: URL, completion: ((URL) -> Void)? = nil) {
        self.videoURL = videoURL
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: – player
    private lazy var player = AVPlayer(url: videoURL)
    private lazy var playerLayer: AVPlayerLayer = {
        let l = AVPlayerLayer(player: player)
        l.videoGravity = .resizeAspectFill
        return l
    }()

    // MARK: – overlays
    private var captions: [EditableCaption] = []
    private var stickers: [DraggableSticker] = []

    // MARK: – filters
    private let filters: [(title: String, ciName: String?)] = [
        ("None", nil), ("Mono", "CIPhotoEffectMono"), ("Noir", "CIPhotoEffectNoir"),
        ("Fade", "CIPhotoEffectFade"), ("Instant", "CIPhotoEffectInstant"),
        ("Process", "CIPhotoEffectProcess")
    ]
    private var currentFilterName: String?
    private var filterBar: UICollectionView?

    // MARK: – lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupPlayerLayer()
        setupSideTray()
        setupBottomBar()
        addTapToTogglePlay()

        player.play()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
    }

    // MARK: – player helpers
    private func setupPlayerLayer() {
        view.layer.addSublayer(playerLayer)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloop),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem)
    }
    @objc private func reloop() { player.seek(to: .zero); player.play() }
    private func addTapToTogglePlay() {
        view.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(togglePlay)))
    }
    @objc private func togglePlay() {
        view.endEditing(true) 
        player.timeControlStatus == .paused ? player.play() : player.pause()
    }

    // MARK: – side tray
    private func setupSideTray() {
        let tools: [(String,String,Selector)] = [
            ("Aa",     "textformat",             #selector(textTapped)),
            ("Fx",     "sparkles",               #selector(filterTapped)),
            ("🙂",      "face.smiling",           #selector(stickerTapped)),
            ("Trim",   "scissors",               #selector(openTrim)),
            ("Crop",   "crop",                   #selector(openCrop)),
            ("Flip",   "arrow.left.and.right",   #selector(openFlip)),
            ("Aspect", "square.grid.3x3",        #selector(openAspect))
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        tools.forEach { _, sf, sel in
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: sf), for: .normal)
            b.tintColor = .white
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true
            b.heightAnchor.constraint(equalTo: b.widthAnchor).isActive = true
            b.addTarget(self, action: sel, for: .touchUpInside)
            stack.addArrangedSubview(b)
        }

        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: – bottom bar (Done)
    private func setupBottomBar() {
        let bar = UIView()
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let doneBtn = makePill("Done", #selector(doneTapped))
        bar.addSubview(doneBtn); doneBtn.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 90),

            doneBtn.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            doneBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            doneBtn.widthAnchor.constraint(equalToConstant: 120),
            doneBtn.heightAnchor.constraint(equalToConstant: 44)
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

    // MARK: – quick-tool actions
    @objc private func textTapped() {
        let cap = EditableCaption()
        cap.delegate = self
        cap.actionDelegate = self
        cap.frame = CGRect(x: 0, y: 0, width: 200, height: 50)
        cap.center = view.center
        view.addSubview(cap); captions.append(cap)
    }

    @objc private func filterTapped() { toggleFilterBar() }

    @objc private func stickerTapped() {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: – heavy-tool stubs
    @objc private func openTrim()   { print("TODO: Trim UI") }
    @objc private func openCrop()   { print("TODO: Crop UI") }
    @objc private func openFlip()   { print("TODO: Flip operation") }
    @objc private func openAspect() { print("TODO: Aspect-ratio UI") }

    // MARK: – filter bar helpers
    private func toggleFilterBar() {
        if let bar = filterBar {               // hide if already shown
            bar.removeFromSuperview()
            filterBar = nil; return
        }

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 34)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        let bar = UICollectionView(frame: .zero, collectionViewLayout: layout)
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        bar.layer.cornerRadius = 18
        bar.showsHorizontalScrollIndicator = false
        bar.dataSource = self
        bar.delegate = self
        bar.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "chip")
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar); filterBar = bar

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
            bar.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func applyFilter(named ciName: String?) {
        currentFilterName = ciName
        let newItem = AVPlayerItem(asset: player.currentItem!.asset)

        if let name = ciName, let f = CIFilter(name: name) {
            let comp = AVMutableVideoComposition(asset: player.currentItem!.asset) { req in
                let src = req.sourceImage.clampedToExtent()
                f.setValue(src, forKey: kCIInputImageKey)
                let out = (f.outputImage ?? src).cropped(to: req.sourceImage.extent)
                req.finish(with: out, context: nil)
            }
            if let track = player.currentItem!.asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                comp.renderSize = CGSize(width: abs(size.width), height: abs(size.height))
                comp.sourceTrackIDForFrameTiming = track.trackID
            }
            newItem.videoComposition = comp
        }

        player.replaceCurrentItem(with: newItem)
        player.play()
    }

    // MARK: – Done
    @objc private func doneTapped() {
        player.pause()
        completion?(videoURL)           // returns original clip for now
        dismiss(animated: true)
    }
}

// MARK: – captions auto-resize
extension VideoEditVC: UITextViewDelegate {
    func textViewDidChange(_ tv: UITextView) {
        let size = tv.sizeThatFits(CGSize(width: view.bounds.width - 40,
                                          height: .greatestFiniteMagnitude))
        tv.bounds.size = size
    }
}
extension VideoEditVC: EditableCaptionDelegate {
    func captionDidRequestDelete(_ cap: EditableCaption) {
        cap.removeFromSuperview()
        captions.removeAll { $0 === cap }
    }
}

// MARK: – stickers
extension VideoEditVC: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let item = results.first?.itemProvider,
              item.canLoadObject(ofClass: UIImage.self) else { return }
        item.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
            guard let self, let img = obj as? UIImage else { return }
            DispatchQueue.main.async {
                let st = DraggableSticker(image: img)
                st.center = self.view.center
                st.actionDelegate = self
                self.view.addSubview(st); self.stickers.append(st)
            }
        }
    }
}
extension VideoEditVC: DraggableStickerDelegate {
    func stickerDidRequestDelete(_ st: DraggableSticker) {
        st.removeFromSuperview()
        stickers.removeAll { $0 === st }
    }
}

// MARK: – filter bar collection
extension VideoEditVC: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        filters.count
    }
    func collectionView(_ cv: UICollectionView,
                        cellForItemAt idx: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "chip", for: idx)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let lbl = UILabel(frame: cell.contentView.bounds)
        lbl.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.textAlignment = .center
        lbl.textColor = .white
        lbl.text = filters[idx.item].title
        cell.contentView.addSubview(lbl)

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
