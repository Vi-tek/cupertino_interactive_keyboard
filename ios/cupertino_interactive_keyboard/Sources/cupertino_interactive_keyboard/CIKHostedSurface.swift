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

  /// Whether the surface is inserted below the Flutter view.
  ///
  /// A behind surface shows through the transparent hole the app paints; the hit-test passthrough
  /// uses [holeRect] to decide which touches belong to it.
  var isBehind = false

  /// The hole the app paints over the surface, in the Flutter view's coordinates.
  var holeRect: CGRect = .zero

  private weak var hostedView: UIView?
  private var topConstraint: NSLayoutConstraint?
  private var hostedHeightConstraint: NSLayoutConstraint?

  /// The rectangle height a fixed-content surface keeps, safe area included.
  ///
  /// This is the one number the app owns: the engine view's height and its bottom pin are both
  /// derived from it and the current safe area, so a rotation cannot leave either stale. Nil
  /// follows the rectangle instead.
  private(set) var fixedRectHeight: CGFloat?

  /// Whether the engine view keeps its size while the container's top moves.
  ///
  /// A fixed-content surface is pinned to the container's bottom, so the container's top is a clip
  /// the app can move on every frame without the hosted content laying out again.
  var keepsFixedContent: Bool { fixedRectHeight != nil }

  /// The engine view's bottom pin, so a safe-area change can move it.
  private var contentBottomConstraint: NSLayoutConstraint?

  /// The height the hosted engine view keeps, in points.
  private(set) var contentHeight: CGFloat = 0

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
  ///
  /// A fixed-content view is pinned to the container's bottom instead, so a moving container top
  /// only clips it. [contentBottomInset] lifts it off the container's bottom: a forward surface
  /// leaves the home-indicator strip to the app.
  func host(
    _ contentView: UIView,
    contentHeight: CGFloat,
    fixedRectHeight: CGFloat? = nil,
    contentBottomInset: CGFloat = 0
  ) {
    contentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentView)
    self.contentHeight = contentHeight
    self.fixedRectHeight = fixedRectHeight
    let height = contentView.heightAnchor.constraint(equalToConstant: contentHeight)
    var constraints = [
      contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
      height,
    ]
    if fixedRectHeight != nil {
      let bottom = contentView.bottomAnchor.constraint(
        equalTo: bottomAnchor,
        constant: -contentBottomInset
      )
      constraints.append(bottom)
      contentBottomConstraint = bottom
    } else {
      constraints.append(contentView.topAnchor.constraint(equalTo: topAnchor))
    }
    NSLayoutConstraint.activate(constraints)
    hostedView = contentView
    hostedHeightConstraint = height
  }

  /// Applies a new surface rectangle (same width and bottom, new top and safe area).
  ///
  /// Only called while the keyboard is idle: a resize mid-drag would re-lay the hosted engine out
  /// and reintroduce the lag the surface exists to remove.
  func update(top: CGFloat, safeAreaBottom: CGFloat, parentHeight: CGFloat) {
    // A rectangle that overshoots the view would leave the container with a negative height.
    topConstraint?.constant = min(top, parentHeight)
    restingPadding = safeAreaBottom
    if keepsFixedContent {
      // The top constraint is only this surface's clip. Its height and bottom pin follow the
      // current safe area, so moving the clip never resizes the engine and a rotation keeps the
      // content's top edge at viewBottom - fixedRectHeight.
      applyFixedContent(safeAreaBottom: safeAreaBottom)
    } else {
      hostedHeightConstraint?.constant = CIKHostedSurface.contentHeight(
        parentHeight: parentHeight,
        top: top,
        safeAreaBottom: safeAreaBottom
      )
    }
    setNeedsLayout()
  }

  /// Sets the height a fixed-content surface keeps, from a rectangle height.
  ///
  /// Only a rotation or an app bar cap change gets here; the rectangle the app animates never
  /// resizes the hosted engine.
  func updateContentRectHeight(_ rectHeight: CGFloat, safeAreaBottom: CGFloat) {
    guard keepsFixedContent else {
      return
    }
    fixedRectHeight = rectHeight
    applyFixedContent(safeAreaBottom: safeAreaBottom)
    setNeedsLayout()
  }

  /// Derives the engine view's height and bottom pin from [fixedRectHeight].
  private func applyFixedContent(safeAreaBottom: CGFloat) {
    guard let fixedRectHeight else { return }
    let height = KeyboardGeometry.fixedSurfaceContentHeight(
      rectHeight: fixedRectHeight,
      safeAreaBottom: safeAreaBottom
    )
    restingPadding = safeAreaBottom
    contentBottomConstraint?.constant = -safeAreaBottom
    if abs(height - contentHeight) > 0.5 {
      contentHeight = height
      hostedHeightConstraint?.constant = height
    }
  }

  /// Updates the hosted engine view height (rotation, split view) for a behind surface.
  ///
  /// Only called while the keyboard is idle; a resize mid-drag would re-lay the hosted content out
  /// on a frame that is already in flight.
  func updateContentHeight(_ height: CGFloat) {
    guard abs(height - contentHeight) > 0.5 else { return }
    contentHeight = height
    hostedHeightConstraint?.constant = height
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
