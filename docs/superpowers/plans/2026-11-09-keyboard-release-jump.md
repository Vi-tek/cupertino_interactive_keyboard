# Keyboard Release Jump Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the hosted composer bar ride the keyboard's own release animation instead of snapping, keep the inset driver alive for a hidden bar, and add a DEBUG-only trace that confirms the remaining list-jump mechanism on device.

**Architecture:** Keep the existing `keyboardLayoutGuide` constraint and Auto Layout untouched. When a keyboard release follows an active interactive-tracking session, animate a `transform` correction on the bar from its current visual offset to the offset implied by the notification's end keyboard frame, using the notification's duration/curve, and hold the residual offset if the guide ends stale. The probe logs notification geometry, every inset write with the engine read-back, bar/guide layout and the correction so one device run settles the remaining questions.

**Tech Stack:** Swift, UIKit, Objective-C runtime (private Flutter engine APIs), Foundation. No Dart API change.

**Spec:** `docs/superpowers/specs/2026-11-09-keyboard-release-jump-design.md`

## Global Constraints

- Swift only under `ios/`; no changes to `lib/`, `example/` or the Dart API.
- Probe is DEBUG-only, zero-cost when disabled, and reads `-CIKTrace NO` to switch off.
- No simulator is trusted for pacing; owner verifies on the iPhone.
- Existing geometry checks (`sh ios/KeyboardGeometryTests/run.sh`) must stay green.
- Do not commit; the owner commits after review.

## Review Focus

1. Release-cancel while the bar is at rest: no correction should be applied on a normal keyboard show/hide (the guide owns that animation) — only a release that followed an active tracking session.
2. Guide that actually animates on release (possible on older iOS): the correction must be skipped when the bar's layer already has an in-flight `position` animation, or the bar would double-move.
3. Held residual correction: a later keyboard show must rebase it, and a later drag must clear it; otherwise the composer rides offset.
4. Hidden bar: the plugin must still track drags (app's dock modes depend on the inset alone) and must not resurrect drawing/hit-testing.
5. Trace must not leak into release builds and must not spam per frame (change-only logging).

---

### Task 1: Geometry helper + checks for the release target

**Files:**
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardGeometry.swift`
- Test: `ios/KeyboardGeometryTests/main.swift`

**Interfaces:**
- Produces: `KeyboardGeometry.releaseBandBottom(keyboardTop: CGFloat?, viewBottom: CGFloat) -> CGFloat` — the band's bottom in screen points for a release: the keyboard's top edge when it is docked, the view's bottom for `nil` (hidden, empty or floating keyboard), clamped into the view.

- [ ] **Step 1: Add failing checks** to `ios/KeyboardGeometryTests/main.swift` (after the inset checks), with `viewBottom = 844`:

```swift
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
```

- [ ] **Step 2: Run and confirm it fails to compile**

Run: `sh ios/KeyboardGeometryTests/run.sh`
Expected: FAIL — `releaseBandBottom` does not exist.

- [ ] **Step 3: Implement `releaseBandBottom`** in `KeyboardGeometry.swift`:

```swift
static func releaseBandBottom(keyboardTop: CGFloat?, viewBottom: CGFloat) -> CGFloat {
  guard let keyboardTop else { return viewBottom }
  return max(0, min(viewBottom, keyboardTop))
}
```

- [ ] **Step 4: Run and confirm it passes**

Run: `sh ios/KeyboardGeometryTests/run.sh`
Expected: `all checks passed`.

### Task 2: DEBUG trace (probe A)

**Files:**
- Create: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CIKTrace.swift`
- Modify: `KeyboardManager.swift`, `FlutterViewController+Swizzle.swift`, `CIKHostedAccessoryBar.swift`, `CupertinoInteractiveKeyboardPlugin.swift`

**Interfaces:**
- Produces: `CIKTrace.isEnabled: Bool`; `CIKTrace.log(_ tag: String, _ message: @autoclosure () -> String)`; helpers `CIKTrace.points(_:)`, `CIKTrace.rect(_:)`.
- Produces: `KeyboardManager.readPhysicalViewInsetBottom() -> CGFloat?` (runtime call of the engine delegate method; trace only).

- [ ] **Step 1:** Add `CIKTrace.swift`: an `enum` whose `isEnabled` is `UserDefaults.standard.object(forKey: "CIKTrace") as? Bool ?? true` inside `#if DEBUG` and `false` otherwise; `log` prints `[CIKTrace] t=<CACurrentMediaTime format 4> <tag> <message>` with `NSLog`; helper formatters.

- [ ] **Step 2:** Hook the probe (change-only where noted):
  - swizzle handlers: `notification` name, begin/end frame, duration, curve, `isLocal`, tracking state, before/after.
  - `KeyboardManager.syncInset`: band bottom, computed inset, target, physical inset read-back — only when `inset != lastReportedInset`.
  - `CIKHostedAccessoryBar.layoutSubviews`: height changes only; bar bottom and guide top (`#available(iOS 15.0, *)`).
  - plugin: `createHostedAccessory` (height, hidden), `updateHostedAccessoryHidden`, `tearDownHostedAccessory`.
  - correction (Task 3): start/end/target/auto bottom, duration, curve, skipped reason.

- [ ] **Step 3: Verify it compiles** (Task 4 runs the full build; here `sh ios/KeyboardGeometryTests/run.sh` still passes because the new file is not in that target).
Expected: `all checks passed`.

### Task 3: Release correction + hidden-band fix

**Files:**
- Modify: `KeyboardManager.swift`
- Modify: `FlutterViewController+Swizzle.swift`
- Modify: `CupertinoInteractiveKeyboardPlugin.swift` (`updateHostedAccessoryHidden`, `tearDownHostedAccessory`)
- Modify: `CIKHostedAccessoryBar.swift` (`bottomBeforeTransform`)

**Interfaces:**
- Consumes: `KeyboardGeometry.releaseBandBottom(keyboardTop:viewBottom:)` (Task 1), `CIKTrace` (Task 2).
- Produces: `KeyboardManager.isTrackingKeyboard: Bool`; `KeyboardManager.keyboardNotificationHandled(_ notification: Notification, wasTracking: Bool)`; `CIKHostedAccessoryBar.bottomBeforeTransform: CGFloat` (`center.y + bounds.height/2`, unaffected by `transform`).

- [ ] **Step 1:** Add `isTrackingKeyboard` (display link non-nil), `bottomBeforeTransform`, `keyboardDragDidEnd()` (refresh `lastBandBottom` from `syncInset()` when still tracking) and call it from `CIKScrollView` on `.ended/.cancelled`.

- [ ] **Step 2:** Add `keyboardNotificationHandled(_:wasTracking:)`: skip notifications `isIgnoredByEngine` ignores (drag frames carry no frame); run when `wasTracking` **or** a correction is held; if a release arrives while the drag recognizer is still active, defer one runloop turn and re-check; otherwise call `applyBarCorrection`.

- [ ] **Step 3:** `applyBarCorrection`: capture the bar's visual bottom before `flutterView.layoutIfNeeded()`; skip when the bar layer has animations other than `cikReleaseCorrection`; compute the target band bottom with `KeyboardGeometry.releaseBandBottom(keyboardTop: nil for hide/empty/floating else endFrame.minY, viewBottom: viewRect.maxY)`, clamped to `>= 0` in the Flutter view's space; `wanted = target - bar.bottomBeforeTransform`; start from the last live band position on a release, from the held offset on a reconciliation; add a `CABasicAnimation(keyPath: "transform.translation.y")` with explicit `fromValue`/`toValue` and the notification's duration/curve; set the model transform to `wanted` with actions disabled; when there is nothing to travel, apply the offset without animation.

- [ ] **Step 4:** In the swizzle, capture `wasTracking` before `willProcessKeyboardNotification`, and call `keyboardNotificationHandled(wasTracking:)` with the original notification after the original handler, for all three handlers.

- [ ] **Step 5:** Hidden bar keeps the band: in `updateHostedAccessoryHidden`, stop clearing `KeyboardManager.shared.hostedAccessoryBar`; the inset driver must still see the bar's frame. Verify with `grep -c "hostedAccessoryBar" CupertinoInteractiveKeyboardPlugin.swift` that `tearDownHostedAccessory` is still the only place that clears it.

### Task 4: Build, checks, and the device run

**Files:** none.

- [ ] **Step 1:** `sh ios/KeyboardGeometryTests/run.sh` → `all checks passed`.
- [ ] **Step 2:** `flutter analyze` → no new findings beyond the pre-existing infos.
- [ ] **Step 3:** `flutter build ios --no-codesign --simulator` → build succeeds.
- [ ] **Step 4:** Device procedure for the owner (probe A): build the app in debug on the iPhone; open the chat and focus the composer; drag the keyboard down ~40% and release (cancel), repeat releasing at the bottom (dismiss), then reopen quickly and repeat twice; capture the `[CIKTrace]` lines (Console.app filtered on `CIKTrace`, or `flutter run` log). Send them back.
- [ ] **Step 5:** Read the trace against this table:
  - correction end ≈ 0 and no post-release inset write > 15 pt → B fixed it; no phase C needed for this bug.
  - correction held at non-zero (logged) → guide ended stale; phase C is required; record the value.
  - a single inset write after the release jumps by the keyboard height → band snap at release: stop reading the band on the pan's `.ended` (follow-up change in `CIKScrollView`), or the engine's duration-0 path is hit (log shows duration 0) → follow-up engine defense.
