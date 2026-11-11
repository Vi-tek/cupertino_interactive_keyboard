import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:example/chat_surface.dart';
import 'package:flutter/material.dart';

/// The hosted keyboard surface demo: the app bar and the page background stay
/// in this isolate, while the chat list and the composer are a second Flutter
/// engine whose native container rides the keyboard.
///
/// The page is inset-immune on purpose (`resizeToAvoidBottomInset: false`, no
/// inset padding, a static app bar): the surface moves natively with the
/// keyboard, so nothing in this engine may resize or pad for it.
class HostedSurfaceScreen extends StatefulWidget {
  const HostedSurfaceScreen({super.key});

  @override
  State<HostedSurfaceScreen> createState() => _HostedSurfaceScreenState();
}

class _HostedSurfaceScreenState extends State<HostedSurfaceScreen> {
  final _controller = CupertinoHostedInputAccessoryController();

  /// Whether the plugin's native trace is on (debug builds only).
  bool _traceEnabled = false;

  /// The chat, kept here: the surface isolate receives it after every change.
  final _messages = <ChatMessage>[
    const ChatMessage(
      'This list and the composer live in a second Flutter engine. Its view '
      'has a fixed frame and is moved by a native transform, so during an '
      'interactive keyboard dismissal it moves with the keyboard frame for '
      'frame instead of a frame behind it.',
      mine: false,
    ),
    const ChatMessage('Touch the list and drag down to dismiss.', mine: false),
    const ChatMessage('The app bar is drawn by the main engine.', mine: false),
    const ChatMessage(
      'The surface view is transparent: the page background shows through.',
      mine: false,
    ),
    const ChatMessage(
      'The list is pinned while the keyboard is dragged down: the whole '
      'surface already moves, so it must not scroll as well.',
      mine: false,
    ),
  ];

  /// The text the surface last reported, shown under the title as a preview.
  String _draft = '';

  @override
  void initState() {
    super.initState();
    _controller.onReady = _sendAppState;
    _controller.onInvoke = _handleSurfaceInvoke;
  }

  @override
  void dispose() {
    _controller.onReady = null;
    _controller.onInvoke = null;
    super.dispose();
  }

  /// The surface engine is listening; give it the chat and the colors.
  void _sendAppState() {
    if (!mounted) {
      return;
    }
    _sendTheme();
    _sendMessages();
  }

  void _sendTheme() {
    final scheme = Theme.of(context).colorScheme;
    _controller.invoke('theme', {
      'surface': scheme.surface.toARGB32(),
      'onSurface': scheme.onSurface.toARGB32(),
      'primary': scheme.primary.toARGB32(),
      'onPrimary': scheme.onPrimary.toARGB32(),
      'hint': scheme.onSurfaceVariant.toARGB32(),
      'divider': scheme.outlineVariant.toARGB32(),
    });
  }

  void _sendMessages() {
    _controller.invoke('messages', {
      'messages': _messages.map((message) => message.toArguments()).toList(),
    });
  }

  void _handleSurfaceInvoke(String method, Object? arguments) {
    if (!mounted) {
      return;
    }
    final args = arguments is Map ? arguments : const <Object?, Object?>{};
    switch (method) {
      case 'textChanged':
        setState(() => _draft = (args['text'] as String?) ?? '');
        break;
      case 'send':
        final text = ((args['text'] as String?) ?? '').trim();
        if (text.isNotEmpty) {
          setState(() => _messages.insert(0, ChatMessage(text, mine: true)));
        }
        _draft = '';
        _sendMessages();
        // Clear the field in the surface; it owns the text editing state.
        _controller.invoke('setText', {'text': ''});
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 68,
        actions: [
          IconButton(
            tooltip: 'Native keyboard trace',
            icon: Icon(
              _traceEnabled ? Icons.bug_report : Icons.bug_report_outlined,
            ),
            onPressed: () {
              setState(() => _traceEnabled = !_traceEnabled);
              debugPrint('[cik] trace ${_traceEnabled ? 'ON' : 'OFF'}');
              setKeyboardTraceEnabled(_traceEnabled);
            },
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Frame-locked chat'),
            Text(
              _draft.isEmpty ? 'Hosted keyboard surface' : _draft,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // The page background is this engine's: the surface view is
          // transparent, so it shows through behind the rows and the composer.
          Positioned.fill(child: ColoredBox(color: scheme.surface)),
          Positioned.fill(
            child: CupertinoInteractiveKeyboard(
              child: CupertinoHostedKeyboardSurface(
                entrypoint: surfaceEntrypoint,
                libraryURI: surfaceLibraryURI,
                controller: _controller,
                fallback: const _SurfaceFallback(),
              ),
            ),
          ),
          // The home-indicator strip under the surface at rest, in the
          // composer's colour: the surface's engine view stops above it.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.paddingOf(context).bottom,
            child: ColoredBox(color: scheme.surface),
          ),
        ],
      ),
    );
  }
}

/// What this screen shows when a hosted surface cannot run (iOS below 15, or a
/// platform the plugin does not support).
class _SurfaceFallback extends StatelessWidget {
  const _SurfaceFallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'The frame-locked chat needs a hosted keyboard surface, which is '
          'available on iOS 15 and newer.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
