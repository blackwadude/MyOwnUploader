import UIKit

final class DraggableLabel: UILabel {

  private var pan: UIPanGestureRecognizer!
  private var pinch: UIPinchGestureRecognizer!

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = true
    textColor = .white
    font = .boldSystemFont(ofSize: 28)
    numberOfLines = 0
    textAlignment = .center

    pan   = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
    addGestureRecognizer(pan)
    addGestureRecognizer(pinch)
  }
  required init?(coder: NSCoder) { fatalError() }

  @objc private func handlePan(_ g: UIPanGestureRecognizer) {
    let t = g.translation(in: superview)
    center = CGPoint(x: center.x + t.x, y: center.y + t.y)
    g.setTranslation(.zero, in: superview)
  }
  @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
    transform = transform.scaledBy(x: g.scale, y: g.scale)
    g.scale = 1
  }
}
