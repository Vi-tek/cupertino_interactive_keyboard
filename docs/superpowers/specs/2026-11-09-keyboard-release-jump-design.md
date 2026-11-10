# Design Doc: Keyboard Release Jump (hosted bar + inset hand-off)

Date: 2026-11-09 · Status: approved approach (B + A probe), C deferred

## Intent & The Why

On the owner's iPhone (iOS 26.5), releasing an interactive keyboard dismissal makes the hosted
composer bar snap to its end position while the keyboard still animates ("a few ms apart", see the
recording frames). The chat list also jumps. Both are the same failure seen through two paths:

- The bar is a pure Auto Layout follower of `flutterView.keyboardLayoutGuide.topAnchor`
  (`CupertinoInteractiveKeyboardPlugin.createHostedAccessory`). The guide is live during the drag but
  has no release-animation contract: at release it is updated once to its end position, so the bar
  snaps. Known on iOS 26.x — react-native-keyboard-controller `769bf60` (closes #1591): "the
  keyboardLayoutGuide is not animating back when keyboard gets hidden".
- `KeyboardManager.syncInset()` derives the engine's bottom inset from that same bar rect and writes
  it raw (`updateViewportMetricsWithInset:`). A bar that reads "at the view bottom" is published as
  inset ~0. The app applies `viewInsets` 1:1 with `Duration.zero` (uptalk
  `bottom_panel.dart:1076,1421-1440`), so one bad write moves the whole feed a full keyboard height
  in one frame.

Audits: `docs/audit/2026-11-09-{engine,uikit,app,verification}.md`.

## Goals

- The bar follows the keyboard's own curve on release-cancel and release-dismiss, not a snap.
- The Flutter inset is never published from a band rect that contradicts the release notification.
- A hidden hosted bar still drives the interactive inset (apps rely on the inset alone when the bar is
  hidden).
- No public Dart API change; no app release.
- One DEBUG-only trace (probe) that discriminates the remaining candidates for the list jump in a
  single device run.

## Non-Goals / Anti-Goals

- Replacing `keyboardLayoutGuide` with plugin-owned geometry (approach C — next phase).
- Patching the Flutter engine's `FlutterKeyboardInsetManager` (`duration == 0` →
  `hideKeyboardImmediately` writes inset 0 in one frame). The probe tells us if that path is hit; if
  so, the plugin defends itself in a follow-up.
- Moving the bar into the keyboard's `inputAccessoryView` (approach D).
- App-side hardening (uptalk's 90 ms scroll-to-end ease, 17 pt reserved-height tick).

## Constraints

- Swift only (`ios/`); no Dart API change.
- The app consumes `viewInsets.bottom` in logical points and reserves the reported bar height; both
  conventions stay.
- Probe must be zero-cost when disabled, DEBUG-only, and removed from release builds.
- No simulator run may be trusted for pacing; the owner runs the device trace.

## Approaches Considered

1. **Trace only** — no; the composer defect is certain from the frames, and the fix is independent.
2. **B: release-correction transform (selected)** — keep the guide constraint; when a release follows
   an active tracking session, animate `bar.transform` from the current visual offset to the offset
   needed at the notification's end position, using the notification's duration/curve. If the guide
   ends on the target (the common case) the correction animates to zero and nothing is held; if it
   ends stale, the final offset is held and the probe logs it. Smallest diff, cannot break layout.
3. **C: owned geometry** — one `keyboardTop` value drives both bar and inset; the guide becomes a
   drag-only delta source. Removes the guide from the release path entirely. Deferred (phase 2).
4. **D: inputAccessoryView** — UIKit owns the bar lifecycle, but it changes the layout contract for
   apps. Rejected for now.

## How It Works (B)

1. **Correction hook.** The `FlutterViewController` keyboard handlers (swizzled) capture
   `wasTracking = KeyboardManager.isTrackingKeyboard` before `willProcessKeyboardNotification`
   stops the session, call the engine's original handler, then call
   `KeyboardManager.keyboardNotificationHandled(notification, wasTracking:)`. If the dismissal
   recognizer still reports a drag at that instant, the correction is deferred one runloop turn so
   the release is not lost.
2. **Target.** `KeyboardGeometry.releaseBandBottom(keyboardTop:viewBottom:)`: the band ends on the
   keyboard's end-frame top edge (`keyboardEnd.minY`), or at the view's bottom for
   `keyboardWillHide`, an empty end frame or a floating keyboard; the result is clamped to the view
   and converted into the Flutter view's coordinate space.
3. **Auto Layout position.** Capture the bar's visual bottom *before* forcing
   `flutterView.layoutIfNeeded()`, then `autoBottom = bar.center.y + bar.bounds.height/2`
   (`center` is unaffected by `transform`, so this is the constraint position).
4. **Animation.** `wanted = targetBarBottom - autoBottom`; the release starts from the band's last
   live position and a reconciliation starts from the held offset. Animate
   `bar.transform.translation.y` with an explicit `fromValue` and the notification's duration and
   curve; when there is nothing to travel, apply the offset without animation. Never animate when
   the release did not follow a tracking session and no correction is held, and never fight a
   UIKit-owned animation (the plugin's own key is ignored).
5. **Rebase, not reset.** A non-zero offset is reconciled on every later keyboard notification:
   when the guide catches up it animates back to zero, and when the guide moves elsewhere the offset
   is re-targeted rather than added on top of the new position. The folded-in release position is
   refreshed at gesture end (`CIKScrollView` `.ended/.cancelled`), so a missing display-link tick
   does not cost the correction. A correction that stays non-zero is logged — that is the "guide is
   stale" signal that justifies phase C.
6. **Hidden bar.**
   `updateHostedAccessoryHidden` keeps `KeyboardManager.hostedAccessoryBar` registered (a hidden view
   still lays out on the guide); only drawing/hit-testing are skipped. This restores drag tracking in
   the app's dock modes, where the composer is in-app and depends on the inset alone.
7. **Probe (A).** `CIKTrace` (DEBUG-only, disabled with `-CIKTrace NO`) logs, change-only:
   keyboard notifications (name, begin/end frames, duration, curve, isLocal, engine-ignores,
   wasTracking), every plugin inset write (band bottom, inset, target, engine read-back of
   `physicalViewInsetBottom`), bar layout changes (bar bottom, guide top), the release correction
   (start/end/target/auto/skipped) and hosted-bar create/hide/teardown. One drag-and-release run on
   the owner's phone answers: does the guide snap (correction works) or stay (held, C needed), and is
   any inset write after the release a single large step (band snap vs the engine's duration-0 path)?

## Verification

- `sh ios/KeyboardGeometryTests/run.sh` — new checks for the release band bottom: keyboard top,
  hidden/floating keyboard, and clamping.
- `flutter analyze` — no new findings.
- `flutter build ios --no-codesign --simulator` — plugin compiles.
- Owner device run with the probe: release-cancel, release-dismiss, rapid repeats; composer must
  travel with the keyboard; no single-frame inset step > ~15 pt; log shows whether the correction
  ended at 0 or was held.
- Phase C is planned only if the log shows held corrections or a residual inset step.

## What Is Left To The Builder

- Exact hook placement in the swizzle and the helper names in `KeyboardManager`.
- How to read `physicalViewInsetBottom` (runtime IMP trick, already used for the setter).
- Threshold values (0.5 pt) and the trace formatting.
