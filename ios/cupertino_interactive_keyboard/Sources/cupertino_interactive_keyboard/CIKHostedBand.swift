import UIKit

/// The band the plugin positions while the keyboard moves.
///
/// Two views implement it: the hosted accessory bar (a composer strip above the keyboard) and the
/// hosted surface (the whole content area above the keyboard). The manager owns the clock and hands
/// both the same values; a band only applies them. The bar carries its home-indicator padding inside
/// itself, the surface moves a fixed frame by a transform, but from the manager's point of view they
/// are the same object.
protocol CIKHostedBand: AnyObject {
  /// The home-indicator inset the band carries at rest, in points.
  var restingPadding: CGFloat { get }

  /// The band's view, for geometry in the Flutter view's coordinate space.
  var view: UIView { get }

  /// Moves the band to the keyboard position.
  ///
  /// - Parameters:
  ///   - inset: The distance from the Flutter view's bottom to the keyboard's top, in points.
  ///   - padding: The home-indicator padding the band carries while it rests, in points.
  ///   - animated: Whether to animate the change with the keyboard's own duration and curve.
  ///   - duration: The keyboard animation's duration in seconds.
  ///   - curve: The keyboard animation's UIKit curve index.
  func apply(inset: CGFloat, padding: CGFloat, animated: Bool, duration: Double, curve: UInt)

  /// Stops a running animation, pins the band where it is currently drawn and returns the keyboard
  /// inset it was drawn at (for seeding a drag that starts mid-animation).
  @discardableResult
  func freezeAtVisiblePosition() -> CGFloat?

  /// The band's bottom edge in [view]'s coordinates, following the presented (animated) position.
  func presentedBottom(in view: UIView) -> CGFloat?

  /// The keyboard inset the band is presented at, in points.
  func presentedKeyboardInset(in view: UIView) -> CGFloat?
}
