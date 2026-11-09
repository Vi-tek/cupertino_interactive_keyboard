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

if failures > 0 {
  print("\(failures) check(s) failed")
  exit(1)
}

print("all checks passed")
