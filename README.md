This project is based off the [cupertino_interactive_keyboard](https://github.com/ky1vstar/cupertino_interactive_keyboard) repo.

# Cupertino Interactive Keyboard

A Flutter plugin for the iOS [interactively dismissible keyboard](https://developer.apple.com/documentation/uikit/uiscrollview/keyboarddismissmode/interactive),
with an input accessory bar that is **your own Flutter UI** and still moves with the keyboard
frame for frame.

## Why this plugin exists

The keyboard can be dragged down with the list to dismiss it interactively. The hard part is the
bar above the keyboard: a Flutter widget drawn inside the app's Flutter view is composited one
frame after UIKit's keyboard, so it trails the keyboard while it moves, and a native UIKit bar is
no longer a Flutter widget.

This plugin solves both by hosting a **second Flutter engine** inside the real keyboard container:
the plugin positions the container itself, from the live keyboard position on every frame, while
Flutter draws the bar inside it. You get a normal Flutter widget tree — `TextField`, `Material`,
anything — glued to the top edge of the keyboard on open, drag, release and at rest.

## Install

```yaml
dependencies:
  cupertino_interactive_keyboard: ^1.1.0
```

iOS only. The hosted bar needs iOS 15+; older versions keep the plugin's inset behaviour and do
not create the bar.

## The hosted bar (recommended)

### 1. Write your composer in its own library

`lib/accessory_composer.dart`:

```dart
import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';

/// Entrypoint of the accessory engine: the plugin runs this in a second
/// isolate and puts its view inside the keyboard accessory container.
@pragma('vm:entry-point')
void accessoryMain() {
  runCupertinoAccessory(
    (context, controller) => Composer(controller: controller),
  );
}

class Composer extends StatefulWidget {
  const Composer({super.key, required this.controller});

  final CupertinoAccessoryController controller;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _field = TextEditingController();
  Color _background = Colors.white;
  Color _foreground = Colors.black;

  @override
  void initState() {
    super.initState();
    // Messages come from the app's main isolate.
    widget.controller.onInvoke = (method, arguments) {
      final args = (arguments as Map?) ?? const {};
      switch (method) {
        case 'theme':
          setState(() {
            _background = Color(args['background'] as int);
            _foreground = Color(args['foreground'] as int);
          });
          break;
        case 'setText':
          _field.text = args['text'] as String? ?? '';
          break;
      }
    };
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _background,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _field,
                maxLines: null,
                style: TextStyle(color: _foreground),
                decoration: const InputDecoration(hintText: 'Input comment...'),
                onChanged: (text) =>
                    widget.controller.invoke('textChanged', {'text': text}),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              color: _foreground,
              onPressed: () =>
                  widget.controller.invoke('send', {'text': _field.text}),
            ),
          ],
        ),
      ),
    );
  }
}
```

> The accessory engine can only start an entrypoint that is in the app's compiled kernel, so the
> app has to import the composer library. A library nothing imports is not compiled in and the
> engine fails with `Dart_LookupLibrary: library 'package:my_app/accessory_composer.dart' not found`,
> so import it from the screen that hosts the bar (or anywhere `main.dart` reaches).

### 2. Put the bar on the screen

```dart
import 'accessory_composer.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final CupertinoHostedInputAccessoryController _bar;

  @override
  void initState() {
    super.initState();
    _bar = CupertinoHostedInputAccessoryController()
      ..onReady = _sendTheme
      ..onInvoke = _handleBarMessage;
  }

  void _sendTheme() {
    final scheme = Theme.of(context).colorScheme;
    _bar.invoke('theme', {
      'background': scheme.surface.toARGB32(),
      'foreground': scheme.onSurface.toARGB32(),
    });
  }

  void _handleBarMessage(String method, Object? arguments) {
    final args = (arguments as Map?) ?? const {};
    switch (method) {
      case 'textChanged':
        debugPrint('typing: ${args['text']}');
        break;
      case 'send':
        debugPrint('send: ${args['text']}');
        _bar.invoke('setText', {'text': ''});
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: CupertinoInteractiveKeyboard(
              child: ListView.builder(
                itemCount: 100,
                itemBuilder: (_, index) => ListTile(title: Text('Item #$index')),
              ),
            ),
          ),
          CupertinoHostedInputAccessory(
            entrypoint: 'accessoryMain',
            libraryURI: 'package:my_app/accessory_composer.dart',
            controller: _bar,
          ),
        ],
      ),
    );
  }
}
```

That is the whole integration: `entrypoint` and `libraryURI` point the plugin at your composer,
and one controller carries everything else.

## The message bridge

The two isolates talk through a generic two-way bridge; the plugin does not know or care what you
send.

| Direction | Main isolate | Accessory isolate |
|---|---|---|
| main → bar | `controller.invoke(method, [arguments])` | `controller.onInvoke = (method, arguments) { ... }` |
| bar → main | `controller.onInvoke = (method, arguments) { ... }` | `controller.invoke(method, [arguments])` |
| bar is ready | `controller.onReady = () { ... }` | sent automatically |

Messages sent from the main isolate before the bar is ready are queued by the native side and
delivered once it is, so `onReady` is only needed for data that depends on layout or theme.

## The classic Flutter accessory

For simple composables you can keep everything in the app's own Flutter view — no second engine,
no entrypoint. The bar can trail the keyboard by a frame during interactive dismissal, which is
usually invisible for a passive bar.

```dart
Column(
  children: [
    Expanded(
      child: CupertinoInteractiveKeyboard(
        child: ListView.builder(...),
      ),
    ),
    CupertinoInputAccessory(
      child: Material(...your bar...),
    ),
  ],
)
```

## The hosted keyboard surface (frame-locked chat)

A hosted **surface** is the same trick applied to the whole chat area: the list and the composer
live in the second engine, inside a native container that tracks the keyboard. The engine view
keeps a fixed frame and size and is moved by a transform, so during a drag the hosted engine does
no layout, no rebuild and no raster at all — its cached pixels move with the keyboard on the
keyboard's own clock. The list cannot lag the composer, and the composer cannot lag the keyboard,
because all three are one surface moved by one number.

The app bar, the page background and route chrome stay in the main engine; the scrolling content
and its composer live in the surface isolate.

```dart
// main isolate: the surface takes the content area, the app bar stays here
Scaffold(
  resizeToAvoidBottomInset: false,
  appBar: AppBar(title: const Text('Chat')),
  body: Stack(
    children: [
      CupertinoHostedKeyboardSurface(
        entrypoint: 'surfaceMain',
        libraryURI: 'package:my_app/chat_surface.dart',
        controller: _controller,
        fallback: const InAppChat(), // shown on iOS < 15 or if hosting fails
      ),
      // the home-indicator strip under the engine view, painted by the main engine
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: MediaQuery.paddingOf(context).bottom,
          child: ColoredBox(color: composerColor),
        ),
      ),
    ],
  ),
)
```

```dart
// surface isolate: the list + composer, filling the fixed-size surface
@pragma('vm:entry-point')
void surfaceMain() => runCupertinoKeyboardSurface(
  (context, controller) => MyChatSurface(controller: controller),
);
```

What to know before using it:

- The surface rectangle must be the whole content area under the app bar: full width and down to
  the Flutter view's bottom. The page around it must not resize for the keyboard
  (`resizeToAvoidBottomInset: false`, no inset-driven padding) and the app bar must be static — the
  surface cannot react to a collapsing bar.
- The surface isolate has a fixed layout: do not size anything from `MediaQuery.viewInsets` and do
  not resize for the keyboard. While the keyboard is dragged the native container already moves the
  content, so pin the list's scroll offset on `CupertinoAccessoryController.onKeyboardDragging`
  instead of letting it scroll a second time.
- The surface is a native view above the Flutter content: routes and overlays in the main engine
  are covered while it is shown. It hides itself when its route is not current; overlays over the
  chat (menus, sheets) must be hosted inside the surface isolate. v1 does not animate route
  transitions around it.
- One hosted thing per app: a newer surface (or bar) displaces the previous one; the displaced
  widget is told through the `hostedAccessoryReleased` event and a surface re-hosts itself when its
  route is current again. The bar does not re-host on its own.
- iOS 15+ only; pass a real `fallback` for older systems. The plugin added the surface so that a
  screen that needs zero lag does not have to switch to `resizeToAvoidBottomInset: true` (which
  cannot remove the frame anyway).

## The behind surface (an app screen that keeps its overlays)

A behind surface is the same hosted content area, inserted **below** the Flutter view instead of
above it. The app paints a transparent hole where the surface shows, so everything the main engine
draws above it — bottom sheets, dialogs, overlay animations, the screen's own chrome — still renders
over the live, natively-moved content. Use it when a screen cannot give its overlays up.

```dart
// the hole: transparent while the surface is live, the app's background otherwise
CupertinoHostedKeyboardSurface(
  entrypoint: 'surfaceMain',
  libraryURI: 'package:my_app/chat_surface.dart',
  behind: true,
  interactive: !modalOpen, // touches fall through to the surface only while true
  fallback: const MyBackground(), // fills the hole when hidden/covered
)
```

Requirements and limits:

- The app's root `FlutterViewController` must be non-opaque before the first frame (`isViewOpaque =
  false` in the iOS host): the engine builds its surface from that flag, so a late change may not
  open the hole. The plugin sets and restores it on create/teardown as a safety net.
- The widget must be given the hole: a full-width area whose content the app paints nothing in -
  for a chat, the list area above the app's own band. The surface engine owns that hole's
  background and the scrolling content. (A forward surface's rectangle must instead reach the
  Flutter view's bottom; a behind surface's may stop above its band.)
- Touches are passed through the Flutter view to the surface only while `interactive` is true and
  this route is current; the plugin withholds them automatically under a pushed route or a modal,
  and the hole stays open so a sheet still draws over the live list. The passthrough rectangle
  follows the keyboard: the app's band/composer above the surface keeps its touches.
- The surface engine is translated by the keyboard inset and never resizes; the app sends the
  bottom band's height over the bridge so the hosted content ends above it.
- Because the surface is below the Flutter view, the hole's background must be painted by the
  surface isolate; the app's `fallback` must be the same background so a covered hole never flashes
  the window colour.

## API reference

### Main isolate

- `CupertinoKeyboardAccessory({required String entrypoint, required String libraryURI, double? height, bool hidden = false, CupertinoHostedInputAccessoryController? controller})`
  reserves the bar's height in the layout and hosts the accessory UI. The bar sizes itself from the
  accessory's content; `height` is only the first-frame reservation (default 56).
  `hidden` keeps the engine alive but skips drawing and hit-testing, so a bar that is only
  visible while its screen is open can be toggled instead of created and destroyed.
- `CupertinoHostedInputAccessoryController`
  - `void invoke(String method, [Object? arguments])` — send to the bar.
  - `void Function(String method, Object? arguments)? onInvoke` — receive from the bar.
  - `VoidCallback? onReady` — the bar installed its handler.
  - `void setInteractive(bool interactive)` — toggle touch passthrough for a behind surface.
- `CupertinoHostedKeyboardSurface({required String entrypoint, required String libraryURI, CupertinoHostedInputAccessoryController? controller, bool hidden = false, Widget? fallback, bool behind = false, bool interactive = true})`
  hosts the whole content area in the second engine (see above and "The behind surface"). It reports
  its rect to native, hides while its route is not current, renders `fallback` when hosting is
  unavailable or when a behind hole is closed, and forwards the interactive flag for touch
  passthrough.
- `CupertinoInteractiveKeyboard({required Widget child})` — the area where the interactive
  keyboard dismissal is enabled; put your scrollable inside.
- `CupertinoInputAccessory({required Widget child})` — the classic in-app bar.
- `isKeyboardDragging` — a package-level `ValueListenable<bool>` for the interactive dismissal
  gesture: true while the drag moves the keyboard, false the moment the finger is released (before
  the keyboard animates back or away). Use it from anywhere, e.g. a `ValueListenableBuilder` over
  an overlay.
- `setKeyboardTraceEnabled(bool enabled)` — the DEBUG-only pacing trace (native lines plus the Dart
  `viewInsets` half), for a `flutter run` session.

### Accessory isolate

- `runCupertinoAccessory(CupertinoAccessoryBuilder builder)` — run the bar; the builder gets a
  `CupertinoAccessoryController`.
- `runCupertinoKeyboardSurface(CupertinoAccessoryBuilder builder)` — run the surface; the builder
  gets the whole fixed-size surface and must not report a content height.
- `CupertinoAccessoryController`
  - `void invoke(String method, [Object? arguments])` — send to the app.
  - `void Function(String method, Object? arguments)? onInvoke` — receive from the app.
  - `void Function(bool dragging)? onKeyboardDragging` — the interactive drag state, forwarded to a
    surface only; pin the list's scroll offset while it is true.

### Notes

- The accessory entrypoint must be a top-level function annotated with
  `@pragma('vm:entry-point')`.
- The bar's height follows the accessory's content: the plugin lays the bar out at its natural
  height and resizes the native container, so a multiline composer grows the bar. Build the bar as
  an intrinsically sized widget (no `Expanded` or full-height scrollable against the vertical axis);
  the plugin adds the bottom safe area itself.
- The bar runs in a second isolate: it cannot use the main isolate's widget instances or theme;
  send what it needs through the bridge (as the theme example does).
- The bar's native container and the accessory engine's view are transparent: the plugin paints
  nothing behind the accessory's widgets, so whatever the app draws there (a chat background, a
  gradient) shows through. An app that wants an opaque bar paints one inside its accessory.
- `hidden` is the cheap visibility switch: the engine and its widget state stay alive, only
  drawing and hit-testing are skipped. Use it for a bar that appears with a panel or a screen;
  unmount the widget only when the bar is really done.
- The cleanest junction between the list and the bar: keep `resizeToAvoidBottomInset: false` and put
  `MediaQuery.viewInsets.bottom` into the list's bottom padding instead of resizing the body. The
  list's viewport then never changes size during a drag, so there is no moving clip edge and no
  scroll-offset correction; `CupertinoKeyboardAccessory` still reserves the composer's height in the
  layout. The list still follows the keyboard on the Flutter clock, so it can trail the composer by
  a frame; use a hosted surface when that is not acceptable.

## Example app

The `example/` project is a runnable gallery. Routes:

- `/hosted_surface` — the hosted frame-locked chat surface: list and composer in the second
  engine, moved with the keyboard.
- `/hosted_accessory` — the hosted Flutter composer on a chat-like screen (recommended path).
- `/input_accessory` — the classic in-app Flutter accessory.
- `/simple_scroll_view` — minimal interactive keyboard.
- `/reversed_scroll_view` — reversed list + cover-based keyboard.
- `/nested_navigation` — nested navigation with the keyboard.

## License

MIT — see `LICENSE`.
