# Hosted Bar Ownership, Dynamic Height and Quiet Probe — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The plugin owns the hosted bar's position and height (no `keyboardLayoutGuide` dependency), the accessory content sizes the bar and is never stretched, and the DEBUG probe is off by default.

**Architecture:** `CIKHostedAccessoryBar` gets a manual bottom constraint and a content-height-only hosted view. `KeyboardManager` keeps one value, `barInset`; keyboard notifications animate the bar to their end position, an interactive drag moves it from the guide's delta since the drag started, and the engine inset is computed from the same value. The accessory host measures its content's natural height and reports it, so a multiline composer grows the bar.

**Tech Stack:** Swift (UIKit, Auto Layout, QuartzCore, private Flutter engine APIs as already used), Dart (plugin widget + accessory host), no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md`

## Global Constraints

- Public API: `CupertinoKeyboardAccessory.height` becomes optional; everything else keeps its shape.
- Classic `CupertinoInputAccessory` and non-hosted apps keep the old inset band path untouched.
- No new private engine APIs; no Dart API removal.
- Probe: off by default, `-CIKTrace YES` enables it, release always off.
- No commits; the owner commits after review.

## Review Focus

1. A drag that starts at rest (keyboard closed) and a drag that starts mid-flight must both track.
2. A release that is cancelled (keyboard springs back) and one that completes (keyboard leaves) must land exactly on the keyboard, with no residual offset.
3. The safe-area padding must appear/disappear with the keyboard animation, never as a 34 pt jump or stretch.
4. A multiline composer must grow the bar, and the bar must not clip or stretch it on the way.
5. The hidden bar must still drive the inset, and a bar created while the keyboard is open must start at the right position.

---

### Task 1: Drag math + checks

**Files:**
- Modify: `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardGeometry.swift`
- Test: `ios/KeyboardGeometryTests/main.swift`

**Interfaces:**
- Produces: `KeyboardGeometry.dragBarInset(insetAtStart: CGFloat, guideTopAtStart: CGFloat, guideTop: CGFloat, maxInset: CGFloat) -> CGFloat` — the current bar inset from the guide's delta, clamped to `0...maxInset`.

- [ ] **Step 1: Add failing checks** (view height 844):

```swift
expect(
  KeyboardGeometry.dragBarInset(insetAtStart: 300, guideTopAtStart: 508, guideTop: 508, maxInset: 844),
  300, "a still guide keeps the inset the drag started with"
)
expect(
  KeyboardGeometry.dragBarInset(insetAtStart: 300, guideTopAtStart: 508, guideTop: 548, maxInset: 844),
  260, "dragging the keyboard down by 40 shrinks the inset by 40"
)
expect(
  KeyboardGeometry.dragBarInset(insetAtStart: 300, guideTopAtStart: 508, guideTop: 900, maxInset: 844),
  0, "an inset never goes negative"
)
expect(
  KeyboardGeometry.dragBarInset(insetAtStart: 300, guideTopAtStart: 508, guideTop: 300, maxInset: 844),
  508, "an inset never grows past the view top"
)
```

- [ ] **Step 2:** `sh ios/KeyboardGeometryTests/run.sh` → FAIL (no `dragBarInset`).
- [ ] **Step 3:** Implement in `KeyboardGeometry.swift`:

```swift
static func dragBarInset(
  insetAtStart: CGFloat,
  guideTopAtStart: CGFloat,
  guideTop: CGFloat,
  maxInset: CGFloat
) -> CGFloat {
  let dragged = insetAtStart + (guideTopAtStart - guideTop)
  return max(0, min(maxInset, dragged))
}
```

- [ ] **Step 4:** `sh ios/KeyboardGeometryTests/run.sh` → `all checks passed`.

### Task 2: Probe is opt-in

**Files:** `ios/.../CIKTrace.swift`

- [ ] **Step 1:** Default `isEnabled` to `false` unless `-CIKTrace YES` was passed; keep release off; update the doc comment. Verify with `grep -n "isDebugBuild" CIKTrace.swift` that no default-on path remains.

### Task 3: Bar owns its bottom and never stretches its content

**Files:** `ios/.../CIKHostedAccessoryBar.swift`

**Interfaces:**
- Produces: `var bottomInset: CGFloat` (get/set; setter updates the bottom constraint to `-inset`), `func setIncludesSafeArea(_:)`, `func setBottomInset(_:)`, `func apply(height:)` unchanged, `var contentHeight: CGFloat`.

- [ ] **Step 1:** Replace the height-only view with: a bottom constraint to `superview.bottomAnchor` (constant 0), a height constraint `contentHeight + (includesSafeArea ? superview.safeAreaInsets.bottom : 0)`, and the hosted view pinned top/leading/trailing with height `contentHeight` (updated in `updateHeightIfNeeded`). `safeAreaInsetsDidChange` recomputes.

### Task 4: Manager drives the bar; correction machinery is deleted

**Files:** `ios/.../KeyboardManager.swift`, `ios/.../CIKScrollView.swift`

**Interfaces:**
- Consumes: `KeyboardGeometry.dragBarInset`, `releaseBandBottom`, `CIKHostedAccessoryBar.bottomInset`.
- Produces: `var barInset: CGFloat` (points), `func currentlyTrackingGuideDelta() -> ...` internal only; `keyboardNotificationHandled(_:wasTracking:)` animates the bar to the notification target and no longer touches transforms.

- [ ] **Step 1:** Delete `applyBarCorrection`, `setBarCorrection`, `releaseCorrectionKey`, the transform animation, and the `keyboardDragDidEnd` call from `CIKScrollView`.
- [ ] **Step 2:** `syncInset()`: for the hosted bar, compute `barInset` from the guide delta (drag start values recorded in `startInteractiveTracking`), set `bar.bottomInset`, and publish the engine inset from `barInset * scale` with the existing target sync; keep the old band path for the classic accessory. Return the bar's bottom in screen points for the settle detection.
- [ ] **Step 3:** `keyboardNotificationHandled`: for notifications the engine acts on, compute the target with `releaseBandBottom`, then animate `bar.bottomInset` to it and set `includesSafeArea = target < 0.5` inside `UIView.animate` with the notification duration/curve and a `layoutIfNeeded` on the bar's superview; do not write the engine inset there.
- [ ] **Step 4:** `startInteractiveTracking` records `barInset` and the guide top; `guideTopInView()` reads `keyboardLayoutGuide.layoutFrame.minY` (iOS 15+).

### Task 5: Plugin wiring

**Files:** `ios/.../CupertinoInteractiveKeyboardPlugin.swift`

- [ ] **Step 1:** Replace the guide pin with `bar.setBottomInset(initialInset)` where `initialInset` is read from the guide (0 when unavailable), and set `includesSafeArea` from it; drop `usesBottomSafeArea`.
- [ ] **Step 2:** Handle `contentHeight` on the accessory channel: `hostedAccessoryBar?.apply(height:)` on the main queue.

### Task 6: Dynamic height in Dart

**Files:** `lib/cupertino_accessory.dart`, `lib/src/cupertino_hosted_input_accessory.dart`, `example/lib/keyboard_accessory.dart`

- [ ] **Step 1:** In `CupertinoAccessoryHost`, wrap the builder in a measuring host that lays it out with unbounded height (never-scrollable viewport), measures the content's natural height after each frame and invokes `contentHeight` (change-only, >0.5 pt) on `accessoryChannel`.
- [ ] **Step 2:** `CupertinoKeyboardAccessory.height` becomes `double?`; `build` reserves `_reportedHeight ?? (height ?? 56) + padding.bottom`; `didUpdateWidget` compares null-safely.
- [ ] **Step 3:** Example passes no `height`; README notes the dynamic height and the intrinsic-content contract.

### Task 7: Tests and verification

**Files:** `test/cupertino_accessory_test.dart`

- [ ] **Step 1:** Widget test: pump `CupertinoAccessoryHost` with a 120 pt builder against the mocked accessory channel; expect an `contentHeight` invocation with 120 (±0.5). Run `flutter test` → FAIL first (no report).
- [ ] **Step 2:** Implement Task 6 until the test passes; whole-suite `flutter test` green.
- [ ] **Step 3:** `sh ios/KeyboardGeometryTests/run.sh`, `flutter analyze`, `flutter build ios --no-codesign --simulator`.
- [ ] **Step 4:** Device checklist (owner): multiline growth; drag slow/fast, release at 40% and at the bottom; open/close; hidden bar in dock modes. Expected: no stretch, no detach, no jump, list 1:1 with the finger.
