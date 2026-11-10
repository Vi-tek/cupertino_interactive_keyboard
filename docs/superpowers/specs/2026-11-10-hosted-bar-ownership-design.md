# Design Doc: Hosted Bar Owns Its Position, Its Height, and Its Cost

Date: 2026-11-10 · Status: approved approach (bar ownership C + dynamic height + quiet probe)

## Intent & The Why

The first device run of the release fix showed that the hosted bar still misbehaves and added cost:
during an interactive dismissal the bar stretches and detaches, a release still jumps, and the list
lags behind the finger. Separately, a multiline composer cannot grow: the bar keeps forcing a height.

The causes are now known and structural:

1. **The bar is still positioned by `keyboardLayoutGuide`.** The guide is live during the drag, but it
   is the wrong owner for the release and for the bar's height: it snaps on release, and the bar's own
   `safeAreaInsets` change by the 34 pt home-indicator inset as it approaches the bottom. The bar's
   height is `content + safeArea`, the hosted Flutter view is stretched across that height, so a
   34 pt height change is a visible stretch of the composer. The previous transform correction also
   left the bar offset when the guide ended somewhere unexpected (detached state).
2. **The bar's content height is app-supplied and clamped by the bar itself.** A multiline field can
   only request a taller bar from inside the bar; the accessory view is sized to the bar, so the
   composer's measured height is clamped at the current bar height and can never grow.
3. **The probe logs synchronously per frame** (`NSLog` for every bar layout change and every inset
   write) and is on by default in DEBUG. That is main-thread work per frame during exactly the
   gesture it measures — the reported list lag.

## Goals

- The bar travels with the keyboard through open, drag, release and dismissal, with no stretch, no
  snap and no residual offset.
- The bar's height follows its Flutter content automatically; `height` is only an initial fallback.
- The accessory content is never stretched by the bar's safe-area padding.
- The list inset moves 1:1 with the drag and is derived from the same value that positions the bar.
- The probe is off by default and costs nothing unless enabled.
- No change to the public API shape beyond `height` becoming optional.

## Non-Goals / Anti-Goals

- Moving the bar into the keyboard's `inputAccessoryView` (still the long-term option).
- Re-animating the Flutter engine's own inset animation (the engine keeps ownership of open/close;
  the plugin only drives the inset while the drag is in progress, as today).
- App-side layout changes (the uptalk composer only needs to stop passing a fixed height).

## Constraints

- Swift only under `ios/`; Dart changes limited to the plugin's own accessory host and hosted widget.
- The classic `CupertinoInputAccessory` path and non-hosted apps stay untouched.
- The engine's private APIs stay exactly as used today (write inset, target sync, animation
  invalidation) — no new private API.
- The bar must remain a live Flutter view in the second engine.

## Approaches Considered

1. **Keep the transform correction and clamp it.** Rejected: it is a second positioning system on top
   of the guide, it cannot fix a guide that is stale at other moments, and it is what produced the
   offset states seen on device.
2. **Own the bar (selected).** The bar gets a manual bottom constraint. The plugin keeps one value,
   `barInset` (points from the Flutter view bottom to the bar's bottom). Keyboard notifications
   animate the constraint with the notification's duration/curve; an interactive drag moves it from the
   guide's *delta* since the drag began (robust to a stale guide), and the engine inset is computed from
   the same value. The plugin never reads the bar's laid-out rect.
3. **`inputAccessoryView` hosting.** Most native, but it changes the reserved-height contract for every
   app and risks reparenting a Flutter engine's view. Not now.

## How It Works

1. **Bar geometry.** `CIKHostedAccessoryBar` is constrained to the Flutter view's bottom with a bottom
   constraint whose constant is set by `KeyboardManager`. The hosted engine view is pinned to the
   bar's top with the *content* height (not the bar's total height), so the bar's safe-area padding
   never stretches it.
2. **Height.** The bar's total height is `content + safeArea` only while the keyboard is at rest;
   while the keyboard is on screen (or being dragged) the padding is 0. Height changes are applied
   inside the same animation as the bottom constraint when a notification drives the bar, so the
   padding appears and disappears with the keyboard instead of jumping.
3. **Notifications.** For every keyboard notification the engine acts on, the target inset comes from
   `KeyboardGeometry.releaseBandBottom` (top edge; hidden/empty/floating → view bottom); the bar's
   constraint and height animate to it with the notification's duration and curve. The engine keeps
   animating the Flutter inset itself; the plugin does not write insets here.
4. **Drag.** At drag start the manager records the guide's top and the current bar inset. Each frame
   it sets `barInset = insetAtStart + (guideTopAtStart - guideTopNow)` (clamped), moves the bar, and
   writes the engine inset (`barInset * scale`) with the existing target-sync hand-off. The guide is
   therefore only a *live delta source*; if it is stale before the drag, the drag still tracks.
5. **Release.** `willProcessKeyboardNotification` stops the inset driver as today; the bar is animated
   by rule 3, so the composer lands on the keyboard's end position instead of wherever the guide is.
   The transform-correction machinery is deleted.
6. **Dynamic height.** `runCupertinoAccessory` wraps the app's bar in a measuring host: the content is
   laid out with an unbounded height (inside a never-scrollable viewport) so its natural height can be
   measured even when the bar is shorter, and the measured height is pushed to the accessory channel
   (`contentHeight`). Native applies it to the bar and reports the new total to the main isolate, which
   reserves it. `CupertinoKeyboardAccessory.height` becomes optional and only the initial reservation.
7. **Probe.** `CIKTrace` defaults to off in DEBUG and is enabled with `-CIKTrace YES`; release is
   always off. The per-bar-layout log is change-only and the inset log is per write, so an enabled
   trace is a deliberate diagnostic cost, not the default.

## Verification

- `sh ios/KeyboardGeometryTests/run.sh` — checks for the drag delta math and the notification target.
- `flutter test` — new widget test: the accessory host reports the content height through the
  accessory channel; existing tests stay green.
- `flutter analyze` — no new findings.
- `flutter build ios --no-codesign --simulator` — plugin compiles.
- Device run: drag down/up slowly and fast, release at partial and full dismissal, multiline composer
  growth, hidden bar in the dock modes; the bar must stay glued, never stretch, never detach; the list
  must move with the finger with no lag. Enable `-CIKTrace YES` only if a trace is needed.

## What Is Left To The Builder

- Exact constraint plumbing between the bar, the plugin, and the manager.
- The measuring widget's child contract (content must be intrinsically sized; no `Expanded` against
  the unbounded axis) — documented in the README.
- Thresholds (0.5 pt) and trace formatting.

## Addendum (device logs, same day): instant hides and the reserved-height race

The device trace showed two distinct failures that the ownership work does not by itself remove:

1. A hide with duration == 0 takes the engine's "hide immediately" path: FlutterKeyboardInsetManager writes inset 0 in one frame while the keyboard still animates away. The log shows insets 329.6 -> 0 and listH 299.8 -> 595.5 in one step. The plugin now recognises that notification before the engine sees it (ownsInstantHide), skips the engine handler and animates the inset down itself over the keyboard's usual 0.25 s with the same curve that moves the bar.
2. The reserved height stepped 34 pt at the start of a transition, while the native bar's height was still animating: the log shows the single reported bar height=98.5 at the start of the close and listH dropping 34 pt at that instant. Now the home-indicator padding is applied only once the keyboard is gone, and the height event carries the bar's animation duration/curve so the Flutter reservation animates with the bar (TweenAnimationBuilder) instead of jumping.

Verified here: geometry checks, flutter test (18), flutter analyze (4 pre-existing infos), iOS simulator build. Device run still required for pacing.

### Follow-up: no push-up at the end of a collapse

The home-indicator padding is no longer applied after the keyboard is gone (the delayed 0.2 s lift).
It is part of the motion instead: during a drag or an instant hide the padding is
max(0, restingPadding - barInset), so the composer's content reaches its resting place while the
keyboard is still sliding down behind it; in notification-driven transitions it is interpolated over
the notification's duration and curve together with the bar's bottom. The reservation animation
stays in sync, so the list edge and the bar's top keep matching frame for frame.

### Follow-up: the bar mirrors the engine's live inset

The list's motion is the Scaffold body following viewInsets; the accessory used to move on its own
UIView.animate curve, so at every handoff the two producers disagreed (the list appeared to lag or
jump). The bar's position is now a pure function of the engine's live inset: during any keyboard
transition a display link reads physicalViewInsetBottom and lays the bar out from it (bottom = inset,
padding = max(0, restingPadding - inset)). The plugin only produces the inset where the engine cannot
- the interactive drag and the duration-0 instant hide - and in both cases the bar and the inset come
from the same values. The app keeps resizeToAvoidBottomInset: true, so the end of the list stays visible.
