import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Channel between the plugin (native) and the accessory engine.
const MethodChannel accessoryChannel =
    MethodChannel('cupertino_interactive_keyboard/accessory');

/// The configuration the main isolate pushed into the accessory engine.
class CupertinoAccessoryConfig {
  const CupertinoAccessoryConfig({
    this.placeholder = '',
    this.icon = 'paperplane.fill',
    this.backgroundColor,
    this.textColor,
    this.placeholderColor,
    this.iconColor,
    this.height = 56,
  });

  factory CupertinoAccessoryConfig.fromArguments(
      Map<dynamic, dynamic> arguments) {
    Color? color(Object? value) => value is int ? Color(value) : null;

    return CupertinoAccessoryConfig(
      placeholder: arguments['placeholder'] as String? ?? '',
      icon: arguments['icon'] as String? ?? 'paperplane.fill',
      backgroundColor: color(arguments['backgroundColor']),
      textColor: color(arguments['textColor']),
      placeholderColor: color(arguments['placeholderColor']),
      iconColor: color(arguments['iconColor']),
      height: (arguments['height'] as num?)?.toDouble() ?? 56,
    );
  }

  final String placeholder;
  final String icon;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? placeholderColor;
  final Color? iconColor;
  final double height;
}

/// What a custom accessory UI gets from the plugin: the config to draw from and
/// the two calls it makes back into the main isolate.
class CupertinoAccessoryController {
  CupertinoAccessoryController._(this._text);

  final ValueNotifier<String> _text;
  final ValueNotifier<CupertinoAccessoryConfig> _config =
      ValueNotifier<CupertinoAccessoryConfig>(const CupertinoAccessoryConfig());

  /// Config pushed by [CupertinoHostedInputAccessory] on the main isolate.
  ValueListenable<CupertinoAccessoryConfig> get config => _config;

  /// Text written by the main isolate through the controller. Typing in the
  /// bar does not update this notifier, so a field can listen to it without
  /// fighting its own edits.
  ValueListenable<String> get text => _text;

  /// Reports typing to the main isolate ([CupertinoHostedInputAccessory.onChanged]).
  void textChanged(String value) {
    accessoryChannel.invokeMethod<void>('textChanged', {'text': value});
  }

  /// Reports the send action to the main isolate.
  void send(String value) {
    accessoryChannel.invokeMethod<void>('send', {'text': value});
  }
}

/// Builds the accessory UI inside the accessory engine's Material app.
typedef CupertinoAccessoryBuilder = Widget Function(
  BuildContext context,
  CupertinoAccessoryController controller,
);

/// Runs a custom accessory UI in the accessory engine.
///
/// Use it from a top-level entrypoint the main isolate points at with
/// [CupertinoHostedInputAccessory.accessoryEntrypoint]:
///
/// ```dart
/// @pragma('vm:entry-point')
/// void myAccessoryMain() => runCupertinoAccessory(
///   (context, controller) => MyComposer(controller: controller),
/// );
/// ```
void runCupertinoAccessory(CupertinoAccessoryBuilder builder) {
  runApp(CupertinoAccessoryHost(builder: builder));
}

/// The chrome around an accessory UI: owns the channel, the config and the
/// text pushed from the main isolate. [runCupertinoAccessory] pumps it.
class CupertinoAccessoryHost extends StatefulWidget {
  const CupertinoAccessoryHost({super.key, required this.builder});

  final CupertinoAccessoryBuilder builder;

  @override
  State<CupertinoAccessoryHost> createState() => _CupertinoAccessoryHostState();
}

class _CupertinoAccessoryHostState extends State<CupertinoAccessoryHost> {
  late final CupertinoAccessoryController _controller;
  bool _receivedConfig = false;

  @override
  void initState() {
    super.initState();
    _controller = CupertinoAccessoryController._(ValueNotifier<String>(''));
    accessoryChannel.setMethodCallHandler(_handleCall);
    // Native pushes the config once the accessory is listening.
    accessoryChannel.invokeMethod<void>('ready');
  }

  @override
  void dispose() {
    accessoryChannel.setMethodCallHandler(null);
    _controller._text.dispose();
    _controller._config.dispose();
    super.dispose();
  }

  Future<void> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'config':
        final arguments = (call.arguments as Map?) ?? const {};
        _controller._config.value = CupertinoAccessoryConfig.fromArguments(
          arguments,
        );
        // Later config pushes carry the stale create-time text; adopting it
        // again would wipe what the user typed. Mirroring uses setText.
        if (!_receivedConfig) {
          _receivedConfig = true;
          final text = arguments['text'];
          if (text is String) {
            _controller._text.value = text;
          }
        }
        break;
      case 'setText':
        _controller._text.value =
            ((call.arguments as Map?)?['text'] as String?) ?? '';
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => widget.builder(context, _controller),
      ),
    );
  }
}
