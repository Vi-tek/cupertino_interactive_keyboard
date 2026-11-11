import Foundation

// A standalone check for the keyboard tracking geometry. Run it with:
//   ios/KeyboardGeometryTests/run.sh

var failures = 0

func expect(
  _ actual: CGFloat,
  _ expected: CGFloat,
  _ message: String,
  accuracy: CGFloat = 0.0001
) {
  if abs(actual - expected) > accuracy {
    print("FAIL: \(message) - expected \(expected), got \(actual)")
    failures += 1
  } else {
    print("ok: \(message)")
  }
}

func expect(
  _ actual: CGRect,
  _ expected: CGRect,
  _ message: String,
  accuracy: CGFloat = 0.0001
) {
  let equal =
    abs(actual.origin.x - expected.origin.x) <= accuracy &&
    abs(actual.origin.y - expected.origin.y) <= accuracy &&
    abs(actual.width - expected.width) <= accuracy &&
    abs(actual.height - expected.height) <= accuracy
  if !equal {
    print("FAIL: \(message) - expected \(expected), got \(actual)")
    failures += 1
  } else {
    print("ok: \(message)")
  }
}

func expect(
  _ actual: Bool,
  _ expected: Bool,
  _ message: String
) {
  if actual != expected {
    print("FAIL: \(message) - expected \(expected), got \(actual)")
    failures += 1
  } else {
    print("ok: \(message)")
  }
}

// Keyboard fully shown: the viewport has to be inset by the keyboard height.
expect(
  KeyboardGeometry.inset(bandBottom: 844 - 336, viewBottom: 844, scale: 3),
  336 * 3,
  "the inset is the keyboard height in physical pixels while the keyboard is fully shown"
)

// Dragged down by 40 points: the inset shrinks by 40 points.
expect(
  KeyboardGeometry.inset(bandBottom: 844 - 336 + 40, viewBottom: 844, scale: 3),
  (336 - 40) * 3,
  "dragging the keyboard down by 40 points shrinks the inset by 40 points"
)

// A non-fullscreen Flutter view uses its own bottom, not the screen's.
expect(
  KeyboardGeometry.inset(bandBottom: 520, viewBottom: 600, scale: 2),
  80 * 2,
  "the inset is measured against the Flutter view's bottom edge"
)

// The band leaves the screen when the keyboard is dismissed: the inset clamps at zero.
expect(
  KeyboardGeometry.inset(bandBottom: 900, viewBottom: 844, scale: 3),
  0,
  "the inset never becomes negative"
)

// The notification target is clamped into the view.
expect(
  KeyboardGeometry.barInset(bandBottom: 844 - 336, viewHeight: 844),
  336,
  "a docked keyboard's band gives the keyboard height as the bar inset"
)

expect(
  KeyboardGeometry.barInset(bandBottom: 900, viewHeight: 844),
  0,
  "a band below the view puts the bar at the view bottom"
)

expect(
  KeyboardGeometry.barInset(bandBottom: -40, viewHeight: 844),
  844,
  "a band above the view cannot push the bar past the view top"
)

// The drag inset follows the guide's delta, so a stale guide does not offset the gesture.
expect(
  KeyboardGeometry.dragBarInset(
    insetAtStart: 300, guideTopAtStart: 508, guideTop: 508, maxInset: 844
  ),
  300,
  "a still guide keeps the inset the drag started with"
)

expect(
  KeyboardGeometry.dragBarInset(
    insetAtStart: 300, guideTopAtStart: 508, guideTop: 548, maxInset: 844
  ),
  260,
  "dragging the keyboard down by 40 shrinks the inset by 40"
)

expect(
  KeyboardGeometry.dragBarInset(
    insetAtStart: 300, guideTopAtStart: 508, guideTop: 900, maxInset: 844
  ),
  0,
  "an inset never goes negative"
)

expect(
  KeyboardGeometry.dragBarInset(
    insetAtStart: 300, guideTopAtStart: 508, guideTop: 300, maxInset: 844
  ),
  508,
  "an inset never grows past the view top"
)

// The release target: the keyboard's top edge becomes the band's bottom edge.
expect(
  KeyboardGeometry.releaseBandBottom(keyboardTop: 844 - 336, viewBottom: 844),
  844 - 336,
  "the band ends on the keyboard's top edge"
)

expect(
  KeyboardGeometry.releaseBandBottom(keyboardTop: nil, viewBottom: 844),
  844,
  "a hidden or floating keyboard puts the band at the view bottom"
)

expect(
  KeyboardGeometry.releaseBandBottom(keyboardTop: -40, viewBottom: 844),
  0,
  "a keyboard above the view cannot put the band above it"
)

expect(
  KeyboardGeometry.releaseBandBottom(keyboardTop: 900, viewBottom: 844),
  844,
  "a keyboard below the view leaves the band at the view bottom"
)

// A docked keyboard's band spans at least the width of the Flutter view.
expect(
  KeyboardGeometry.isDockedBand(bandWidth: 402, viewWidth: 402),
  true,
  "a band as wide as the view belongs to a docked keyboard"
)

// The keyboard spans the screen while the Flutter view can sit in a sheet.
expect(
  KeyboardGeometry.isDockedBand(bandWidth: 402, viewWidth: 320),
  true,
  "a band wider than the view belongs to a docked keyboard"
)

// A floating keyboard's band is narrower than the view, so the plugin must not drive it.
expect(
  KeyboardGeometry.isDockedBand(bandWidth: 240, viewWidth: 402),
  false,
  "a band narrower than the view belongs to a floating keyboard"
)

// The hosted bar is exactly the height its Flutter content asked for plus the bottom safe area.
expect(
  KeyboardGeometry.hostedAccessoryHeight(contentHeight: 56, safeAreaBottom: 34),
  56 + 34,
  "the bar is its content height plus the safe area"
)

// A taller content height makes a taller bar.
expect(
  KeyboardGeometry.hostedAccessoryHeight(contentHeight: 72, safeAreaBottom: 34),
  72 + 34,
  "a taller content height makes a taller bar"
)

// The height is fixed by the content height: nothing clamps it, however tall it is.
expect(
  KeyboardGeometry.hostedAccessoryHeight(contentHeight: 400, safeAreaBottom: 34),
  400 + 34,
  "the bar height is not clamped"
)

// The safe area disappears while the keyboard covers the home indicator, so the bar shrinks by it.
expect(
  KeyboardGeometry.hostedAccessoryHeight(contentHeight: 56, safeAreaBottom: 0),
  56,
  "the bar has no safe area while it sits on the keyboard"
)

// The tracking has to survive the release of the gesture, because the keyboard animates back
// into place afterwards.
expect(
  KeyboardGeometry.shouldStopTracking(
    isDragging: true,
    hasStoppedMoving: true,
    staticTicks: 100
  ),
  false,
  "the tracking continues while the keyboard is dragged"
)

expect(
  KeyboardGeometry.shouldStopTracking(
    isDragging: false,
    hasStoppedMoving: false,
    staticTicks: 100
  ),
  false,
  "the tracking continues while the keyboard animates back into place"
)

expect(
  KeyboardGeometry.shouldStopTracking(
    isDragging: false,
    hasStoppedMoving: true,
    staticTicks: 4
  ),
  false,
  "the tracking continues until the keyboard came to rest"
)

expect(
  KeyboardGeometry.shouldStopTracking(
    isDragging: false,
    hasStoppedMoving: true,
    staticTicks: 5
  ),
  true,
  "the tracking stops once the keyboard came to rest"
)

// A hosted surface keeps a fixed frame and is moved by a transform, so its translation is the
// keyboard position minus the resting safe area, clamped at rest.
expect(
  KeyboardGeometry.surfaceTranslation(inset: 0, restingPadding: 34),
  0,
  "a resting surface is not translated"
)

expect(
  KeyboardGeometry.surfaceTranslation(inset: 34, restingPadding: 34),
  0,
  "a surface at the home-indicator inset is not translated"
)

expect(
  KeyboardGeometry.surfaceTranslation(inset: 336, restingPadding: 34),
  -302,
  "a fully raised surface moves by the keyboard height minus the resting inset"
)

expect(
  KeyboardGeometry.surfaceTranslation(inset: 10, restingPadding: 34),
  0,
  "a surface never translates above its resting position"
)

expect(
  KeyboardGeometry.surfaceContentHeight(rectHeight: 700, safeAreaBottom: 34),
  666,
  "the hosted content height excludes the resting safe area"
)

expect(
  KeyboardGeometry.surfaceContentHeight(rectHeight: 10, safeAreaBottom: 34),
  0,
  "the hosted content height never goes negative"
)

// The trace/freeze read the keyboard inset back out of the surface's translation; the round trip
// is the coupling a drag seed relies on.
expect(
  KeyboardGeometry.surfaceKeyboardInset(translation: 0, restingPadding: 34),
  34,
  "a resting surface reports its resting inset from the zero translation"
)

expect(
  KeyboardGeometry.surfaceKeyboardInset(translation: -302, restingPadding: 34),
  336,
  "a raised surface reports the keyboard height from its translation"
)

// A behind surface's live hole: the app reports the list area, the band and composer above the
// keyboard rise over it, so the touch-passing bottom is the hole's bottom raised by the inset.
expect(
  KeyboardGeometry.liveHole(
    hole: CGRect(x: 0, y: 100, width: 390, height: 744),
    viewHeight: 844,
    inset: 0
  ),
  CGRect(x: 0, y: 100, width: 390, height: 744),
  "a resting keyboard keeps the whole hole touchable"
)

expect(
  KeyboardGeometry.liveHole(
    hole: CGRect(x: 0, y: 100, width: 390, height: 744),
    viewHeight: 844,
    inset: 336
  ),
  CGRect(x: 0, y: 100, width: 390, height: 408),
  "a raised keyboard lifts the band over the hole"
)

expect(
  KeyboardGeometry.liveHole(
    hole: CGRect(x: 0, y: 200, width: 390, height: 300),
    viewHeight: 844,
    inset: 100
  ),
  CGRect(x: 0, y: 200, width: 390, height: 200),
  "a hole above the view bottom is trimmed by the inset from its own bottom"
)

expect(
  KeyboardGeometry.liveHole(
    hole: CGRect(x: 0, y: 600, width: 390, height: 60),
    viewHeight: 844,
    inset: 336
  ),
  CGRect(x: 0, y: 600, width: 390, height: 0),
  "a hole shorter than the inset has nothing touchable"
)

expect(
  KeyboardGeometry.liveHole(
    hole: CGRect(x: 0, y: 100, width: 390, height: 900),
    viewHeight: 844,
    inset: 0
  ),
  CGRect(x: 0, y: 100, width: 390, height: 744),
  "a hole larger than the view is clamped to it"
)

if failures > 0 {
  print("\(failures) check(s) failed")
  exit(1)
}

print("all checks passed")
