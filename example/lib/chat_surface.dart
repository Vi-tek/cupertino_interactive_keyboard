import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';

/// What [CupertinoHostedKeyboardSurface] is wired with: the entrypoint the
/// surface engine runs and the library that declares it.
///
/// The engine looks the library up in the app's compiled kernel, so this
/// library must be imported by something the app's entrypoint reaches. The
/// screen does that import.
const surfaceEntrypoint = 'surfaceMain';
const surfaceLibraryURI = 'package:example/chat_surface.dart';

/// One chat message, crossing the bridge as a map because the two isolates
/// cannot share objects.
class ChatMessage {
  const ChatMessage(this.text, {required this.mine});

  factory ChatMessage.fromArguments(Object? arguments) {
    final map = arguments is Map ? arguments : const <Object?, Object?>{};
    return ChatMessage(
      (map['text'] as String?) ?? '',
      mine: map['mine'] == true,
    );
  }

  final String text;
  final bool mine;

  Map<String, Object?> toArguments() => {'text': text, 'mine': mine};
}

/// Entrypoint of the surface engine for this app's chat screen.
///
/// The plugin starts it in a second engine and hosts its view in a native
/// container that UIKit moves with the keyboard, so the list and the composer
/// ride the keyboard frame for frame.
@pragma('vm:entry-point')
void surfaceMain() {
  runCupertinoKeyboardSurface(
    (context, controller) => ChatSurface(controller: controller),
  );
}

/// The chat content hosted in the surface engine: the message list and the
/// composer, laid out against the fixed surface height.
///
/// This engine's view is transparent and the surface is moved natively, so the
/// page background belongs to the main engine and nothing here may resize for
/// the keyboard: [MediaQuery.viewInsets] stays 0 by design and the bottom
/// padding is 0, because the engine view never reaches the home indicator. The
/// left/right safe areas still apply (a notch in landscape), so rows and the
/// composer use them.
class ChatSurface extends StatefulWidget {
  const ChatSurface({super.key, required this.controller});

  final CupertinoAccessoryController controller;

  @override
  State<ChatSurface> createState() => _ChatSurfaceState();
}

class _ChatSurfaceState extends State<ChatSurface> {
  final _field = TextEditingController();
  final _scroll = ScrollController();

  /// Colors sent by the main isolate; empty until its 'theme' call arrives.
  Map<Object?, Object?> _theme = const {};

  /// Messages sent by the main isolate, newest first (the list is reversed).
  List<ChatMessage> _messages = const [];

  /// Whether the keyboard is being dragged down; the native container moves the
  /// whole surface then, so the list must not scroll as well.
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.onInvoke = _handleInvoke;
    widget.controller.onKeyboardDragging = _handleKeyboardDragging;
  }

  @override
  void dispose() {
    widget.controller.onInvoke = null;
    widget.controller.onKeyboardDragging = null;
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _handleInvoke(String method, Object? arguments) {
    final map = arguments is Map ? arguments : const <Object?, Object?>{};
    switch (method) {
      case 'theme':
        setState(() => _theme = map);
        break;
      case 'messages':
        final messages = map['messages'];
        setState(() {
          _messages = messages is List
              ? messages.map(ChatMessage.fromArguments).toList()
              : const [];
        });
        break;
      case 'setText':
        final text = (map['text'] as String?) ?? '';
        _field.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        break;
    }
  }

  void _handleKeyboardDragging(bool dragging) {
    setState(() => _dragging = dragging);
  }

  void _send() {
    final text = _field.text.trim();
    if (text.isEmpty) {
      return;
    }
    widget.controller.invoke('send', {'text': text});
  }

  Color _color(String key, Color fallback) {
    final value = _theme[key];
    return value is int ? Color(value) : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = _color('surface', scheme.surface);
    final onSurface = _color('onSurface', scheme.onSurface);
    final primary = _color('primary', scheme.primary);
    final onPrimary = _color('onPrimary', scheme.onPrimary);
    final hint = _color('hint', scheme.onSurfaceVariant);
    final divider = _color('divider', scheme.outlineVariant);
    final otherBubble = Color.alphaBlend(
      onSurface.withValues(alpha: 0.08),
      surface,
    );
    final safe = MediaQuery.paddingOf(context);

    return Material(
      // The main engine paints the page background; only the rows and the
      // composer are opaque in the surface.
      type: MaterialType.transparency,
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              // Pinned for the duration of the drag: the native container
              // already moves the whole surface, so scrolling as well would
              // double the motion.
              physics: _dragging ? const NeverScrollableScrollPhysics() : null,
              padding: EdgeInsets.fromLTRB(
                16 + safe.left,
                16,
                16 + safe.right,
                8,
              ),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _MessageBubble(
                message: _messages[index],
                color: _messages[index].mine ? primary : otherBubble,
                textColor: _messages[index].mine ? onPrimary : onSurface,
              ),
            ),
          ),
          _buildComposer(
            surface: surface,
            onSurface: onSurface,
            primary: primary,
            onPrimary: onPrimary,
            hint: hint,
            divider: divider,
          ),
        ],
      ),
    );
  }

  Widget _buildComposer({
    required Color surface,
    required Color onSurface,
    required Color primary,
    required Color onPrimary,
    required Color hint,
    required Color divider,
  }) {
    final fieldColor = Color.alphaBlend(
      onSurface.withValues(alpha: 0.06),
      surface,
    );
    final safe = MediaQuery.paddingOf(context);
    return Material(
      color: surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: divider, width: 0.5)),
        ),
        padding: EdgeInsets.fromLTRB(12 + safe.left, 8, 12 + safe.right, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 40, maxHeight: 96),
                decoration: BoxDecoration(
                  color: fieldColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _field,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: onSurface, fontSize: 16),
                  cursorColor: primary,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: hint, fontSize: 16),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (text) =>
                      widget.controller.invoke('textChanged', {'text': text}),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _field,
              builder: (context, value, _) {
                final canSend = value.text.trim().isNotEmpty;
                return IconButton.filled(
                  onPressed: canSend ? _send : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: onPrimary,
                    disabledBackgroundColor: primary.withValues(alpha: 0.25),
                    disabledForegroundColor: onPrimary.withValues(alpha: 0.65),
                    minimumSize: const Size(40, 40),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.color,
    required this.textColor,
  });

  final ChatMessage message;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
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
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: textColor, height: 1.3),
        ),
      ),
    );
  }
}
