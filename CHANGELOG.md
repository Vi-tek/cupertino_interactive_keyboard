## Unreleased

* `isKeyboardDragging`: a package-level `ValueListenable<bool>` that turns true while the interactive
  dismissal gesture drags the keyboard and false the moment the finger is released, before the
  keyboard animates back or away.

## 1.1.1 - A transparent bar you can hide

* The hosted bar's native container and the accessory engine's view are transparent: the bar shows
  only the pixels its Flutter app paints, so the app's own content (a chat background, a gradient)
  shows through instead of a system-background band. An app that wants an opaque bar paints it in
  the accessory.
* `CupertinoKeyboardAccessory(hidden:)` keeps the engine and its widget state alive while skipping
  drawing and hit-testing, so a bar that is only visible while a panel or screen is open can be
  toggled instead of created and destroyed. A hidden bar is also not treated as the live keyboard
  band by the inset driver. Created hidden through the new `hidden` field on
  `createHostedAccessory`, toggled through the new `updateHostedAccessoryHidden` platform method.

## 1.1.0 - Your Flutter bar, glued to the keyboard

* Hosted input accessory bar: your own Flutter composer (TextField, Material, anything) rendered by a
  second Flutter engine inside the real keyboard accessory container, so it moves with the keyboard
  frame for frame on open, interactive drag, release and at rest.
* Generic bridge between the app and the bar: `CupertinoHostedInputAccessory(entrypoint:, libraryURI:,
  controller:)` with `invoke` / `onInvoke` / `onReady` on both isolates; messages are queued until the
  bar is ready.
* The plugin ships no built-in composer and no UI configuration: the bar is entirely the app's Flutter
  code.
* The existing `CupertinoInteractiveKeyboard` / `CupertinoInputAccessory` path is unchanged.
* The example app now lives in `example/` (standard plugin layout) and demonstrates the hosted bar on a
  chat-like screen next to the classic accessory examples.

## 1.0.0 - Nothing is more permanent than a temporary solution

* Added Swift Package Manager support.
* Flutter-side improvements: new/updated helpers and behavior (persistent frame notifier, route
  awareness, interactive keyboard scroll physics) to improve scrolling and interaction with the
  keyboard.
* Partial fix for reversed scroll view behavior (see example and related Dart changes).
* Minor Example app updates.
* Added Flutter-side tests.
* CI/CD: added GitHub Actions workflows.

## 0.0.1

* Initial public release
