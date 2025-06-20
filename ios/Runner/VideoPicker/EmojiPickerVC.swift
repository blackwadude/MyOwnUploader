import UIKit

//  ▸ Call-back so PostEditorVC receives the chosen UIImage
protocol EmojiPickerDelegate: AnyObject {
    func emojiPicker(_ picker: EmojiPickerVC, didPick image: UIImage)
}

final class EmojiPickerVC: UICollectionViewController {

    weak var delegate: EmojiPickerDelegate?

    // A *big* subset (330+) of iOS emojis, grouped roughly by tab row 👇
    private let emojis: [String] = {
        let blocks: [ClosedRange<Int>] = [
            0x1F600...0x1F64F,      // Smileys & People
            0x1F680...0x1F6C5,      // Transport
            0x1F30D...0x1F567,      // Nature + Misc
            0x1F947...0x1F9FF       // Activities / Objects / Symbols
        ]
        return blocks.flatMap { range in
            range.compactMap { Scalar in
                guard let scalar = UnicodeScalar(Scalar) else { return nil }
                return String(Character(scalar))
            }
        }
    }()

    init() {
        let flow = UICollectionViewFlowLayout()
        flow.itemSize                = .init(width: 46, height: 46)
        flow.minimumLineSpacing      = 10
        flow.minimumInteritemSpacing = 10
        flow.sectionInset            = .init(top: 18, left: 18, bottom: 18, right: 18)

        super.init(collectionViewLayout: flow)
        modalPresentationStyle = .popover
        preferredContentSize   = .init(width: 340, height: 370)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: data-source
    override func numberOfSections(in _: UICollectionView) -> Int { 1 }
    override func collectionView(_ c: UICollectionView,
                                 numberOfItemsInSection _: Int) -> Int { emojis.count }

    override func collectionView(_ c: UICollectionView,
                                 cellForItemAt index: IndexPath) -> UICollectionViewCell {

        c.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        let cell = c.dequeueReusableCell(withReuseIdentifier: "cell", for: index)

        // reuse-proof
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let label = UILabel(frame: cell.contentView.bounds)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 34)
        label.text = emojis[index.item]
        cell.contentView.addSubview(label)

        return cell
    }

    // MARK: pick ➜ render ➜ callback
    override func collectionView(_ c: UICollectionView,
                                 didSelectItemAt idx: IndexPath) {
        let emoji = emojis[idx.item]
        let img   = EmojiPickerVC.render(emoji: emoji)
        delegate?.emojiPicker(self, didPick: img)
        dismiss(animated: true)
    }

    /// Convert a single emoji into a transparent PNG UIImage (512 × 512 pt)
    private static func render(emoji: String) -> UIImage {
        let side: CGFloat = 512
        let renderer = UIGraphicsImageRenderer(size: .init(width: side, height: side))
        return renderer.image { ctx in
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font : UIFont.systemFont(ofSize: side * 0.75),
                .paragraphStyle : para
            ]
            let rect = CGRect(x: 0, y: (side - side*0.8)/2,
                              width: side, height: side*0.8)
            emoji.draw(in: rect, withAttributes: attrs)
        }
    }
}
