# Hosted Keyboard Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A second-engine content surface (list + composer) that moves with the interactively dismissed iOS keyboard frame for frame, so the list has zero lag, plus an example route that proves it on device.

**Architecture:** The surface is the bar feature generalized. A native clipping container covers the content rectangle; the hosted engine view keeps a fixed frame and size and is moved by a `UIView` transform driven by the existing keyboard tracking (`KeyboardManager`), so the hosted engine never lays out or rasters while the keyboard moves. The main engine keeps the app bar and background; the surface isolate keeps the scroll content and composer; the two isolates talk over the existing accessory bridge.

**Tech Stack:** Flutter 3.47.7 (Dart), Swift 5 / UIKit + Flutter iOS embedder (SPM plugin in `ios/`), `package:test` + `flutter_test` widget tests with the existing mock channel, a pure-Swift geometry check harness.

**Spec:** `docs/superpowers/specs/2026-11-11-hosted-keyboard-surface-design.md` (read it; the research it cites is `docs/research/2026-11-11-keyboard-drag-list-second-engine.md`).

## Global Constraints

- iOS only; surface hosting requires iOS 15+ (same floor as the bar), with an app-supplied `fallback` widget otherwise. No Android/web work.
- One hosted thing per app. A create while another is hosted is last-wins and the displaced widget receives `hostedAccessoryReleased`; multi-host is out of scope.
- The hosted engine view has a **fixed frame and size** and is moved by a `UIView.transform` only; it must never be resized by the keyboard. The transform is `translationY = -max(0, inset - restingPadding)` (pure function in `KeyboardGeometry`).
- The hosted surface engine's view controller must never receive keyboard-inset notifications (the swizzle skips it), so `MediaQuery.viewInsets` inside the surface stays 0.
- The main engine is inset-immune while a surface is hosted: `resizeToAvoidBottomInset: false`, no `viewInsets` padding, static app bar; the plugin does not publish the drag inset to the main engine in surface mode.
- The reported rect is full width and reaches the view bottom; native uses only its top (A) and derives everything else from the Flutter view.
- No new dependencies. Do not commit from implementers; the Lead commits after review.
- Do not remove or change the existing bar behaviour: the bar route must keep working unchanged.

## Review Focus

- **A fast flick down (interactive dismissal).** The surface must stay within 1 pt of the keyboard-derived band every frame; the hosted engine must produce no frames. Wrong guess: the surface silently never tracks (e.g. the visibility predicate uses the bar's bottom-offset test) and only a device run reveals it.
- **Cancel mid-drag and release.** The surface must follow the keyboard back up and the bar/engine hand-off must not snap or jump.
- **Drag started during the keyboard's own show/hide animation.** The surface must be frozen at its presentation position before tracking starts (same rule the bar already follows).
- **Hiding a hosted surface (route pushed, panel collapsed).** The composer must lose focus and the keyboard must dismiss; no tracking or band may stay armed for a hidden surface.
- **Rect change while the keyboard is moving (rotation, app-bar change).** The rect update must be deferred until tracking settles; a mid-drag engine resize reintroduces the lag the feature exists to remove.
- **Hosting unavailable / engine start failure (iOS 13-14, memory pressure).** The widget must render its `fallback` rather than a blank area.

---

### Task 1: Surface geometry (pure Swift + checks)

**Files:**
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardGeometry.swift`
- Test: `ios/KeyboardGeometryTests/main.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `KeyboardGeometry.surfaceTranslation(inset: CGFloat, restingPadding: CGFloat) -> CGFloat` and `KeyboardGeometry.surfaceContentHeight(rectHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat`; used by Tasks 2 and 3.

- [ ] **Step 1: Add failing checks** to `ios/KeyboardGeometryTests/main.swift`, in the existing `expect` style:

```swift
expect(KeyboardGeometry.surfaceTranslation(inset: 0, restingPadding: 34), 0,
       "a resting surface is not translated")
expect(KeyboardGeometry.surfaceTranslation(inset: 34, restingPadding: 34), 0,
       "a surface at the home-indicator inset is not translated")
expect(KeyboardGeometry.surfaceTranslation(inset: 336, restingPadding: 34), -302,
       "a fully raised surface moves by the keyboard height minus the resting inset")
expect(KeyboardGeometry.surfaceTranslation(inset: 10, restingPadding: 34), 0,
       "a surface never translates above its resting position")
expect(KeyboardGeometry.surfaceContentHeight(rectHeight: 700, safeAreaBottom: 34), 666,
       "the hosted content height excludes the resting safe area")
expect(KeyboardGeometry.surfaceContentHeight(rectHeight: 10, safeAreaBottom: 34), 0,
       "the hosted content height never goes negative")
```

- [ ] **Step 2: Run the checks and verify they fail**

Run: `ios/KeyboardGeometryTests/run.sh`
Expected: compile error, `surfaceTranslation` / `surfaceContentHeight` not found.

- [ ] **Step 3: Implement the two functions** in `KeyboardGeometry.swift` with doc comments that state the contract (translation is `-max(0, inset - resting)`; content height is `max(0, rectHeight - safeAreaBottom)`).

- [ ] **Step 4: Run the checks and verify they pass**

Run: `ios/KeyboardGeometryTests/run.sh`
Expected: every existing check plus the six new ones prints `ok`, exit code 0.

---

### Task 2: Native hosted band + surface container + plugin wiring

**Files:**
- Create: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CIKHostedSurface.swift`
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CIKHostedAccessoryBar.swift` (conform to the new protocol)
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardManager.swift`
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CupertinoInteractiveKeyboardPlugin.swift`
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/FlutterViewController+Swizzle.swift`
- Test: `ios/KeyboardGeometryTests/run.sh` (unchanged, must stay green) + `flutter build ios --no-codesign --simulator` from `example/`.

**Interfaces:**
- Consumes: `KeyboardGeometry.surfaceTranslation`, `KeyboardGeometry.surfaceContentHeight` (Task 1).
- Produces:
  - `protocol CIKHostedBand: AnyObject` with `var restingPadding: CGFloat { get }`, `func apply(inset: CGFloat, padding: CGFloat, animated: Bool, duration: Double, curve: UInt)`, `func freezeAtVisiblePosition()`, `func presentedBottom(in view: UIView) -> CGFloat?`, `var isVisible: Bool { get }`.
  - `CIKHostedAccessoryBar: CIKHostedBand` (behaviour unchanged).
  - `CIKHostedSurface: CIKHostedBand` (new): fixed container [A,S] with `clipsToBounds = true`; engine view height `surfaceContentHeight(rectHeight: S - A, safeAreaBottom: resting)`, frame at the container top, transform from `surfaceTranslation`; `apply` sets/animates the transform; `update(rect:)` re-applies the container top and engine height only when tracking is idle.
  - `KeyboardManager.hostedBand: CIKHostedBand?` (replaces `hostedAccessoryBar` usage; keep `hostedAccessoryBar` as a typed alias only if the bar's height callbacks need it), `weak var hostedSurfaceViewController: FlutterViewController?`, `var isHostedSurface(_:) -> Bool`.
  - Plugin method `createHostedAccessory` accepts optional `rect` = `[String: Double]` x/y/width/height in points; new method `updateHostedAccessoryRect`; new main-engine call `hostedAccessoryReleased` (sent before tearing down a hosted thing that a new create displaces).
  - Bridge forwarding to the hosted isolate: `invoke('hidden', {'hidden': Bool})` on hide/show, `invoke('keyboardDragging', {'dragging': Bool})` on drag-state transitions, both through the existing `invokeHostedAccessory` path.
  - Swizzle: `FlutterViewController+Swizzle.handleKeyboardNotification` returns immediately when `KeyboardManager.shared.isHostedSurface(self)` (skip both the plugin manager and the engine handler).
  - Surface mode: do not publish the drag inset to the main engine; do not invalidate/sync the engine animation; `ownsInstantCollapse` still applies to the surface band.

- [ ] **Step 1: Refactor the manager to the band protocol with the bar only.** Introduce the protocol, conform `CIKHostedAccessoryBar`, and replace `hostedAccessoryBar` reads in `KeyboardManager` with `hostedBand`. Behaviour must be identical: `syncInset` computes inset/padding from the guide delta and calls `hostedBand.apply(...)` (non-animated during drag, animated with the notification duration/curve on release, instant-collapse ownership unchanged); `freezeBarAtVisiblePosition` becomes `hostedBand.freezeAtVisiblePosition()`; `startTrackingIfKeyboardVisible` keeps the bar predicate for a bar and uses `barInset > 0.5` for a surface; trace lines read `hostedBand`'s presented bottom.
  - Verify: `ios/KeyboardGeometryTests/run.sh` green; `flutter build ios --no-codesign --simulator` from `example/` succeeds; the bar route still behaves as before (owner device check later).

- [ ] **Step 2: Add `CIKHostedSurface.swift`.** Container constraints to the FlutterView (leading/trailing, top = A, bottom = view bottom), `clipsToBounds = true`; the hosted engine view pinned to the container top with height from Task 1, no auto-resizing; `apply` sets `transform = CGAffineTransform(translationX: 0, y: surfaceTranslation(...))` inside `UIView.animate` when `animated`, otherwise directly; `freezeAtVisiblePosition` removes animations and pins the presentation transform; `presentedBottom(in:)` returns the presentation layer's converted bottom; `update(rect:safeAreaBottom:)` updates the top constraint and engine height. Surface mode's `apply` must also set the engine view height once from the rect and never on a drag tick.

- [ ] **Step 3: Wire the plugin surface mode.** `NativeAccessoryConfig` gains optional `rect` (points). When present: create `CIKHostedSurface`, add it to the FlutterView, host the accessory VC's view in it, compute the content height from Task 1, set `hostedSurfaceViewController`, `hostedBand`, and apply the initial inset. Reuse the existing engine/create/bridge code paths. Add `updateHostedAccessoryRect` handling (`hostedBand as? CIKHostedSurface` → defer while tracking, else apply). Send `hostedAccessoryReleased` to the main engine before `tearDownHostedAccessory` when the teardown is caused by a new create. Forward `hidden` and `keyboardDragging` to the hosted isolate. In `tearDownHostedAccessory`, clear `hostedSurfaceViewController` and restore the main-engine inset behaviour.

- [ ] **Step 4: Swizzle suppression.** In `FlutterViewController+Swizzle.handleKeyboardNotification`, early-return for the hosted surface's view controller. Add `KeyboardManager.isHostedSurface(_:)` (identity check against the weak reference).

- [ ] **Step 5: Hide / focus.** `updateHostedAccessoryHidden(true)` on a surface: forward `invoke('hidden', {'hidden': true})`, `hostedSurfaceViewController?.view.endEditing(true)`, stop tracking, clear `hostedBand` (a hidden surface is not the live band); on show: restore `hostedBand`, forward `{'hidden': false}`, re-apply the current inset. The bar's hidden semantics stay exactly as they are (a hidden bar stays the live band).

- [ ] **Step 6: Trace.** Add the surface's model and presented transform/bottom to the `frame` trace line.

- [ ] **Step 7: Verify.** `ios/KeyboardGeometryTests/run.sh` green; `cd example && flutter build ios --no-codesign --simulator` succeeds. Report both outputs.

---

### Task 3: Dart bridge + surface widget + surface host (TDD)

**Files:**
- Modify: `lib/src/cupertino_interactive_keyboard_platform_interface.dart`
- Modify: `lib/src/cupertino_interactive_keyboard_method_channel.dart`
- Modify: `lib/src/cupertino_hosted_input_accessory.dart` (controller additions only)
- Create: `lib/src/cupertino_hosted_keyboard_surface.dart`
- Modify: `lib/cupertino_accessory.dart` (add `runCupertinoKeyboardSurface`, controller `onKeyboardDragging`, hidden/keyboardDragging interception)
- Modify: `lib/cupertino_interactive_keyboard.dart` (exports)
- Test: `test/hosted_keyboard_surface_test.dart`, `test/cupertino_accessory_test.dart` (add cases), plus `test/mock_cupertino_interactive_keyboard.dart` if the mock needs the new method.

**Interfaces:**
- Consumes: the channel contract above (Task 2).
- Produces:
  - `CupertinoInteractiveKeyboardPlatform.updateHostedAccessoryRect(Rect rect)`; `createHostedAccessory({required String entrypoint, required String libraryURI, required double height, bool hidden = false, Rect? rect})`; hosted event `{'type': 'released'}`.
  - `CupertinoAccessoryController.onKeyboardDragging: void Function(bool dragging)?`.
  - `CupertinoHostedKeyboardSurface({required String entrypoint, required String libraryURI, CupertinoHostedInputAccessoryController? controller, bool hidden = false, Widget? fallback})`.
  - `void runCupertinoKeyboardSurface(CupertinoAccessoryBuilder builder)`.

- [ ] **Step 1: Write failing widget tests.** In `test/hosted_keyboard_surface_test.dart`, with the existing mock:
  - the surface reports its rect and creates the hosted accessory once with `rect` = that rect and the given entrypoint/libraryURI;
  - a rect change after the first frame calls `updateHostedAccessoryRect` with the new rect and does not create again;
  - `hidden: true` on the widget calls `updateHostedAccessoryHidden(true)`, and a route becoming non-current also hides it (pump a `Navigator` push);
  - `released` emitted on `hostedAccessoryEvents` stops the widget owning the host (its dispose does not call `removeHostedAccessory`), and it re-creates when the route is current again;
  - creation returning null renders `fallback`;
  - non-iOS shows `fallback` and touches no channel.
  In `test/cupertino_accessory_test.dart`: the surface host unfocuses the primary focus when the bridge sends `invoke('hidden', {'hidden': true})`, and forwards `invoke('keyboardDragging', {'dragging': true})` to `CupertinoAccessoryController.onKeyboardDragging`.
- [ ] **Step 2: Run the tests and verify they fail** (`flutter test test/hosted_keyboard_surface_test.dart test/cupertino_accessory_test.dart`; missing types / methods).
- [ ] **Step 3: Implement the platform-interface and method-channel additions** with the exact method names and argument shapes above; add `released` to the event stream; keep the interface's default `UnimplementedError` style.
- [ ] **Step 4: Implement `CupertinoHostedKeyboardSurface`** (with the lifecycle rules above; reuse `RectObserver` and `CurrentRouteAware`; iOS only) and `runCupertinoKeyboardSurface` (full-size host, `FocusManager.instance.primaryFocus?.unfocus()` on `hidden`, forward `keyboardDragging` to the controller, never report `contentHeight`).
- [ ] **Step 5: Run the tests and verify they pass** (`flutter test`).
- [ ] **Step 6: Analyze** (`flutter analyze --no-fatal-infos`; 0 errors, no new infos beyond the 4 pre-existing).

---

### Task 4: Example route `/hosted_surface`

**Files:**
- Create: `example/lib/chat_surface.dart` (surface isolate app + entrypoint/library constants)
- Create: `example/lib/hosted_surface_screen.dart` (main isolate screen)
- Modify: `example/lib/catalog.dart` (list tile)
- Modify: `example/lib/main.dart` (route)

**Interfaces:**
- Consumes: `CupertinoHostedKeyboardSurface`, `CupertinoHostedInputAccessoryController`, `runCupertinoKeyboardSurface`, `CupertinoAccessoryController.onKeyboardDragging` (Task 3).
- Produces: the runnable device demo the owner will test.

- [ ] **Step 1: Surface app** (`chat_surface.dart`): `@pragma('vm:entry-point') void surfaceMain() => runCupertinoKeyboardSurface(...)`; a chat screen with a reverse `ListView`, the styled composer (TextField + send) at the bottom, the surface's own background via the main engine (no opaque page background), messages/theme received from the main isolate, draft/send sent back, and a `ScrollController` that pins the offset while `onKeyboardDragging` is true.
- [ ] **Step 2: Main screen** (`hosted_surface_screen.dart`): app bar with the trace toggle (reuse the bar screen's pattern), `resizeToAvoidBottomInset: false`, body `Stack`: `CupertinoHostedKeyboardSurface(entrypoint: surfaceEntrypoint, libraryURI: surfaceLibraryURI, controller: _controller)`, a bottom `ColoredBox` of height `MediaQuery.paddingOf(context).bottom` in the composer colour, and the message-bridge handlers (`onReady` → send messages + theme; `onInvoke` → send/draft).
- [ ] **Step 3: Register** in `catalog.dart` and `main.dart`.
- [ ] **Step 4: Verify** `flutter analyze` and `flutter test` from the repo root, and `cd example && flutter build ios --no-codesign --simulator`.
- [ ] **Step 5: Report** the exact commands run and their results; the owner runs the device check (design doc "Verification": surface vs keyboard within 1 pt every tick, no surface-engine frames during a drag).

---

### Task 5: Docs

**Files:**
- Modify: `README.md` (new "Frame-locked chat" section: the surface, its constraints - app bar outside, overlays inside or hidden, static rect, one hosted engine, iOS 15+ with fallback - and the example route)
- Modify: `CHANGELOG.md` (Unreleased entry)

- [ ] **Step 1:** Write both from the spec, without promising anything the implementation does not do.
- [ ] **Step 2:** Check the README's existing "notes" section does not contradict the new section; correct the stale "pinned to the keyboard layout guide" sentence if it is still there.

---

### Task 6: Verification, review, commit

- [ ] **Step 1:** Full gates from the repo root: `flutter test`, `flutter analyze --no-fatal-infos`, `ios/KeyboardGeometryTests/run.sh`, `cd example && flutter build ios --no-codesign --simulator`.
- [ ] **Step 2:** Read the whole diff; check the spec's Constraints and Review Focus line by line against it.
- [ ] **Step 3:** Fresh reviewer subagent on the diff (read-only) with the spec; fix accepted findings.
- [ ] **Step 4:** Commit (Lead only), with a message naming the feature and the device check that remains.
