# Design Doc: 1:1 Interactive Keyboard and Accessory Synchronization

## Intent & The Why
When interactively dismissing the iOS keyboard in Flutter (via dragging down on a scrollable view), the native iOS keyboard slides down in real-time. For an accessory toolbar (such as an input field or action bar wrapped in `CupertinoInputAccessory`) to feel completely native, it must move 1:1 with the keyboard—sticking directly to its top edge without latency, stutter, or detachment.

Currently, the accessory lags behind or freezes during dragging and release because:
1. Coordinates are sampled from model CALayers rather than live presentation CALayers.
2. Tracking ceases the instant the drag gesture enters `.ended`, aborting tracking before UIKit's release animation (inertia or snap-back) finishes.
3. Insets are computed against raw screen coordinates rather than the Flutter view's coordinate system, misaligning safe areas and view boundaries.
4. Overwriting internal engine state (`targetViewInsetBottom`) interferes with the engine's animation completion.

## Goals
- **1:1 Live Tracking**: While dragging, the Flutter accessory's bottom edge remains attached to the keyboard's top edge at every frame.
- **Smooth Release Transition**: When the user releases the drag, tracking seamlessly continues through UIKit's inertial dismissal or snap-back until the keyboard settles at rest.
- **Accurate Inset Geometry**: Inset calculations accurately use the Flutter view's local bounds and presentation coordinate space, correctly respecting safe area transitions.
- **Engine Compatibility**: Integrate cleanly with Flutter's `FlutterKeyboardInsetManager` and viewport metrics without breaking subsequent animations.
- **Test Verification**: Comprehensive test coverage without running the iOS Simulator app.

## Non-Goals & Anti-Goals
- **Non-Goals**: Replacing Flutter's widget-based `CupertinoInputAccessory` with a native platform view. The pure Flutter widget tree must remain intact.
- **Anti-Goals**:
  - Stopping tracking on finger lift and leaving the accessory frozen.
  - Hardcoding screen assumptions that fail in split-screen or multi-window layouts.
  - Using sleep loops or blocking main thread operations.

## Constraints
- Do not launch the iOS Simulator application during development or test runs.
- Must compile cleanly for iOS and maintain backward compatibility.

## Approaches Considered
- **Approach 1: Live Presentation Layer Tracking & Settlement Loop (Selected)**
  Keep the accessory rendered as a Flutter widget. Sample the live presentation geometry of the active accessory/keyboard container (`UIInputSetHostView` / presentation CALayers) converted to the Flutter view coordinate space. Drive updates via CADisplayLink through both drag and release animation until settled.
  *Trade-offs*: Preserves pure Flutter widget customization, requires precise frame geometry conversion and lifecycle handling.
- **Approach 2: Native View Embedding (inputAccessoryView Platform View)**
  Embed the accessory directly as a native UIKit view into `inputAccessoryView`.
  *Trade-offs*: Zero-lag UIKit rendering, but completely breaks Flutter widget composition, text input focus handling, and state management in Dart.

## Detailed Architecture & Implementation

### 1. Live Presentation Geometry Tracking
- Identify the active `CIKInputAccessoryView` and its ancestor layer in `UITextEffectsWindow`.
- Query `accessoryView.layer.presentation()` or its container presentation layer rather than static model properties.
- Convert presentation bounds to `flutterViewController.view` coordinate space:
  ```swift
  let presentation = accessoryView.layer.presentation() ?? accessoryView.layer
  // Map presentation frame to view coordinate space
  ```
- Calculate the visible keyboard inset:
  `visibleKeyboardHeight = max(0, view.bounds.height - presentationFrame.maxY)`
  `physicalInset = visibleKeyboardHeight * screenScale`

### 2. Gesture Lifecycle & Settlement Tracking
- Initiate CADisplayLink tracking as soon as the interactive pan gesture begins or the private interactive dismissal notification fires.
- When the pan gesture enters `.ended` or `.cancelled`, **do not immediately stop tracking**.
- Keep CADisplayLink active while the presentation layer is moving.
- Settle and stop tracking only when:
  1. The keyboard has reached resting position (either fully dismissed with inset = 0, or fully restored).
  2. A definitive system keyboard notification (`keyboardDidHide` / `keyboardDidShow`) completes the transition.
  3. A timeout safety ceiling is reached.

### 3. Flutter Engine Bookkeeping Protection
- Ensure `updateViewportMetricsWithInset:` updates the engine's physical bottom inset synchronously.
- Do not corrupt `FlutterKeyboardInsetManager.targetViewInsetBottom` with intermediate drag values, allowing the engine to properly handle the final settlement.

### 4. Verification Plan
- Dart unit and widget tests covering scroll physics, rect tracking, route awareness, and height observation.
- Headless compilation verification via `flutter build ios --no-codesign --simulator`.
