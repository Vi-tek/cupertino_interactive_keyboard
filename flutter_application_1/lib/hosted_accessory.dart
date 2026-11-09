import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';

const _kNumberOfItems = 100;

/// The hosted Flutter accessory bar demo: no other toolbar or overlay is
/// involved, so the screen shows exactly one bar riding the keyboard.
class HostedAccessory extends StatefulWidget {
  const HostedAccessory({super.key});

  @override
  State<StatefulWidget> createState() => _HostedAccessoryState();
}

class _HostedAccessoryState extends State<HostedAccessory> {
  final _controller = CupertinoHostedInputAccessoryController();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Hosted Accessory")),
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
            placeholder: "Input comment...",
            icon: "paperplane.fill",
            backgroundColor: colorScheme.surface,
            textColor: colorScheme.onSurface,
            placeholderColor: colorScheme.onSurface.withValues(alpha: 0.5),
            iconColor: colorScheme.primary,
            controller: _controller,
            // This app's own Flutter bar, running in the accessory engine.
            accessoryEntrypoint: 'accessoryMain',
            accessoryLibraryURI: 'package:flutter_application_1/accessory_composer.dart',
            onSend: (_) => _controller.clear(),
          ),
        ],
      ),
    );
  }
}