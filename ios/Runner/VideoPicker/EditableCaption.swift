//
//  EditableCaption.swift
//

import UIKit

// MARK: – delegate
protocol EditableCaptionDelegate: AnyObject {
    func captionDidRequestDelete(_ caption: EditableCaption)
    /// double-tap ⇒ user wants to change the text colour
    func captionDidRequestColourPicker(_ caption: EditableCaption)
}

// MARK: – view
final class EditableCaption: UITextView, UIGestureRecognizerDelegate {

    weak var actionDelegate: EditableCaptionDelegate?

    // MARK: – init
    init() {
        super.init(frame: .zero, textContainer: nil)

        // basic look
        backgroundColor = .clear
        textColor       = .white
        font            = .boldSystemFont(ofSize: 28)
        textAlignment   = .center
        isScrollEnabled = false
        showsVerticalScrollIndicator   = false
        showsHorizontalScrollIndicator = false

        // ─── gestures ───
        let pan     = UIPanGestureRecognizer   (target: self, action: #selector(didPan(_:)))
        let pinch   = UIPinchGestureRecognizer (target: self, action: #selector(didPinch(_:)))
        let rotate  = UIRotationGestureRecognizer(target: self, action: #selector(didRotate(_:)))
        let longP   = UILongPressGestureRecognizer(target: self, action: #selector(deleteMe(_:)))
        let doubleT = UITapGestureRecognizer   (target: self, action: #selector(doubleTapped(_:)))
        doubleT.numberOfTapsRequired = 2                // double-tap → colour picker

        [pan, pinch, rotate].forEach { $0.delegate = self }
        addGestureRecognizer(pan)
        addGestureRecognizer(pinch)
        addGestureRecognizer(rotate)
        addGestureRecognizer(longP)
        addGestureRecognizer(doubleT)

        becomeFirstResponder()                           // keyboard up immediately
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: – gesture handlers
    @objc private func didPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: superview)
        center = CGPoint(x: center.x + t.x, y: center.y + t.y)
        g.setTranslation(.zero, in: superview)
    }
    @objc private func didPinch(_ g: UIPinchGestureRecognizer) {
        transform = transform.scaledBy(x: g.scale, y: g.scale)
        g.scale = 1
    }
    @objc private func didRotate(_ g: UIRotationGestureRecognizer) {
        transform = transform.rotated(by: g.rotation)
        g.rotation = 0
    }
    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        actionDelegate?.captionDidRequestColourPicker(self)
    }
    @objc private func deleteMe(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        actionDelegate?.captionDidRequestDelete(self)
    }

    // allow pinch-rotate-pan simultaneously (and with caret shown)
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool { true }
}
