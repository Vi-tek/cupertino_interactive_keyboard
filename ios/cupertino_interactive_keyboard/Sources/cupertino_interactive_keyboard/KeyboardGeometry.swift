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

  /// The bar inset implied by a band position and the view's height, clamped into the view.
  static func barInset(bandBottom: CGFloat, viewHeight: CGFloat) -> CGFloat {
    max(0, min(viewHeight, viewHeight - bandBottom))
  }

  /// The bar inset for a frame of an interactive drag, from the guide's movement since the drag
  /// started.
  ///
  /// The keyboard layout guide is the only live source of the keyboard's position while it is
  /// dragged, but the bar is no longer positioned by it: the plugin only uses its delta, so a guide
  /// that is stale before the drag still tracks the gesture.
  static func dragBarInset(
    insetAtStart: CGFloat,
    guideTopAtStart: CGFloat,
    guideTop: CGFloat,
    maxInset: CGFloat
  ) -> CGFloat {
    let dragged = insetAtStart + (guideTopAtStart - guideTop)
    return max(0, min(maxInset, dragged))
  }

  /// The bottom edge of the keyboard band in screen points for a release notification.
  ///
  /// A release notification carries the keyboard's end frame: its top edge is the band's bottom. A
  /// hidden, floating or empty keyboard leaves no band, so `nil` puts the band at the view's
  /// bottom. The result is clamped, so a keyboard above the view cannot put the band outside it.
  static func releaseBandBottom(keyboardTop: CGFloat?, viewBottom: CGFloat) -> CGFloat {
    guard let keyboardTop else { return viewBottom }
    return max(0, min(viewBottom, keyboardTop))
  }

  /// The total height of the hosted accessory bar.
  ///
  /// The bar is a fixed-height container: the second Flutter engine renders the composer inside it
  /// and never resizes it, so the only term that changes is the bottom safe area. It is added on
  /// top, so the bar clears the home indicator while it sits at the bottom of the screen and loses
  /// that padding once the keyboard covers the indicator.
  ///
  /// - Parameters:
  ///   - contentHeight: The height the bar's Flutter content asked for, safe area excluded.
  ///   - safeAreaBottom: The bottom safe area inset of the bar.
  /// - Returns: The bar height in points.
  static func hostedAccessoryHeight(
    contentHeight: CGFloat,
    safeAreaBottom: CGFloat
  ) -> CGFloat {
    contentHeight + safeAreaBottom
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


  /// The vertical translation of a hosted keyboard surface for the live keyboard inset.
  ///
  /// A surface keeps a fixed frame and is moved by a transform, so it never resizes while the
  /// keyboard moves: the pixels are cached and Core Animation moves them on the keyboard's own
  /// clock. The surface rests with its bottom edge one safe-area inset above the Flutter view's
  /// bottom (the home indicator strip), so the first `restingPadding` points of keyboard travel do
  /// not move it, and a keyboard that has not moved the surface at all leaves it untranslated.
  ///
  /// - Parameters:
  ///   - inset: The distance from the Flutter view's bottom to the keyboard's top, in points.
  ///   - restingPadding: The bottom safe area inset of the surface, in points.
  /// - Returns: The translation in points, zero or negative (upwards).
  static func surfaceTranslation(inset: CGFloat, restingPadding: CGFloat) -> CGFloat {
    -max(0, inset - restingPadding)
  }

  /// The height of a fixed-content surface's engine view, in points.
  ///
  /// The app reports the rectangle height the surface keeps when it is fully revealed. The engine
  /// view stops one safe-area inset above the Flutter view's bottom, so its top edge lands at
  /// `viewBottom - rectHeight` at every bottom inset: the height and the bottom pin are both
  /// derived from this one number, and a rotation that changes the inset keeps the pair consistent.
  static func fixedSurfaceContentHeight(
    rectHeight: CGFloat,
    safeAreaBottom: CGFloat
  ) -> CGFloat {
    max(0, rectHeight - safeAreaBottom)
  }

  /// The height of a hosted surface's engine view.
  ///
  /// The engine view stops one safe-area inset above the Flutter view's bottom, so the home
  /// indicator strip is painted by the app behind it and the engine view never touches the home
  /// indicator (its safe area is therefore constant while the surface moves).
  ///
  /// - Parameters:
  ///   - rectHeight: The height of the surface rectangle, in points.
  ///   - safeAreaBottom: The bottom safe area inset of the surface, in points.
  /// - Returns: The engine view height in points, never negative.
  static func surfaceContentHeight(
    rectHeight: CGFloat,
    safeAreaBottom: CGFloat
  ) -> CGFloat {
    max(0, rectHeight - safeAreaBottom)
  }

  /// The part of a behind surface's hole that can receive touches at this keyboard inset.
  ///
  /// The app reports the hole it paints (the list area; its bottom is the band's top, which may or
  /// may not be the view's bottom). The band, the composer and anything else the main engine paints
  /// over the hole ride the keyboard, so the live bottom is the hole's own bottom (clamped to the
  /// view) raised by the inset. A touch below it belongs to the main engine.
  ///
  /// - Parameters:
  ///   - hole: The hole the app paints over the surface, in view points.
  ///   - viewHeight: The Flutter view's height, in points.
  ///   - inset: The keyboard inset, in points.
  /// - Returns: The touch-passing part of the hole.
  static func liveHole(hole: CGRect, viewHeight: CGFloat, inset: CGFloat) -> CGRect {
    let bottom = min(hole.maxY, viewHeight) - max(0, inset)
    return CGRect(
      x: hole.minX,
      y: hole.minY,
      width: hole.width,
      height: max(0, bottom - hole.minY)
    )
  }

  /// The keyboard inset a hosted surface's translation was computed from.
  ///
  /// A surface is untranslated for every keyboard inset up to its resting safe-area inset, so this
  /// value saturates at [restingPadding] near the bottom and is only meaningful while the surface
  /// is off its resting position. The manager only uses it to seed a drag, which cannot start
  /// there (the keyboard is visible only once its inset is larger than the resting one).
  ///
  /// - Parameters:
  ///   - translation: The surface's presented vertical translation, in points.
  ///   - restingPadding: The bottom safe area inset of the surface, in points.
  /// - Returns: The keyboard inset the translation corresponds to, in points.
  static func surfaceKeyboardInset(
    translation: CGFloat,
    restingPadding: CGFloat
  ) -> CGFloat {
    restingPadding - translation
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
