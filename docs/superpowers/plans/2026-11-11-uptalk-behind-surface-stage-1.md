# Behind-Surface Stage 1 Implementation Plan (plugin behind mode + uptalk probe)

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** the plugin can host a surface *behind* the Flutter view with touch passthrough, and uptalk proves it in a probe screen inside a rounded bottom panel (fake list, live sheet, push/pop, keyboard drag), with the full-screen chat route removed.

**Architecture:** behind mode = the forward surface with the container inserted below the FlutterView, the engine view full-screen, translation = keyboard inset, and a hit-test passthrough gated by an app-controlled flag; the app paints a transparent hole and keeps all overlays in the main engine.

**Tech Stack:** Flutter 3.47.7, Swift/UIKit plugin (SPM), `flutter_test` + mock channel, go_router in the app.

**Spec:** `docs/superpowers/specs/2026-11-11-uptalk-workspace-surface-design.md` (and the plugin spec it builds on).

## Global Constraints

- Forward bar and forward surface behaviour must not change.
- The hosted surface engine must keep a fixed layout while the keyboard moves: translation only, no resize, no metrics push, keyboard notifications suppressed for its VC.
- Touch passthrough only while `setHostedSurfaceInteractive(true)`; default false.
- The main FlutterView opacity is restored on teardown.
- Implementers do not commit; the Lead commits after review.
- iOS 15+; no new dependencies.

## Review Focus

- A tap on the list with no modal open must reach the surface (passthrough); a tap while a sheet is up must stay in the main engine.
- The sheet/flight/panel chrome stay above the live list (z-order).
- The hole shows the surface, never the window background, at rest, mid-drag and while a route covers it.
- The list must stay glued to the keyboard on a fast drag (device).
- Forward modes must still pass their tests.

---

### Task 1: Plugin behind mode (Lead)

**Files:**
- Modify: `ios/.../CIKHostedSurface.swift`, `CupertinoInteractiveKeyboardPlugin.swift`, `KeyboardManager.swift`, `FlutterViewController+Swizzle.swift` (hitTest swizzle in a new file `FlutterView+Swizzle.swift`)
- Modify: `lib/src/cupertino_interactive_keyboard_platform_interface.dart`, `lib/src/cupertino_interactive_keyboard_method_channel.dart`, `lib/src/cupertino_hosted_keyboard_surface.dart`, `lib/cupertino_accessory.dart`
- Test: `test/hosted_keyboard_surface_test.dart`, `test/mock_cupertino_interactive_keyboard.dart`

**Interfaces:**
- `createHostedAccessory({..., bool behind = false})` (channel arg `behind`).
- `CupertinoInteractiveKeyboardPlatform.setHostedSurfaceInteractive(bool interactive)` (channel method `setHostedSurfaceInteractive`); `CupertinoHostedInputAccessoryController.setInteractive(bool)`.
- `CupertinoHostedKeyboardSurface({..., bool behind = false})`: when `behind`, renders a transparent hole while hosting and `fallback` otherwise; forwards `setHostedSurfaceInteractive` when `interactive` changes (new widget field, default true, ignored unless behind).

- [ ] Steps: tests first (widget: behind create payload, fallback instead of hole when not hosting, interactive forwarded on change and on create; mock/channel contract), then platform interface + channel, then native (behind flag, below-view insertion, translation with resting 0, opacity set/restore, hitTest swizzle with the live hole, interactive flag), then Swift typecheck + geometry + `flutter test` + `flutter analyze` + iOS simulator build.

### Task 2: uptalk — remove the full-screen chat (teammate, independent)

**Files:** `lib/core/navigation/app_router.dart`, `lib/view/chat/presentation/direct_chat_menu_page.dart`, `lib/logic/services/notifications.dart`, related routing/workspace entry code.

- [ ] Find every entry point to `/chats/:chatId` (`app_router.dart:303`, `direct_chat_menu_page.dart:159`, `notifications.dart:22`, plus tests/snackbar links).
- [ ] Remove the route and the page's full-screen mount; route the entry points into the workspace with the chat open (the workspace's existing chat-selection/URL mechanism).
- [ ] `flutter analyze` clean; app tests pass; report the replacement mechanism used.

### Task 3: uptalk — behind-surface probe (teammate, after Task 1)

**Files:** `pubspec.yaml` (plugin to a local `path:`), a debug-only probe screen + route, its surface-isolate entrypoint, catalog/debug entry.

- [ ] Path dependency to the local plugin; `flutter pub get`.
- [ ] Probe: rounded bottom panel over a wallpaper; header row; transparent hole with `CupertinoHostedKeyboardSurface(behind: true, fallback: wallpaper)`; bottom band with a TextField; buttons "sheet" (showModalBottomSheet over the chat) and "push" (go_router push); a trace toggle.
- [ ] Surface isolate: fake 100-row list, palette background, bottom padding = band height (bridged); no content-height reporting.
- [ ] Interactive flag: true at rest, false while the sheet is open.
- [ ] `flutter analyze` clean; report exact commands; owner runs the device checks (list glued, sheet above the live list, tap/scrolling reaching the list, panel drag reveal, push/pop without a background flash).

### Task 4: Verification, review, commit (Lead)

- [ ] Plugin gates + app gates; read the diff; fresh reviewer; commit the plugin; commit the app (after review).
