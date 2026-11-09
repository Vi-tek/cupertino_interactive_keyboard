import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/accessory_composer.dart';
import 'package:keyboard_actions_bar/keyboard_actions_bar.dart';

const _kNumberOfItems = 100;

class InputAccessory extends StatefulWidget {
  const InputAccessory({super.key});

  @override
  State<StatefulWidget> createState() => _InputAccessoryState();
}

class _InputAccessoryState extends State<InputAccessory> {
  final _controller = CupertinoHostedInputAccessoryController();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
          CupertinoHostedInputAccessory(
            accessoryEntrypoint: 'accessoryMain',
            accessoryLibraryURI:
                'package:flutter_application_1/accessory_composer.dart',
            placeholder: 'Inputent...',
            backgroundColor: colorScheme.surface, // config reaches the bar
            controller: _controller,
            onSend: (_) => _controller.clear(),
          ),
        ],
      ),
    );
  }
}
