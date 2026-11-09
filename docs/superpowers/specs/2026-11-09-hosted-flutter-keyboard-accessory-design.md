# Design Doc: Hosted Flutter Keyboard Accessory

## Intent & The Why

The bar must be a **live Flutter widget** and must ride the iOS keyboard frame for frame. A bar drawn
inside the app's own Flutter view cannot do the second part: Flutter composites after UIKit's keyboard
(measured repeatedly on device). The only way to have Flutter pixels move with the keyboard is to put
a **second Flutter engine's view inside a native container pinned to UIKit's keyboard layout guide**.
The bar is then rendered by Flutter and positioned by UIKit — no application-level tracking, no
snapshot, no native controls.

The owner rejected a native UIKit bar after trying it; this is the agreed fallback.

## Goals

- The bar is rendered by Flutter (Material widgets, the plugin's composer look) and configured from
  the main isolate: placeholder, initial text, colors, send icon.
- The bar's bottom edge is on the keyboard's top edge on open, drag and release, and on the view's
  bottom edge while the keyboard is closed (always visible).
- Typing, text mirroring, clearing and the send action work between the main isolate and the bar.
- The Flutter list still ends at the bar's top and still grows during an interactive dismissal.
- One small public API. The existing `CupertinoInputAccessory` path is untouched.

## Non-Goals (v1)

- Rendering the app's own widget tree in the bar: a second isolate cannot inflate widgets from the main
  isolate. The bar is the plugin's Flutter composer, configured by data; apps that need a custom bar
  can point the plugin at their own accessory entrypoint (exposed as optional parameters).
- Multiline self-growing bar (fixed height in v1).
- Android.

## Constraints

- No simulator/device runs by the implementers: static gates only; device pacing is verified by the owner.
- iOS 15+ for the positioned container (`keyboardLayoutGuide`); below that the widget keeps its
  placeholder and no bar is created. The plugin's floor stays iOS 13.
- No new package dependencies.

## Approach

1. **Host container.** `CIKHostedAccessoryBar` (UIView) is added to the FlutterViewController's view as
   the last subview, with `bottomAnchor == view.keyboardLayoutGuide.topAnchor` (and, on iOS 17+,
   `usesBottomSafeArea = false`). Its height is `height + safeAreaInsets.bottom`, reported to Dart.
2. **Second engine.** The plugin creates a `FlutterEngineGroup`, then an engine with
   `makeEngineWithEntrypoint(_:libraryURI:)` for the accessory entrypoint and a `FlutterViewController`
   on it, added as a child of the FlutterViewController. Its view fills the host container.
3. **Accessory Flutter app.** The plugin ships `cupertinoAccessoryMain` (annotated
   `@pragma('vm:entry-point')`), which runs a Material app: a composer bar (placeholder text field,
   send button) driven by a config map pushed from native and emitting text/send events.
4. **Channels.**
   - Main engine channel (existing): `createHostedAccessory` / `updateHostedAccessory` /
     `setHostedAccessoryText` / `removeHostedAccessory`; events `hostedAccessoryHeight`,
     `hostedAccessoryTextChanged`, `hostedAccessorySend`.
   - Accessory engine channel `cupertino_interactive_keyboard/accessory`: native → accessory
     `config` / `setText`; accessory → native `ready` / `textChanged` / `send`.
   The plugin forwards accessory events to the main channel and pushes config/setText down.
5. **Main isolate widget.** `CupertinoHostedInputAccessory` reserves the reported height in the Flutter
   layout (so the list ends at the bar's top), pushes config, mirrors text via a controller and
   surfaces `onChanged` / `onSend`.
6. **Content inset.** `KeyboardManager` uses the host container's live rect as its band (same existing
   driver), so the list grows during an interactive dismissal.

## Risks (device only)

- A second engine's view rendering inside the keyboard guide container; containment and first-frame size.
- Interactive dismissal: UIScrollView keyboard dismiss mode with the first responder in another engine.
- Safe-area flip changes the container height by the home-indicator inset when it leaves the bottom.
- Two isolates: `ready` handshake timing before config arrives.

## Verification

- Geometry checks for the container height, Dart widget tests for the host contract and the accessory
  app (config + events via a mocked channel), `flutter analyze`, `flutter build ios`.
- Owner's device run: bar glued to the keyboard, typing/send work, list reveals rows.
