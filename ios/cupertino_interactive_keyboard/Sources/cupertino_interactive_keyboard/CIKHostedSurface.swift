import UIKit

/// The plugin's hosted content surface: the whole area above the keyboard, rendered by a second
/// Flutter engine.
///
/// The container is a clipping view covering the surface rectangle [top, bottom of the Flutter
/// view]. The engine view inside keeps a fixed frame and size and is moved by a transform, so the
/// hosted engine never lays out or rasterises while the keyboard moves: its pixels are cached and
/// Core Animation moves them on the keyboard's own clock. That is what removes the lag a
/// Flutter-rendered list cannot avoid.
final class CIKHostedSurface: UIView {
  /// The home-indicator inset the surface rests above, in points.
  private(set) var restingPadding: CGFloat = 0

  private weak var hostedView: UIView?
  private var topConstraint: NSLayoutConstraint?
  private var hostedHeightConstraint: NSLayoutConstraint?

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    clipsToBounds = true
    backgroundColor = .clear
    isUserInteractionEnabled = true
  }

  required init?(coder: NSCoder) {
    fatalError("CIKHostedSurface does not support coding")
  }

  /// Pins the container to [parent]'s full width, from [top] down to its bottom.
  func attach(to parent: UIView, top: CGFloat, safeAreaBottom: CGFloat) {
    let top = topAnchor.constraint(equalTo: parent.topAnchor, constant: top)
    NSLayoutConstraint.activate([
      leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      trailingAnchor.constraint(equalTo: parent.trailingAnchor),
      top,
      bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
    topConstraint = top
    restingPadding = safeAreaBottom
  }

  /// The height the hosted engine view keeps for a container spanning from [top] to the bottom.
  static func contentHeight(
    parentHeight: CGFloat,
    top: CGFloat,
    safeAreaBottom: CGFloat
  ) -> CGFloat {
    KeyboardGeometry.surfaceContentHeight(
      rectHeight: max(0, parentHeight - top),
      safeAreaBottom: safeAreaBottom
    )
  }

  /// Puts the hosted engine view into the container: fixed height, pinned to the top.
  func host(_ contentView: UIView, contentHeight: CGFloat) {
    contentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentView)
    let height = contentView.heightAnchor.constraint(equalToConstant: contentHeight)
    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
      contentView.topAnchor.constraint(equalTo: topAnchor),
      height,
    ])
    hostedView = contentView
    hostedHeightConstraint = height
  }

  /// Applies a new surface rectangle (same width and bottom, new top and safe area).
  ///
  /// Only called while the keyboard is idle: a resize mid-drag would re-lay the hosted engine out
  /// and reintroduce the lag the surface exists to remove.
  func update(top: CGFloat, safeAreaBottom: CGFloat, parentHeight: CGFloat) {
    topConstraint?.constant = top
    restingPadding = safeAreaBottom
    hostedHeightConstraint?.constant = CIKHostedSurface.contentHeight(
      parentHeight: parentHeight,
      top: top,
      safeAreaBottom: safeAreaBottom
    )
    setNeedsLayout()
  }

  func presentedBottom(in view: UIView) -> CGFloat? {
    guard let hostedView, let superview = hostedView.superview else { return nil }
    let frame = hostedView.layer.presentation()?.frame ?? hostedView.layer.frame
    return superview.convert(CGPoint(x: 0, y: frame.maxY), to: view).y
  }

  func presentedKeyboardInset(in view: UIView) -> CGFloat? {
    KeyboardGeometry.surfaceKeyboardInset(
      translation: presentedTranslation(in: view),
      restingPadding: restingPadding
    )
  }

  /// The vertical translation the surface is presented at, in points (zero at rest).
  ///
  /// For a surface the drawn position is a transform, so this - not a bottom edge - is the number
  /// the trace and the freeze read.
  func presentedTranslation(in view: UIView) -> CGFloat {
    guard let hostedView else { return 0 }
    let presented = hostedView.layer.presentation()?.transform ?? hostedView.layer.transform
    return CATransform3DGetAffineTransform(presented).ty
  }
}

extension CIKHostedSurface: CIKHostedBand {
  var view: UIView { self }

  func apply(inset: CGFloat, padding: CGFloat, animated: Bool, duration: Double, curve: UInt) {
    guard let hostedView else { return }
    let translation = KeyboardGeometry.surfaceTranslation(
      inset: inset,
      restingPadding: restingPadding
    )
    let change = {
      hostedView.transform = CGAffineTransform(translationX: 0, y: translation)
    }
    guard animated, duration > 0 else {
      UIView.performWithoutAnimation(change)
      return
    }
    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: UIView.AnimationOptions(rawValue: curve << 16),
      animations: change
    )
  }

  @discardableResult
  func freezeAtVisiblePosition() -> CGFloat? {
    guard let hostedView, let superview = hostedView.superview else { return nil }
    let translation = presentedTranslation(in: superview)
    hostedView.layer.removeAllAnimations()
    hostedView.transform = CGAffineTransform(translationX: 0, y: translation)
    UIView.performWithoutAnimation { superview.layoutIfNeeded() }
    return KeyboardGeometry.surfaceKeyboardInset(
      translation: translation,
      restingPadding: restingPadding
    )
  }
}
