# Design Doc: Frame-correct engine inset during an interactive keyboard drag

Date: 2026-11-10 · Status: **Reverted** - implemented, did not remove the band. The write-to-frame delay varies per frame (pan write vs deferred main-queue write vs display-link tick vs runloop order), so no fixed lead can be correct for all frames. The code was removed; the finding is recorded in `docs/research/2026-11-10-keyboard-drag-list-lag.md`.
Research: `docs/research/2026-11-10-keyboard-drag-list-lag.md`

## Intent & The Why

On a fast interactive dismissal drag the chat list's bottom edge falls one frame behind the composer/keyboard edge: the last line is cut by the list's viewport and a strip of app background sits between it and the composer (`IMG_7155.png`, 2026-11-10). The cause is two clocks for one value. The plugin writes the keyboard's **current** position to the native bar constraint and to the engine inset (`KeyboardManager.swift:478-557`); the bar is Core-Animation-committed in the write turn and shown at vsync N, while the Flutter frame that consumes the same write is presented one refresh later (raster, then a main-thread `CATransaction`, `FlutterMetalLayer.mm:398-444`). The junction has no absorbing term - list edge = S - viewInsets - reserved, bar top = S - i_native - barHeight - so the one-frame difference is rendered as a cut line plus a background band.

The engine's own notification-driven animation does not have this defect because it writes the inset for the **next presentation time** (`FlutterKeyboardInsetManager.mm:393-403`: `targetTime + frameInterval`, "make sure the new viewport metrics get sent after the begin frame event has processed"). This design does the same for the drag path the plugin drives itself.

## Goals

- The engine inset describes the keyboard's position at the presentation time of the frame that will carry it, so the list edge and the bar edge land together on every drag frame.
- The native bar keeps the current sample, because it is shown in the write turn and must stay glued to the keyboard.
- The change is local to the drag path: notification-driven release, instant hides and the classic accessory path keep their behaviour.
- The lead is a one-line constant, and the per-tick trace exists to calibrate it on device.

## Non-Goals / Anti-Goals

- Hiding the seam with an app-side overscan or a native curtain (research option 3) - a backstop, not this change.
- Delaying the bar to the list's clock (research option 2) - it gives up the bar's 1:1 motion.
- Changing the public Dart API, adding a dependency, or using a new private engine API.

## Constraints

- Swift only under `ios/`; no new dependencies.
- The projection runs only while the finger is dragging; the release animation stays the engine's.
- No device run was available while implementing: the source-level argument plus the repo's host-runnable checks are the gates here, and the device trace is the owner's gate.

## Approaches Considered

1. **Project the engine inset one refresh ahead (selected).** Mirrors what `FlutterKeyboardInsetManager` already does for notifications and what react-native-keyboard-controller shipped in PR #412. Removes the disagreement instead of hiding it, and keeps the bar's 1:1 motion. Risk: extrapolation overshoot when the drag reverses direction, bounded to one frame of travel and self-correcting on the next tick.
2. **Put the bar on the list's clock** (delay the bar one frame, cover the keyboard gap with the bar's own background). Deterministic, no prediction; gives up the bar's 1:1 motion. Rejected for this change; it is the fallback if the projection proves jittery.
3. **Tolerant junction** (list viewport behind an opaque composer with an overscan band). Cheap, reversible, but it does not remove the lag - deferred as a backstop.

## How It Works

1. **Projection math** - `KeyboardGeometry.projectedInset(sample:velocityPerFrame:leadFrames:maxInset:)`: `sample + velocityPerFrame * leadFrames`, clamped to `0...maxInset`. Pure and host-checked.
2. **Velocity** - `KeyboardManager` keeps `previousSampleInset` and `sampleVelocityPerFrame` (the last display-link tick's travel in points), reset with the tracking session and updated **once per display-link tick**, never by the intermediate writes of a frame; `currentFrameInterval` is carried for the trace only.
3. **Two values per frame** - `syncInset()` applies the current sample to the bar and publishes the projected value to the engine, only while `isDraggingKeyboard`; `engineInsetLeadFrames` (1.0 default, 0 disables) scales the lead.
4. **Trace** - a per-tick `frame` line (refresh interval, physical inset, bar model and presentation frame, guide top) plus a Dart twin that prints `viewInsets` per metrics push, so the owner can measure the lead on device.
5. **Release hand-off** - the engine's `targetViewInsetBottom` mirrors the projected value, as before, so the release animation starts from what the engine actually has.

## Verification

- `sh ios/KeyboardGeometryTests/run.sh` - new projection checks.
- `flutter analyze`, `flutter test`.
- `flutter build ios --no-codesign --simulator` from `example/`.
- Owner device run, two passes: one debug run with the trace on (the trace is DEBUG-only, so it reads the mechanics: the `frame` lines carry the lead, the physical inset and the bar's model/presented frame); one profile run without the trace (debug is too slow to judge pacing). On a fast drag the bar's presented bottom and the list's rendered bottom must agree within 0.5 pt. If the list **leads** the bar, the present half was wrong and `engineInsetLeadFrames` goes to 0.5 or 0; if it still trails, the lead goes to 2.

## What Is Left To The Builder

- Calibrate `engineInsetLeadFrames` from the trace (expect 1.0).
- If a residual band is still objectionable after calibration, take research option 3 (app-side overscan) as the backstop; it is independent of this change.
- Decide separately whether the classic `CupertinoInputAccessory` path should get the same projection - it is untouched here.
