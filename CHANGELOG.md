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
