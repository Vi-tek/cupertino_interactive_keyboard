import CoreGraphics
import Foundation

/// The geometry of the interactive keyboard tracking, kept free of UIKit so it can be tested.
enum KeyboardGeometry {
  /// The distance between the bottom of the band and the bottom of the screen.
  ///
  /// The band is the input accessory view of the text input. UIKit moves it in lockstep with the
  /// keyboard, so its bottom edge is the live top edge of the keyboard. The distance is clamped to
  /// zero, because the band leaves the screen when the keyboard is dismissed.
  ///
  /// - Parameters:
  ///   - bandBottom: The bottom edge of the band in screen coordinates.
  ///   - screenBottom: The bottom edge of the screen in screen coordinates.
  /// - Returns: The distance in points, never negative.
  static func bandOffset(bandBottom: CGFloat, screenBottom: CGFloat) -> CGFloat {
    max(0, screenBottom - bandBottom)
  }

  /// How far the accessory has to be moved to stay glued to the band.
  ///
  /// The accessory is laid out at the bottom of the content area, which is the bottom of the view
  /// minus the viewport inset. The band is at the bottom of the view minus its own offset. The
  /// difference between both is the distance the accessory has to be moved.
  ///
  /// - Parameters:
  ///   - viewportInset: The bottom inset the engine currently reports.
  ///   - bandOffset: The distance between the bottom of the band and the bottom of the screen.
  /// - Returns: The distance in points.
  static func accessoryTranslation(viewportInset: CGFloat, bandOffset: CGFloat) -> CGFloat {
    viewportInset - bandOffset
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
