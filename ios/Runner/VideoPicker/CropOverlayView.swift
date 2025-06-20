//
//  CropOverlayView.swift
//  YourApp
//
//  Created by ChatGPT on 2025-06-10.
//

import UIKit

/// A draggable / resizable crop overlay that mimics the Photos app.
/// Callers set `onDone` and `onCancel` closures to receive the final crop rectangle (in view coords).
final class CropOverlayView: UIView {

  // MARK: - Public callbacks
  var onDone:   ((CGRect) -> Void)?
  var onCancel: (() -> Void)?

  // MARK: - Configuration
  private let handleSize: CGFloat = 26          // touchable zone for edges / corners
  private let minSide:    CGFloat = 60          // minimum allowed crop width / height

  // MARK: - Internal state
  private var cropRect: CGRect = .zero
  private enum Edge { case none, top, bottom, left, right, tl, tr, bl, br }
  private var activeEdge: Edge = .none
  private var startPoint: CGPoint = .zero

  // Layers
  private let shade  = CAShapeLayer()
  private let border = CAShapeLayer()

  // MARK: - Init
  /// - parameter initial: initial crop rectangle in *view coordinates*; if `nil`, starts nearly full-frame.
  init(frame: CGRect, initial: CGRect? = nil) {
    super.init(frame: frame)
    backgroundColor = .clear          // we draw our own shaded layer

    // Default rect = full screen minus 20-pt inset
    cropRect = initial ?? bounds.insetBy(dx: 20, dy: 20)

    // Semi-transparent shade outside crop
    shade.fillRule = .evenOdd
    shade.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
    layer.addSublayer(shade)

    // White dashed border
    border.strokeColor = UIColor.white.cgColor
    border.lineDashPattern = [8, 5]
    border.fillColor = UIColor.clear.cgColor
    layer.addSublayer(border)

    redraw()

    // One pan gesture handles all dragging/resizing
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    addGestureRecognizer(pan)

    // Top-bar buttons
    addSubview(makeButton(title: "Cancel", action: #selector(cancelTap)))
    addSubview(makeButton(title: "Done",   action: #selector(doneTap)))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: - Layout
  override func layoutSubviews() {
    super.layoutSubviews()
    // Position buttons: left = Cancel, right = Done
    subviews.first?.frame = CGRect(x: 20, y: 30, width: 70, height: 32)
    subviews.last?.frame  = CGRect(x: bounds.maxX - 90, y: 30, width: 70, height: 32)
  }

  private func makeButton(title: String, action: Selector) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(title, for: .normal)
    b.tintColor = .white
    b.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    b.layer.borderWidth = 1
    b.layer.borderColor = UIColor.white.cgColor
    b.layer.cornerRadius = 5
    b.addTarget(self, action: action, for: .touchUpInside)
    return b
  }

  // MARK: - Drawing helpers
  private func redraw() {
    // Shade path = full bounds minus cropRect (even-odd rule)
    let p = UIBezierPath(rect: bounds)
    p.append(UIBezierPath(rect: cropRect))
    shade.path = p.cgPath

    // Border path
    border.path = UIBezierPath(rect: cropRect).cgPath
  }

  // MARK: - Gesture handling
  @objc private func handlePan(_ g: UIPanGestureRecognizer) {
    let point = g.location(in: self)

    switch g.state {
    case .began:
      startPoint = point
      activeEdge = edge(at: point)
    case .changed:
      guard activeEdge != .none else { return }
      let dx = point.x - startPoint.x
      let dy = point.y - startPoint.y
      startPoint = point
      resize(by: dx, dy: dy, edge: activeEdge)
      redraw()
    default:
      activeEdge = .none
    }
  }

  /// Determine which edge/corner is being grabbed
  private func edge(at p: CGPoint) -> Edge {
    let extended  = cropRect.insetBy(dx: -handleSize, dy: -handleSize)
    let inner     = cropRect.insetBy(dx: handleSize, dy: handleSize)

    // Corners first
    if CGRect(x: extended.minX, y: extended.minY, width: handleSize, height: handleSize).contains(p) { return .tl }
    if CGRect(x: extended.maxX-handleSize, y: extended.minY, width: handleSize, height: handleSize).contains(p) { return .tr }
    if CGRect(x: extended.minX, y: extended.maxY-handleSize, width: handleSize, height: handleSize).contains(p) { return .bl }
    if CGRect(x: extended.maxX-handleSize, y: extended.maxY-handleSize, width: handleSize, height: handleSize).contains(p) { return .br }

    // Edges
    if !inner.contains(p) {
      if abs(p.x - cropRect.minX) < handleSize { return .left }
      if abs(p.x - cropRect.maxX) < handleSize { return .right }
      if abs(p.y - cropRect.minY) < handleSize { return .top }
      if abs(p.y - cropRect.maxY) < handleSize { return .bottom }
    }
    return .none
  }

  /// Resize the rect according to which edge is active
  private func resize(by dx: CGFloat, dy: CGFloat, edge: Edge) {
    switch edge {
    case .top, .tl, .tr:
      let newY = max(0, min(cropRect.maxY - minSide, cropRect.origin.y + dy))
      cropRect.origin.y = newY
      cropRect.size.height = cropRect.maxY - newY
    case .bottom, .bl, .br:
      let newH = max(minSide, min(bounds.maxY - cropRect.minY, cropRect.height + dy))
      cropRect.size.height = newH
    default: break
    }

    switch edge {
    case .left, .tl, .bl:
      let newX = max(0, min(cropRect.maxX - minSide, cropRect.origin.x + dx))
      cropRect.origin.x = newX
      cropRect.size.width = cropRect.maxX - newX
    case .right, .tr, .br:
      let newW = max(minSide, min(bounds.maxX - cropRect.minX, cropRect.width + dx))
      cropRect.size.width = newW
    default: break
    }
  }

  // MARK: - Button actions
  @objc private func doneTap()   { onDone?(cropRect) }
  @objc private func cancelTap() { onCancel?() }
}
