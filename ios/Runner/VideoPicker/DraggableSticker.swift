import UIKit
import UniformTypeIdentifiers

protocol DraggableStickerDelegate: AnyObject {
    func stickerDidRequestDelete(_ sticker: DraggableSticker)
}

final class DraggableSticker: UIImageView, UIGestureRecognizerDelegate {

    weak var actionDelegate: DraggableStickerDelegate?

    init(image: UIImage) {
        super.init(image: image)
        isUserInteractionEnabled = true
        contentMode = .scaleAspectFit

        // ── gestures ──
        let pan   = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
        let longp = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))

        [pan, pinch, rotate].forEach { $0.delegate = self }

        addGestureRecognizer(pan)
        addGestureRecognizer(pinch)
        addGestureRecognizer(rotate)
        addGestureRecognizer(longp)

        frame = CGRect(x: 0, y: 0, width: 120, height: 120)
    }
    required init?(coder: NSCoder) { fatalError() }

    // ── handlers ──
    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: superview)
        center = CGPoint(x: center.x + t.x, y: center.y + t.y)
        g.setTranslation(.zero, in: superview)
    }
    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        transform = transform.scaledBy(x: g.scale, y: g.scale)
        g.scale = 1
    }
    @objc private func rotated(_ g: UIRotationGestureRecognizer) {
        transform = transform.rotated(by: g.rotation)
        g.rotation = 0
    }
    @objc private func longPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        actionDelegate?.stickerDidRequestDelete(self)
    }

    // allow simultaneous gestures
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
