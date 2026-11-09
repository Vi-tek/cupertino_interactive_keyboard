# Design Doc: 1:1 Interactive Keyboard and Accessory Synchronization

## Intent & The Why

When the keyboard is dragged away interactively, it slides down in real time. The Flutter-rendered
accessory bar must stay glued to its top edge, and the content behind it must grow as the keyboard
leaves, revealing more rows — the same thing a native iOS app does.

## What Actually Happens (audited)

1. **The frame-change notifications posted while the keyboard is dragged carry no frame.** iOS
   sends an empty `keyboardWillChangeFrame` while the drag runs and the usable notifications only
   when the gesture ends. The plugin has to read the live position itself, and must not treat the
   empty one as the end of the drag.
2. **During the drag UIKit moves the keyboard container directly.** Its *model* layer holds the
   frame that is about to be rendered; the *presentation* layer still holds the previous frame —
   the one-frame error react-native-keyboard-controller documented in their PR #412.
3. **A write of the viewport inset made from a CADisplayLink is one frame too late.** The engine's
   vsync callback runs before the plugin's display link callback, so the frame that is starting
   never sees the new inset. The write has to happen while the drag is being handled, before the
   vsync.
4. **The accessory cannot be moved on its own.** The bar is laid out at the bottom of the content
   area, and the content area only grows when the viewport inset changes. A widget Transform keeps
   the bar under the keyboard but freezes the list: the rows that should be revealed stay hidden.
   The viewport inset is the single driver.
5. **The engine animates the inset towards every notification** over the notification's duration.
   While the plugin drives the inset, nothing of the engine may animate on top of the plugin's
   values; when the plugin lets go, the engine must take over from the live position.

## Goals

- The bar stays glued to the keyboard's top edge for the whole gesture, with no visible delay.
- The content grows while the keyboard leaves, revealing rows, as on iOS.
- The release animation is the keyboard's own: the plugin hands the live position to the engine
  the moment the gesture ends.
- No change to the public Dart API.

## Non-Goals & Anti-Goals

- Replacing the Flutter-rendered accessory with a native view.
- Moving the bar with a widget Transform while the content stays frozen (the 6dc5869 approach).
- Synthetic keyboard notifications fabricated from gesture geometry.

## Constraints

- No iOS simulator may be run. Verification is static: geometry checks, Dart tests, iOS build.
- The accessory keeps being rendered with Flutter widgets.

## Approaches Considered

- **Flutter gesture detector drives the bar (proposed).** Flutter receives the same touches as the
  dismissal gesture, so a `Listener` could move the bar in the frame the finger moved — no platform
  channel latency. But the content can only grow through the viewport inset, and Dart cannot write
  it. This approach can move the bar, never reveal rows. Rejected by the content requirement.
- **Native push + Dart Transform (committed as 6dc5869).** Geometrically exact, paint-only, no
  relayout; same blind spot: the content stays frozen. Kept in history, not used.
- **Engine viewport inset driven from the live band position (selected).** One driver for the bar
  and the content, written at touch time so it lands in the frame that is about to be rendered.

## How It Works

- `CIKScrollView` forwards `.began` / `.changed` of the dismissal pan to `KeyboardManager`; the
  interactive dismissal notification and the display link also start tracking. The release itself
  is driven by the display link, not by the pan.
- On each change the manager schedules **one** sync on the next main-runloop turn — after UIKit has
  applied the drag and before the next vsync — reads the band's model position, computes the bottom
  inset the viewport needs and writes it with `updateViewportMetricsWithInset:`.
- A `CADisplayLink` repeats the sync every frame while the keyboard is moving, which covers motion
  that does not come from a touch (settling, animation). Tracking stops when the band comes to
  rest, when the band leaves the window, and on the notifications the engine acts on.
- While an animation is in flight the model geometry is corrected by the difference between the
  closest animated ancestor's presentation and model frames.
- Every write also sets the engine's `targetViewInsetBottom` to the same value. The engine ignores
  a notification whose computed inset equals its target — the frame a cancelled drag is released
  at — so keeping the target on the live position guarantees the release always animates from
  where the keyboard actually is, with the keyboard's own curve.
- When the gesture ends iOS posts the final frame. The manager stops driving there and the engine
  animates the release from the last inset the plugin wrote. The band is not read again at that
  moment: UIKit may already hold the resting position it is about to animate to, and writing it
  would snap the content to the end of the release.
- The engine's own inset animation is invalidated on the first write of a tracking session, not
  when tracking starts: while the plugin follows the finger the engine must not animate on top of
  the live values, but a session that never writes must leave a show animation running.
- Notifications the engine ignores (an exactly zero frame change posted while the keyboard is
  dragged, keyboards that belong to another app) do not stop the tracking. A keyboard whose
  accessory view is narrower than the Flutter view is a floating keyboard; the engine gives those
  no inset, so they are not driven either.
- The inset is written in physical pixels: `(flutterViewBottom - bandBottom) * screen.scale`, both
  edges taken in screen points so a non-fullscreen Flutter view cannot skew it.

## Verification

- `ios/KeyboardGeometryTests/run.sh` — inset math, clamping and settle lifecycle, no simulator.
- `flutter test` — the Dart contract is unchanged by this design.
- `flutter analyze`.
- `flutter build ios --no-codesign --simulator` — the plugin compiles.
- Device check by the human: frame pacing and stickiness are only visible on hardware.
