# Design Doc: 1:1 Interactive Keyboard and Accessory Synchronization

## Intent & The Why
When interactively dismissing the iOS keyboard in Flutter (dragging the list down), the native
keyboard slides down in real time. The Flutter-rendered accessory bar must move down with it,
staying glued to the top edge of the keyboard, without any visible delay.

## Root Causes (audited)

1. **The engine animated the inset towards a stale target.**
   `FlutterKeyboardInsetManager.handleKeyboardNotification` starts an animation of the viewport
   inset over the animation duration of the notification and samples it per vsync. While the
   keyboard is dragged the duration is zero, but the animation still costs a frame and the inset
   trails the keyboard.
2. **The live position was read one frame too late.**
   The position of the keyboard was read from the *presentation* layer inside a
   `CADisplayLink` callback. A display link fires *before* the next frame is rendered, so the
   presentation layer still holds the value of the previous frame — a guaranteed frame of delay.
   This is the same finding react-native-keyboard-controller documented in their PR #412
   ("we always read a value for a previous frame").
3. **The engine and the plugin fought over the same value.**
   The plugin wrote the viewport inset directly while the engine kept animating it, so the two
   writers interleaved and the accessory visibly detached from the keyboard.
4. **The tracking stopped at the wrong moment.**
   The tracking was torn down as soon as the drag gesture ended, while the keyboard was still
   animating back into place.

## Goals
- The accessory stays glued to the top edge of the keyboard for the whole gesture.
- The release animation is handled by the engine, so it matches the curve of the keyboard exactly.
- No visible delay between the keyboard and the accessory.

## Non-Goals & Anti-Goals
- Replacing the Flutter-rendered accessory with a native one. The plugin keeps rendering the
  accessory with Flutter widgets.
- Changing the public Dart API.

## Constraints
- No iOS simulator may be run for development or verification.

## Approach

**The native input accessory view is the reference.** `CIKInputAccessoryView` is the real
`inputAccessoryView` of the Flutter text input, so UIKit moves it in lockstep with the keyboard.
Its bottom edge is the live top edge of the keyboard, and the Flutter accessory has to be drawn
exactly there.

**The plugin drives the viewport inset itself during the drag.**

- `CIKScrollView` starts the tracking when the pan gesture begins, before the keyboard moves.
- Every vsync the plugin reads the live position of the band and writes the resulting inset
  straight into the engine with `updateViewportMetricsWithInset:`, bypassing the animation
  machinery of the engine. The inset therefore follows the keyboard instead of easing towards it.
- The band is read from the **model** layer while the keyboard is dragged, because UIKit moves it
  directly and the model already holds the position of the frame that is about to be rendered.
  When the keyboard animates back into place, the closest animated ancestor is used to correct
  the model geometry by the offset that is still missing.
- While the plugin is in charge, the notifications of the drag are not handed over to the engine
  and the target inset of the engine is kept in sync, so the engine does not animate the same
  value a second time.
- The tracking keeps running until the keyboard came to rest, so the release animation is not cut
  off half way.

## Verification
- `ios/KeyboardGeometryTests/run.sh` checks the geometry and the lifecycle of the tracking
  without a simulator.
- `flutter test` covers the Dart side.
- `flutter build ios --no-codesign --simulator` verifies that the plugin compiles.
