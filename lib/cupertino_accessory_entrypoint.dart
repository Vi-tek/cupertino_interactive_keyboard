import 'package:cupertino_interactive_keyboard/cupertino_accessory.dart';
import 'package:flutter/material.dart';

/// Entrypoint of the accessory engine: the plugin's default composer bar.
@pragma('vm:entry-point')
void cupertinoAccessoryMain() {
  runCupertinoAccessory(cupertinoAccessoryBuilder);
}

/// Builds the plugin's default bar for [CupertinoAccessoryHost].
Widget cupertinoAccessoryBuilder(
  BuildContext context,
  CupertinoAccessoryController controller,
) {
  return CupertinoAccessoryApp(controller: controller);
}

/// The default composer: a Flutter text field and a send button, styled from
/// the config the main isolate pushed.
class CupertinoAccessoryApp extends StatefulWidget {
  const CupertinoAccessoryApp({super.key, required this.controller});

  final CupertinoAccessoryController controller;

  @override
  State<CupertinoAccessoryApp> createState() => _CupertinoAccessoryAppState();
}

class _CupertinoAccessoryAppState extends State<CupertinoAccessoryApp> {
  final _field = TextEditingController();

  static const _icons = <String, IconData>{'paperplane.fill': Icons.send};

  @override
  void initState() {
    super.initState();
    _field.text = widget.controller.text.value;
    widget.controller.text.addListener(_applyExternalText);
  }

  @override
  void dispose() {
    widget.controller.text.removeListener(_applyExternalText);
    _field.dispose();
    super.dispose();
  }

  void _applyExternalText() {
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
        return Scaffold(
          backgroundColor:
              config.backgroundColor ?? Theme.of(context).colorScheme.surface,
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _field,
                      style: TextStyle(color: config.textColor),
                      decoration: InputDecoration(
                        hintText: config.placeholder,
                        hintStyle: TextStyle(color: config.placeholderColor),
                        border: InputBorder.none,
                      ),
                      onChanged: widget.controller.textChanged,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _icons[config.icon] ?? Icons.send,
                      color: config.iconColor,
                    ),
                    onPressed: () => widget.controller.send(_field.text),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
