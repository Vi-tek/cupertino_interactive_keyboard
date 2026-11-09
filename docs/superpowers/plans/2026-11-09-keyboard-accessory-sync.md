# Interactive Keyboard & Accessory 1:1 Sync — Insets Driven Live (Plan v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** The Flutter accessory bar stays glued to the top of the interactively dragged iOS keyboard at 1:1, and the app content grows behind it, by driving the engine's viewport inset from the live keyboard band on every frame of the drag.

**Architecture:** The native plugin reads the model-layer position of its own `inputAccessoryView` band (the view UIKit moves in lockstep with the keyboard), converts it into the required bottom view inset in physical pixels, and writes it into the engine with `updateViewportMetricsWithInset:` while the drag is being handled — before the vsync, so the frame that is about to be rendered already has it. The release is handed to the engine from the live inset so it animates with the keyboard's own curve. The Dart side is unchanged.

**Tech Stack:** Swift, Objective-C runtime, UIKit, Flutter (Dart).

**Spec:** `docs/superpowers/specs/2026-11-09-keyboard-accessory-sync-design.md`

## Global Constraints

- No iOS simulator may be run for development or verification (`flutter build ios --no-codesign --simulator` is build-only and allowed).
- The accessory keeps being rendered with Flutter widgets; no native accessory, no snapshot.
- No change to the public Dart API. `lib/` keeps its pre-6dc5869 shape.
- No synthetic keyboard notifications.
- Do not commit; the controller commits after review (single-writer git rule).

## Review Focus

1. Drag cancelled / snapped back: the bar follows the keyboard back up and the engine settles it without a jump.
2. Drag begun while the keyboard is still animating in: the plugin must not fight the engine's show animation.
3. Keyboard shown but no accessory on screen: standard interactive dismissal is unaffected.
4. Route change / app backgrounded mid-drag: the DisplayLink is invalidated, no leaked tracking.
5. Non-fullscreen Flutter view or rotation: the inset is computed against the Flutter view's own bottom, not the screen's.
6. Rapid repeated drags: no crash, no accumulated state.

---

### Task 1: Native — drive the viewport inset from the live band position

**Files:**
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardManager.swift`
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CIKScrollView.swift`
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CupertinoInteractiveKeyboardPlugin.swift`
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardGeometry.swift`
- Test: `ios/KeyboardGeometryTests/main.swift`

**Interfaces:**
- Consumes: `FlutterViewController` (`flutterViewController` set by the plugin), `CIKInputAccessoryView`, `activeScrollViews`, `activeInputAccessoryViews`.
- Produces:
  - `KeyboardGeometry.inset(bandBottom: CGFloat, viewBottom: CGFloat, scale: CGFloat) -> CGFloat` — physical pixels, never negative.
  - `KeyboardGeometry.shouldStopTracking(isDragging: Bool, hasStoppedMoving: Bool, staticTicks: Int) -> Bool` (unchanged).
  - `KeyboardManager.shared.keyboardDragDidChange()` — called on every pan `.began`/`.changed`.
  - `KeyboardManager.shared.willProcessKeyboardNotification(_ notification: Notification?)` — called by the swizzle before the engine sees a keyboard notification; performs the final live-inset write and stops driving.
  - `KeyboardManager.shared.startTrackingIfKeyboardVisible()` — unchanged entry point.

- [x] **Step 1: Add the failing geometry checks to `ios/KeyboardGeometryTests/main.swift`**

Add, in the existing style (`expect(...)`), with `screenHeight = 844`, `keyboardHeight = 336`, `scale = 3`, `viewBottom = 844`:

```swift
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
```

- [x] **Step 2: Run the geometry checks and confirm they fail**

Run: `sh ios/KeyboardGeometryTests/run.sh`
Expected: FAIL to compile — `KeyboardGeometry.inset` does not exist.

- [x] **Step 3: Implement `KeyboardGeometry.inset`**

In `KeyboardGeometry.swift` add exactly:

```swift
  /// The bottom view inset in physical pixels for a keyboard whose band currently ends at
  /// `bandBottom`.
  ///
  /// The band is the plugin's input accessory view. UIKit moves it in lockstep with the keyboard,
  /// so its bottom edge is the live top edge of the keyboard, and the viewport has to be inset by
  /// the distance between the Flutter view's bottom edge and that edge.
  static func inset(bandBottom: CGFloat, viewBottom: CGFloat, scale: CGFloat) -> CGFloat {
    max(0, viewBottom - bandBottom) * scale
  }
```

Replace the obsolete `bandOffset` / `accessoryTranslation` functions (nothing else uses them
after Task 1; `shouldStopTracking` stays).

- [x] **Step 4: Run the geometry checks and confirm they pass**

Run: `sh ios/KeyboardGeometryTests/run.sh`
Expected: all `ok: ...`, ending in `all checks passed`.

- [x] **Step 5: Rewrite the tracking half of `KeyboardManager.swift`**

Requirements, all in `KeyboardManager.swift`:

1. Delete everything added for the Dart-push approach: `channel`, `reportTranslation`,
   `currentViewportInset`, `lastReportedTranslation`, `isDrivingTranslation`.
2. Keep `adjustKeyboardNotification`, the `interactiveDismissalDidChange` observer,
   `startTrackingIfKeyboardVisible`, `isDraggingKeyboard`, `liveScreenRect(of:in:)`, and the
   `CADisplayLink` lifecycle. `willProcessKeyboardNotification` keeps forwarding (the swizzle
   forwards the returned notification unchanged).
3. Add `private var isInsetSyncScheduled = false` and:

```swift
  /// Called from the pan gesture while the keyboard is being dragged.
  ///
  /// UIKit applies the drag after the touch is delivered; the inset is written on the next main
  /// runloop turn so it sees the position UIKit just applied, and still lands before the next
  /// vsync — a write from the display link would miss the frame that is already starting.
  func keyboardDragDidChange() {
    guard interactiveTrackingDisplayLink != nil, !isInsetSyncScheduled else { return }
    isInsetSyncScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isInsetSyncScheduled = false
      // The gesture may have ended before this turn: the engine already took the inset over.
      guard self.interactiveTrackingDisplayLink != nil else { return }
      self.syncInset()
    }
  }
```

4. `private func syncInset()` reads the band's live rect through `liveScreenRect(of:in:)`,
   converts both edges into the screen coordinate space, computes
   `KeyboardGeometry.inset(bandBottom:viewBottom:scale:)`, returns the band bottom, and only calls
   `updateViewportMetrics(inset)` when the value changed since the previous write
   (`lastReportedInset`). Guard out when there is no Flutter view or no band on screen.
5. `private func updateViewportMetrics(_ inset: CGFloat)` — the same runtime call already in the
   file: `class_getInstanceMethod` for `updateViewportMetricsWithInset:` on
   `FlutterViewController`, `unsafeBitCast` to `@convention(c) (AnyObject, Selector, CGFloat) -> Void`,
   call it on `flutterViewController`.
6. `trackInteractiveKeyboard` (the display link callback) calls `syncInset()`, keeps the existing
   `hasStoppedMoving` / `staticTicks` settle detection, and stops via
   `KeyboardGeometry.shouldStopTracking`, with the 600-tick safety cap only when not dragging. It
   also stops after 5 consecutive ticks without a band on screen (the accessory left its window).
5b. `syncInset()` keeps the engine coherent with what it writes: after
   `updateViewportMetrics(inset)` it sets `keyboardInsetManager.targetViewInsetBottom` to the same
   value through the runtime (guarded by `responds(to: "setTargetViewInsetBottom:")`). The engine
   ignores a notification whose computed inset equals its target, which is exactly the frame a
   cancelled drag is released at; with the target on the live position the release always animates
   from where the keyboard is. The first write of a session also invalidates the engine's animation
   client (`invalidateKeyboardAnimationVSyncClient`), never the start of the session, so a session
   that writes nothing leaves a running show animation alone. `syncInset()` skips keyboards whose
   band is narrower than the Flutter view (floating) via
   `KeyboardGeometry.isDockedBand(bandWidth:viewWidth:)`, because the engine gives them no inset.
5c. `willProcessKeyboardNotification` stops tracking only for notifications the engine acts on: a
   `keyboardWillChangeFrame` with an exactly zero end frame (posted while the keyboard is dragged)
   and a notification with `UIResponder.keyboardIsLocalUserInfoKey == false` are ignored,
   mirroring the engine's own filter. `keyboardWillHideNotification` is never ignored.
7. `willProcessKeyboardNotification(_:)`: call `stopInteractiveTracking()` and forward the
   notification untouched. Do not read the band here: UIKit may already hold the resting position
   it is about to animate to, and writing it would snap the release instead of animating it.
8. `stopInteractiveTracking()` resets `lastReportedInset`, `lastBandBottom`, `staticTicks`,
   `trackingTicks`, `isInsetSyncScheduled = false`, invalidates the display link.
9. `startInteractiveTracking()` resets the same state and adds the display link.

- [x] **Step 6: Call `keyboardDragDidChange()` on every drag update in `CIKScrollView.swift`**

```swift
  @objc
  private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began, .changed:
      // Start tracking before the keyboard moves, then push the live position on every change.
      KeyboardManager.shared.startTrackingIfKeyboardVisible()
      KeyboardManager.shared.keyboardDragDidChange()
    default:
      break
    }
  }
```

Also call `KeyboardManager.shared.keyboardDragDidChange()` in
`gestureRecognizerShouldBegin` after the existing `startTrackingIfKeyboardVisible()`.

- [x] **Step 7: Drop the channel hand-over in `CupertinoInteractiveKeyboardPlugin.swift`**

Delete `KeyboardManager.shared.channel = channel` and its comment. Keep `detachFromEngine`
calling `KeyboardManager.shared.stopInteractiveTracking()`.

- [x] **Step 8: Verify the plugin compiles for iOS**

Run: `flutter build ios --no-codesign --simulator` (from the repository root; the example app lives
in `flutter_application_1/`, build from there if the root has no iOS project).
Expected: `✓ Built build/ios/iphonesimulator/Runner.app`.

- [x] **Step 9: Commit**

```bash
git add ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardManager.swift \
        ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardGeometry.swift \
        ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CIKScrollView.swift \
        ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CupertinoInteractiveKeyboardPlugin.swift \
        ios/KeyboardGeometryTests/main.swift
git commit -m "fix(ios): drive the viewport inset from the live keyboard position"
```

---

### Task 2: Dart — remove the Transform experiment

**Files:**
- Modify: `lib/src/cupertino_input_accessory.dart` → restore the pre-experiment version
- Modify: `lib/src/cupertino_interactive_keyboard_method_channel.dart` → restore
- Modify: `lib/src/cupertino_interactive_keyboard_platform_interface.dart` → restore
- Modify: `test/cupertino_interactive_keyboard_test.dart` → restore
- Delete: `test/tmp_probe_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: the public API and widget behaviour of `0949963` — no `keyboardTranslation`, no
  `Transform`; the accessory is laid out by the viewport inset alone.

- [x] **Step 1: Restore the four files from the commit before the experiment**

```bash
git checkout 0949963 -- lib/src/cupertino_input_accessory.dart \
  lib/src/cupertino_interactive_keyboard_method_channel.dart \
  lib/src/cupertino_interactive_keyboard_platform_interface.dart \
  test/cupertino_interactive_keyboard_test.dart
rm -f test/tmp_probe_test.dart
```

- [x] **Step 2: Confirm nothing references the removed notifier**

Run: `grep -rn "keyboardTranslation\|setKeyboardTranslation\|tmp_probe" lib test`
Expected: no output.

- [x] **Step 3: Run the Dart tests**

Run: `flutter test`
Expected: `All tests passed!`.

- [x] **Step 4: Run static analysis**

Run: `flutter analyze`
Expected: no errors. Four info-level findings are pre-existing after the byte-exact restore:
`current_route_aware.dart:11` (deprecated `TickerMode.of`), `cupertino_interactive_keyboard_method_channel.dart:13-14`
(`async` without `await`) and `flutter_application_1/lib/reversed_scroll_view.dart:37`. Do not "fix" them in
this task.

- [x] **Step 5: Commit**

```bash
git add lib test
git commit -m "revert: drop the Transform-based accessory experiment"
```

---

### Task 3: Whole-branch verification

- [x] **Step 1:** `sh ios/KeyboardGeometryTests/run.sh` → `all checks passed`
- [x] **Step 2:** `flutter test` → `All tests passed!`
- [x] **Step 3:** `flutter analyze` → no errors
- [x] **Step 4:** `flutter build ios --no-codesign --simulator` → build succeeds
- [x] **Step 5:** `git diff --stat 6dc5869..HEAD` limited to the intended files; no leftovers of the
      transform experiment in `lib/`.
- [x] **Step 6:** Dispatch the task reviewer over `6dc5869..HEAD`, then the final review.