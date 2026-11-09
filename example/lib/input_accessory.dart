import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';

const _kNumberOfItems = 100;

/// The classic path: the accessory bar is an ordinary Flutter widget inside the
/// app's own Flutter view, laid out above the keyboard by the plugin's inset.
/// It can trail the keyboard by a frame during interactive dismissal; use the
/// hosted bar (see the hosted_accessory example) when that matters.
class InputAccessory extends StatefulWidget {
  const InputAccessory({super.key});

  @override
  State<StatefulWidget> createState() => _InputAccessoryState();
}

class _InputAccessoryState extends State<InputAccessory> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Input Accessory")),
      body: Column(
        children: [
          Expanded(
            child: CupertinoInteractiveKeyboard(
              child: ListView.separated(
                itemCount: _kNumberOfItems,
                itemBuilder: (context, index) =>
                    ListTile(title: Text("List Item #$index")),
                separatorBuilder: (context, index) => const Divider(height: 1),
              ),
            ),
          ),
          CupertinoInputAccessory(
            child: Material(
              elevation: 8,
              color: scheme.surface,
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
                        decoration: const InputDecoration(
                          hintText: "Input comment...",
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _field.clear,
                      icon: Icon(Icons.send, color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
