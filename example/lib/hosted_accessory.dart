import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';

/// The hosted Flutter accessory bar demo: a real chat screen in the app and a
/// second Flutter engine drawing the composer that rides the keyboard.
class HostedAccessory extends StatefulWidget {
  const HostedAccessory({super.key});

  @override
  State<HostedAccessory> createState() => _HostedAccessoryState();
}

class _HostedAccessoryState extends State<HostedAccessory> {
  final _controller = CupertinoHostedInputAccessoryController();
  final _messages = <_ChatMessage>[
    const _ChatMessage(
      'Type a message below and tap send. The bar is a second Flutter engine '
      'pinned to the keyboard.',
      mine: false,
    ),
    const _ChatMessage('This chat lives in the main isolate.', mine: false),
  ];

  /// The text the bar last reported, shown under the title as a small preview.
  String _draft = '';

  @override
  void initState() {
    super.initState();
    _controller.onReady = _sendTheme;
    _controller.onInvoke = _handleAccessoryInvoke;
  }

  @override
  void dispose() {
    _controller.onReady = null;
    _controller.onInvoke = null;
    super.dispose();
  }

  /// The accessory engine is listening; give it the app's current colors.
  void _sendTheme() {
    if (!mounted) {
      return;
    }
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

  void _handleAccessoryInvoke(String method, Object? arguments) {
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
          setState(() => _messages.insert(0, _ChatMessage(text, mine: true)));
        }
        _draft = '';
        // Clear the field in the accessory; it owns the text editing state.
        _controller.invoke('setText', {'text': ''});
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chat'),
            Text(
              _draft.isEmpty ? 'Hosted Flutter accessory' : _draft,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: CupertinoInteractiveKeyboard(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) =>
                    _MessageBubble(message: _messages[index]),
              ),
            ),
          ),
          CupertinoHostedInputAccessory(
            entrypoint: 'accessoryMain',
            libraryURI: 'package:flutter_application_1/accessory_composer.dart',
            height: 64,
            controller: _controller,
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage(this.text, {required this.mine});

  final String text;
  final bool mine;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: mine ? scheme.onPrimary : scheme.onSurface,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
