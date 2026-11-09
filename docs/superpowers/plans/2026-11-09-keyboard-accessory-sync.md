# Interactive Keyboard & Accessory 1:1 Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the Flutter keyboard accessory stays perfectly stuck (1:1 sync) to the iOS keyboard during interactive dismissal and snap-back/release animations.

**Architecture:** Sample live presentation CALayer coordinates from `CIKInputAccessoryView`'s hierarchy converted to `flutterViewController.view` coordinate space. Feed insets via `updateViewportMetricsWithInset:` and maintain CADisplayLink tracking through finger release until velocity settles.

**Tech Stack:** Swift, Objective-C Runtime, UIKit, Flutter (Dart).

**Spec:** `docs/superpowers/specs/2026-11-09-keyboard-accessory-sync-design.md`

## Global Constraints
- Do not run or launch the iOS Simulator app (compile-only via `flutter build ios --no-codesign --simulator`).
- Pure Flutter widget tree structure for `CupertinoInputAccessory` must be preserved.
- Target iOS platform integration without breaking non-accessory interactive dismissals.

## Review Focus
1. Release settlement: Lifting finger mid-drag must continue tracking smoothly until the keyboard is fully hidden or restored.
2. Inset precision: Screen scale and safe area bounds must not cause a 1-pixel gap or jump.
3. Rapid repeated drags: Dragging, releasing, and dragging again before animation finishes must not crash or leak DisplayLinks.
4. Non-fullscreen views: Inset must be calculated relative to `flutterViewController.view` instead of assuming full `UIScreen` bounds.
5. Inactive accessory: When no accessory is registered, standard interactive keyboard dismissal must continue functioning unaffected.

---

### Task 1: Refactor Live Geometry and Settlement Loop in KeyboardManager.swift

**Files:**
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardManager.swift`

**Interfaces:**
- Consumes: `activeInputAccessoryViews`, `flutterViewController`, `CIKInputAccessoryView`
- Produces: `reportLiveKeyboardInset()`, `startInteractiveTracking()`, `stopInteractiveTracking()`

- [ ] **Step 1: Implement live presentation layer frame calculation**
Update `reportLiveKeyboardInset()` to:
1. Extract `accessoryView.layer.presentation() ?? accessoryView.layer`.
2. Convert presentation layer frame into `view` coordinates:
   ```swift
   guard
     let flutterViewController,
     let view = flutterViewController.view,
     let accessoryView = activeInputAccessoryViews.first(where: { $0.window != nil }),
     let accessoryWindow = accessoryView.window
   else { return }
   let presentationLayer = accessoryView.layer.presentation() ?? accessoryView.layer
   let rectInWindow = presentationLayer.convert(presentationLayer.bounds, to: accessoryWindow.layer)
   let rectInView = view.convert(rectInWindow, from: accessoryWindow)
   let insetPoints = max(0, view.bounds.height - rectInView.maxY)
   let scale = view.window?.screen.scale ?? UIScreen.main.scale
   let inset = insetPoints * scale
   ```
3. Send to `updateViewportMetrics(inset, in: flutterViewController)`.
4. Remove mutation of `insetManager.setValue(..., forKey: "targetViewInsetBottom")` to avoid corrupting engine bookkeeping.

- [ ] **Step 2: Update CADisplayLink lifecycle for drag release and settlement**
Modify `trackInteractiveKeyboard()`:
1. When `gestureFinished` is true, do not immediately kill tracking.
2. Check if `inset` has settled (unchanged across consecutive ticks at 0 or resting height, or matching `lastReportedInset` for at least 3 consecutive frames with zero gesture activity).
3. Stop tracking only when settled or upon `willProcessKeyboardNotification` for terminal events.

- [ ] **Step 3: Verify Swift code compiles cleanly**
Run: `flutter build ios --no-codesign --simulator` in `flutter_application_1`
Expected: Build succeeds with 0 errors.

- [ ] **Step 4: Commit**
```bash
git add ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardManager.swift
git commit -m "fix(ios): sample presentation layer and maintain tracking through release"
```

---

### Task 2: Gesture and Notification Synchronization in CIKScrollView & Swizzles

**Files:**
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CIKScrollView.swift`
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/FlutterViewController+Swizzle.swift`

**Interfaces:**
- Consumes: `KeyboardManager.shared`
- Produces: Live tracking triggers on pan begin and clean teardown on terminal notifications.

- [ ] **Step 1: Ensure gesture tracking starts synchronously on pan**
In `CIKScrollView.swift`, verify pan gesture setup so interactive dismissal initiates tracking cleanly.

- [ ] **Step 2: Handle terminal notifications in FlutterViewController swizzles**
In `FlutterViewController+Swizzle.swift`, forward notifications to `KeyboardManager` so that when a standard animation completes, interactive tracking yields back to the engine cleanly.

- [ ] **Step 3: Verify compile step**
Run: `flutter build ios --no-codesign --simulator` in `flutter_application_1`
Expected: Build succeeds.

- [ ] **Step 4: Commit**
```bash
git add ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CIKScrollView.swift ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/FlutterViewController+Swizzle.swift
git commit -m "fix(ios): synchronize interactive dismissal gestures and notifications"
```

---

### Task 3: Comprehensive Dart Unit & Widget Tests

**Files:**
- Modify: `test/cupertino_interactive_keyboard_test.dart`

**Interfaces:**
- Consumes: `CupertinoInteractiveKeyboard`, `CupertinoInputAccessory`, `MockCupertinoInteractiveKeyboard`
- Produces: Test coverage for accessory height changes, interactive scroll physics, and route changes.

- [ ] **Step 1: Add unit tests for CupertinoInputAccessory height dynamics**
Add a test verifying:
1. Changing child height dynamically updates `inputAccessoryHeights` on platform interface.
2. Multiple accessories register and compute maximum height correctly.
3. Unmounting accessories removes height registration.

- [ ] **Step 2: Run flutter test**
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 3: Commit**
```bash
git add test/cupertino_interactive_keyboard_test.dart
git commit -m "test: add tests for accessory dynamics and platform interface synchronization"
```
