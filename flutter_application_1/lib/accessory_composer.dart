import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';

/// Entrypoint of the accessory engine for this app's own composer bar.
///
/// The plugin starts this entrypoint in a second engine and puts its view in a
/// native container pinned to the keyboard, so this Flutter UI (TextField and
/// all) rides the keyboard frame for frame.
@pragma('vm:entry-point')
void accessoryMain() {
  runCupertinoAccessory(
    (context, controller) => AccessoryComposer(controller: controller),
  );
}

/// The app's own Flutter composer, written like any other Flutter widget.
class AccessoryComposer extends StatefulWidget {
  const AccessoryComposer({super.key, required this.controller});

  final CupertinoAccessoryController controller;

  @override
  State<AccessoryComposer> createState() => _AccessoryComposerState();
}

class _AccessoryComposerState extends State<AccessoryComposer> {
  final _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    _field.text = widget.controller.text.value;
    widget.controller.text.addListener(_syncFromMainIsolate);
  }

  @override
  void dispose() {
    widget.controller.text.removeListener(_syncFromMainIsolate);
    _field.dispose();
    super.dispose();
  }

  void _syncFromMainIsolate() {
    final text = widget.controller.text.value;
    if (_field.text != text) {
      _field.text = text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CupertinoAccessoryConfig>(
      valueListenable: widget.controller.config,
      builder: (context, config, _) {
        return Material(
          elevation: 8,
          color:
              config.backgroundColor ?? Theme.of(context).colorScheme.surface,
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
                    style: TextStyle(color: config.textColor),
                    decoration: InputDecoration(
                      hintText: "nekddkdklll",
                      hintStyle: TextStyle(color: config.placeholderColor),
                    ),
                    onChanged: widget.controller.textChanged,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => widget.controller.send(_field.text),
                  icon: Icon(Icons.abc, color: config.iconColor),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
