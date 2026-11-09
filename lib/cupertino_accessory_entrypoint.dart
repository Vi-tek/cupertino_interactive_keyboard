import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Channel between the plugin (native) and the accessory engine.
const _kAccessoryChannel =
    MethodChannel('cupertino_interactive_keyboard/accessory');

/// Entrypoint of the accessory engine: runs the composer bar in a second
/// isolate, configured by native over [_kAccessoryChannel].
@pragma('vm:entry-point')
void cupertinoAccessoryMain() {
  runApp(const CupertinoAccessoryApp());
}

/// The Material app hosted inside the native accessory container.
///
/// Native pushes `config` and `setText`; the app reports `ready`,
/// `textChanged` and `send`.
class CupertinoAccessoryApp extends StatefulWidget {
  const CupertinoAccessoryApp({super.key});

  @override
  State<CupertinoAccessoryApp> createState() => _CupertinoAccessoryAppState();
}

class _CupertinoAccessoryAppState extends State<CupertinoAccessoryApp> {
  final _text = TextEditingController();
  Map<String, Object?> _config = const {};
  bool _receivedConfig = false;

  @override
  void initState() {
    super.initState();
    _kAccessoryChannel.setMethodCallHandler(_handleCall);
    // Native pushes the config once the accessory is listening.
    _kAccessoryChannel.invokeMethod<void>('ready');
  }

  @override
  void dispose() {
    _kAccessoryChannel.setMethodCallHandler(null);
    _text.dispose();
    super.dispose();
  }

  Future<void> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'config':
        _applyConfig((call.arguments as Map?) ?? const {});
        break;
      case 'setText':
        // Writing the controller does not fire [TextField.onChanged], so this
        // never echoes a textChanged back to native.
        _text.text = ((call.arguments as Map?)?['text'] as String?) ?? '';
        break;
    }
  }

  void _applyConfig(Map<dynamic, dynamic> raw) {
    final config = Map<String, Object?>.from(raw);
    final text = config['text'];
    setState(() => _config = config);
    // Later config pushes may carry the stale create-time text; adopting it
    // again would wipe what the user typed. Mirroring uses `setText`.
    if (!_receivedConfig) {
      _receivedConfig = true;
      if (text is String) {
        _text.text = text;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _AccessoryBar(
        config: _config,
        text: _text,
        onChanged: (text) => _kAccessoryChannel.invokeMethod<void>(
          'textChanged',
          {'text': text},
        ),
        onSend: () => _kAccessoryChannel.invokeMethod<void>(
          'send',
          {'text': _text.text},
        ),
      ),
    );
  }
}

class _AccessoryBar extends StatelessWidget {
  const _AccessoryBar({
    required this.config,
    required this.text,
    required this.onChanged,
    required this.onSend,
  });

  final Map<String, Object?> config;
  final TextEditingController text;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  static const _icons = <String, IconData>{'paperplane.fill': Icons.send};

  static Color? _color(Object? argb) => argb is int ? Color(argb) : null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = _color(config['backgroundColor']);
    final textColor = _color(config['textColor']);
    final placeholderColor = _color(config['placeholderColor']);
    final iconColor = _color(config['iconColor']);

    return Scaffold(
      backgroundColor: backgroundColor ?? colorScheme.surface,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: text,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: config['placeholder'] as String? ?? '',
                    hintStyle: TextStyle(color: placeholderColor),
                    border: InputBorder.none,
                  ),
                  onChanged: onChanged,
                ),
              ),
              IconButton(
                icon: Icon(
                  _icons[config['icon']] ?? Icons.send,
                  color: iconColor,
                ),
                onPressed: onSend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
