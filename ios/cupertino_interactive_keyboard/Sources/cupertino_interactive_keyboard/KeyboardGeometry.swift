import CoreGraphics
import Foundation

/// The geometry of the interactive keyboard tracking, kept free of UIKit so it can be tested.
enum KeyboardGeometry {
  /// The bottom view inset in physical pixels for a keyboard whose band currently ends at
  /// `bandBottom`.
  ///
  /// The band is the plugin's input accessory view. UIKit moves it in lockstep with the keyboard,
  /// so its bottom edge is the live top edge of the keyboard, and the viewport has to be inset by
  /// the distance between the Flutter view's bottom edge and that edge.
  ///
  /// - Parameters:
  ///   - bandBottom: The bottom edge of the band in screen coordinates.
  ///   - viewBottom: The bottom edge of the Flutter view in screen coordinates.
  ///   - scale: The scale factor of the screen.
  /// - Returns: The inset in physical pixels, never negative.
  static func inset(bandBottom: CGFloat, viewBottom: CGFloat, scale: CGFloat) -> CGFloat {
    max(0, viewBottom - bandBottom) * scale
  }

  /// Whether the band belongs to a docked keyboard.
  ///
  /// Floating and split keyboards carry no engine inset, so the plugin must not drive those. A
  /// docked keyboard's accessory view spans at least the width of the Flutter view; a narrower one
  /// belongs to a floating keyboard. It can be wider, because the keyboard spans the screen while
  /// the Flutter view may sit in a sheet.
  static func isDockedBand(bandWidth: CGFloat, viewWidth: CGFloat) -> Bool {
    bandWidth >= viewWidth - 1
  }

  /// Whether the interactive tracking can be stopped.
  ///
  /// The tracking has to survive the release of the gesture, because the keyboard animates back
  /// into place afterwards. It may only stop once the keyboard has come to rest.
  ///
  /// - Parameters:
  ///   - isDragging: Whether the user is currently dragging the keyboard.
  ///   - hasStoppedMoving: Whether the keyboard did not move since the previous frame.
  ///   - staticTicks: The number of consecutive frames the keyboard did not move.
  /// - Returns: Whether the tracking should stop.
  static func shouldStopTracking(
    isDragging: Bool,
    hasStoppedMoving: Bool,
    staticTicks: Int
  ) -> Bool {
    !isDragging && hasStoppedMoving && staticTicks >= 5
  }
}
