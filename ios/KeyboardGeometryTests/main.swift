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

let screenHeight: CGFloat = 844
let keyboardHeight: CGFloat = 336

// The keyboard is fully shown, so the band sits directly above the keyboard.
let bandBottom = screenHeight - keyboardHeight

expect(
  KeyboardGeometry.bandOffset(bandBottom: bandBottom, screenBottom: screenHeight),
  keyboardHeight,
  "the band offset is the keyboard height while the keyboard is fully shown"
)

// Dragging the keyboard down by 40 points moves the band down by 40 points.
expect(
  KeyboardGeometry.bandOffset(
    bandBottom: bandBottom + 40,
    screenBottom: screenHeight
  ),
  keyboardHeight - 40,
  "dragging the keyboard down by 40 points shrinks the band offset by 40 points"
)

// The band leaves the screen when the keyboard is dismissed.
expect(
  KeyboardGeometry.bandOffset(
    bandBottom: screenHeight + 100,
    screenBottom: screenHeight
  ),
  0,
  "the band offset never becomes negative"
)

// The accessory is laid out at the bottom of the content area, so it is already in the right
// place while the viewport inset matches the band offset.
expect(
  KeyboardGeometry.accessoryTranslation(
    viewportInset: keyboardHeight,
    bandOffset: keyboardHeight
  ),
  0,
  "the accessory does not move while the keyboard is fully shown"
)

// While the keyboard is dragged the viewport inset stays at its resting value, so the accessory
// has to be moved by the distance the keyboard travelled.
expect(
  KeyboardGeometry.accessoryTranslation(
    viewportInset: keyboardHeight,
    bandOffset: keyboardHeight - 40
  ),
  40,
  "the accessory follows the keyboard by the distance it travelled"
)

// The accessory is never moved up, so it cannot end up above the keyboard.
expect(
  KeyboardGeometry.accessoryTranslation(
    viewportInset: keyboardHeight,
    bandOffset: keyboardHeight + 40
  ),
  -40,
  "the accessory is moved up when the band is below its resting position"
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
