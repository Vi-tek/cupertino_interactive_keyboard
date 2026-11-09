# Hosted Flutter Keyboard Accessory — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox syntax.

**Goal:** The accessory bar is a live Flutter widget rendered by a second Flutter engine inside a native container pinned to UIKit's keyboard layout guide, so it rides the keyboard frame for frame while staying Flutter.

**Architecture:** `CIKHostedAccessoryBar` hosts a second engine's `FlutterViewController` view, pinned to `keyboardLayoutGuide.topAnchor`; the plugin bridges config/events between the main engine and the accessory engine; `CupertinoHostedInputAccessory` reserves the bar height in the main layout and the existing inset driver uses the host container's rect.

**Spec:** `docs/superpowers/specs/2026-11-09-hosted-flutter-keyboard-accessory-design.md`

## Global Constraints

- Static verification only; no simulator/device run.
- Scope split: **native** owns `ios/`; **Dart** owns `lib/`, `test/`, `flutter_application_1/`. Never cross. No commits.
- The rejected native implementation is already in the working tree (same files): modify it in place, do not start over.
- iOS 15+ for the positioned container; below that `createHostedAccessory` returns nil.

## Channel contract

Main channel `cupertino_interactive_keyboard`:
- `createHostedAccessory` args `{"placeholder": String, "text": String, "icon": String, "backgroundColor": int?, "textColor": int?, "placeholderColor": int?, "iconColor": int?, "height": double, "accessoryEntrypoint": String?, "accessoryLibraryURI": String?}` → `{"height": double}` (height + bottom safe area, points).
- `updateHostedAccessory` args: the same map minus `text` and the entrypoint fields → nil.
- `setHostedAccessoryText` args `{"text": String}` → nil.
- `removeHostedAccessory` → nil.
- Events native → Dart: `hostedAccessoryHeight` `{"height": double}`, `hostedAccessoryTextChanged` `{"text": String}`, `hostedAccessorySend` `{"text": String}`.

Accessory channel `cupertino_interactive_keyboard/accessory` (on the accessory engine's binary messenger):
- native → accessory: `config` (the full config map incl. `height`), `setText` `{"text": String}`.
- accessory → native: `ready` (no args), `textChanged` `{"text": String}`, `send` `{"text": String}`.
Native pushes `config` when the accessory calls `ready` and whenever `updateHostedAccessory` arrives.

---

### Task 1: Native container, second engine, bridging

**Files (modify the existing rejected implementation):**
- `ios/.../CIKNativeInputAccessoryBar.swift` → rename file/class to `CIKHostedAccessoryBar.swift` / `CIKHostedAccessoryBar`; keep `NativeAccessoryConfig` (extend with `height`, `accessoryEntrypoint`, `accessoryLibraryURI`), ARGB parsing.
- `ios/.../CupertinoInteractiveKeyboardPlugin.swift` — rename the four channel cases to the hosted names, create engine group/engine/VC, bridge channels.
- `ios/.../KeyboardManager.swift` — rename `nativeAccessoryBar` to `hostedAccessoryBar` (same tracking role).
- `ios/.../KeyboardGeometry.swift` + `ios/KeyboardGeometryTests/main.swift` — replace `nativeAccessoryHeight` with `hostedAccessoryHeight(contentHeight:safeAreaBottom:) = contentHeight + safeAreaBottom` and update/keep four checks (min height, safe-area 0, …; the min/max clamping is gone because the height is fixed).

**Steps:**
- [ ] Geometry checks first (failing), then the helper; `sh ios/KeyboardGeometryTests/run.sh` passes.
- [ ] `CIKHostedAccessoryBar`: `UIView` with a height constraint = `hostedAccessoryHeight(contentHeight: config.height, safeAreaBottom: safeAreaInsets.bottom)`; lays out a passed-in child view (the accessory VC's view) to its bounds; reports `onHeightChange` on layout/safe-area change; no UITextView/button/placeholder code remains.
- [ ] Plugin: lazily create `FlutterEngineGroup(name:project:)` with `FlutterDartProject()`; on `createHostedAccessory` (guard `#available(iOS 15.0, *)`) create the bar, then `makeEngineWithEntrypoint(entrypoint ?? "cupertinoAccessoryMain", libraryURI ?? "package:cupertino_interactive_keyboard/cupertino_accessory_entrypoint.dart")`, `FlutterViewController(engine:)` as a child of the main FlutterViewController, add its view into the bar, store engine+VC+bar, expose the bar as `KeyboardManager.shared.hostedAccessoryBar`; set the accessory channel handler (on the accessory engine's `binaryMessenger`) for `ready`/`textChanged`/`send`; on `ready` push the current config; forward events to the main channel. `updateHostedAccessory` updates config + pushes to the accessory; `setHostedAccessoryText` pushes `setText`; `removeHostedAccessory` tears down the VC/engine/bar.
- [ ] Verify: geometry checks pass; `cd flutter_application_1 && flutter build ios --no-codesign --simulator` builds.

### Task 2: Dart — hosted widget, accessory entrypoint, example, tests

**Files:**
- `lib/src/cupertino_native_input_accessory.dart` → rename to `cupertino_hosted_input_accessory.dart`; `CupertinoNativeInputAccessory` → `CupertinoHostedInputAccessory`; controller stays `CupertinoNativeInputAccessoryController` → `CupertinoHostedInputAccessoryController`. API: placeholder, initialText, controller, onChanged, onSend, icon, colors, `height` (default 56), optional `accessoryEntrypoint`/`accessoryLibraryURI`. Height comes from the `hostedAccessoryHeight` event, placeholder before it = `height + MediaQuery.padding.bottom`.
- `lib/cupertino_accessory_entrypoint.dart` (new): `@pragma('vm:entry-point') void cupertinoAccessoryMain()` running `CupertinoAccessoryApp` — a Material app whose composer bar follows the `config` map (placeholder, initial text, icon, colors) and emits `ready`/`textChanged`/`send` on `MethodChannel('cupertino_interactive_keyboard/accessory')`; `setText` updates the controller without echoing `textChanged`.
- `lib/cupertino_interactive_keyboard.dart`: export both new libraries.
- Platform interface + method channel: rename to the hosted method/event names in the contract; accessory channel is NOT used from the main isolate.
- `flutter_application_1/lib/input_accessory.dart`: use `CupertinoHostedInputAccessory` with the same config as now.
- `test/native_input_accessory_test.dart` → `test/hosted_input_accessory_test.dart` (rename + update names); `test/cupertino_accessory_entrypoint_test.dart` (new): pump `CupertinoAccessoryApp` with a mocked accessory channel, assert config renders (placeholder/colors), typing emits `textChanged`, the send button emits `send`, `setText` updates the field without emitting.
- Update `test/mock_cupertino_interactive_keyboard.dart` to the hosted names/events.

**Steps:**
- [ ] Tests renamed/extended first (failing), then the implementation; `flutter test` all pass; `flutter analyze --no-fatal-infos` no errors.
