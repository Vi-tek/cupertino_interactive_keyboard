import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';

/// What [CupertinoKeyboardAccessory] is wired with: the entrypoint the accessory
/// engine runs and the library that declares it.
///
/// The engine looks the library up in the app's compiled kernel, so this library
/// must be imported by something the app's entrypoint reaches. The screen does
/// that import.
const accessoryEntrypoint = 'accessoryMain';
const accessoryLibraryURI = 'package:example/keyboard_composer.dart';

/// Entrypoint of the accessory engine for this app's own composer bar.
/// The plugin starts this entrypoint in a second engine and puts its view in a
/// native container pinned to the keyboard, so this Flutter UI (TextField and
/// all) rides the keyboard frame for frame.
@pragma('vm:entry-point')
void accessoryMain() {
  runCupertinoAccessory(
    (context, controller) => KeyboardComposer(controller: controller),
  );
}

class KeyboardComposer extends StatefulWidget {
  const KeyboardComposer({super.key, required this.controller});

  final CupertinoAccessoryController controller;

  @override
  State<KeyboardComposer> createState() => _KeyboardComposerState();
}

class _KeyboardComposerState extends State<KeyboardComposer> {
  final _field = TextEditingController();

  /// Colors sent by the main isolate; null until its 'theme' call arrives.
  _AccessoryTheme? _theme;

  @override
  void initState() {
    super.initState();
    widget.controller.onInvoke = _handleInvoke;
  }

  @override
  void dispose() {
    widget.controller.onInvoke = null;
    _field.dispose();
    super.dispose();
  }

  void _handleInvoke(String method, Object? arguments) {
    switch (method) {
      case 'theme':
        final theme = _AccessoryTheme.fromArguments(arguments);
        if (mounted) {
          setState(() => _theme = theme);
        }
        break;
      case 'setText':
        final text = ((arguments as Map?)?['text'] as String?) ?? '';
        _field.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        break;
    }
  }

  void _send() {
    final text = _field.text.trim();
    if (text.isEmpty) {
      return;
    }
    widget.controller.invoke('send', {'text': text});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = _theme;
    final surface = theme?.surface ?? scheme.surface;
    final onSurface = theme?.onSurface ?? scheme.onSurface;
    final primary = theme?.primary ?? scheme.primary;
    final onPrimary = theme?.onPrimary ?? scheme.onPrimary;
    final hint = theme?.hint ?? scheme.onSurfaceVariant;
    final divider = theme?.divider ?? scheme.outlineVariant;
    final fieldColor = Color.alphaBlend(
      onSurface.withValues(alpha: 0.06),
      surface,
    );

    return Material(
      color: surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: divider, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: 40,
                      maxHeight: 96,
                    ),
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
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                      ),
                      onChanged: (text) => widget.controller.invoke(
                        'textChanged',
                        {'text': text},
                      ),
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
                        disabledBackgroundColor: primary.withValues(
                          alpha: 0.25,
                        ),
                        disabledForegroundColor: onPrimary.withValues(
                          alpha: 0.65,
                        ),
                        minimumSize: const Size(40, 40),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The colors the main isolate sends with its 'theme' call.
class _AccessoryTheme {
  const _AccessoryTheme({
    required this.surface,
    required this.onSurface,
    required this.primary,
    required this.onPrimary,
    required this.hint,
    required this.divider,
  });

  factory _AccessoryTheme.fromArguments(Object? arguments) {
    final map = arguments is Map ? arguments : const <Object?, Object?>{};
    Color color(String key, Color fallback) {
      final value = map[key];
      return value is int ? Color(value) : fallback;
    }

    return _AccessoryTheme(
      surface: color('surface', const Color(0xFFFFFFFF)),
      onSurface: color('onSurface', const Color(0xFF1C1C1E)),
      primary: color('primary', const Color(0xFF0A84FF)),
      onPrimary: color('onPrimary', const Color(0xFFFFFFFF)),
      hint: color('hint', const Color(0xFF8E8E93)),
      divider: color('divider', const Color(0x33000000)),
    );
  }

  final Color surface;
  final Color onSurface;
  final Color primary;
  final Color onPrimary;
  final Color hint;
  final Color divider;
}
