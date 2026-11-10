import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Channel between the plugin (native) and the accessory engine.
const MethodChannel accessoryChannel =
    MethodChannel('cupertino_interactive_keyboard/accessory');

/// The accessory isolate's end of the bridge to the main isolate.
///
/// The accessory runs in its own Flutter engine, so it talks to the app with
/// method names and optional arguments instead of shared objects.
class CupertinoAccessoryController {
  CupertinoAccessoryController._();

  /// Called with every method call the main isolate invokes on the accessory.
  void Function(String method, Object? arguments)? onInvoke;

  /// Invokes [method] with [arguments] in the main isolate.
  void invoke(String method, [Object? arguments]) {
    accessoryChannel.invokeMethod<void>(
      'invoke',
      {'method': method, 'arguments': arguments},
    );
  }
}

/// Builds the accessory UI inside the accessory engine's Material app.
typedef CupertinoAccessoryBuilder = Widget Function(
  BuildContext context,
  CupertinoAccessoryController controller,
);

/// Runs [builder] as the hosted keyboard accessory.
///
/// Use it from a top-level entrypoint the app points at with
/// [CupertinoHostedInputAccessory.entrypoint]:
///
/// ```dart
/// @pragma('vm:entry-point')
/// void accessoryMain() => runCupertinoAccessory(
///   (context, controller) => MyComposer(controller: controller),
/// );
/// ```
void runCupertinoAccessory(CupertinoAccessoryBuilder builder) {
  runApp(CupertinoAccessoryHost(builder: builder));
}

/// The chrome around an accessory UI: owns the channel and routes calls
/// between the main isolate and [builder]. [runCupertinoAccessory] pumps it.
class CupertinoAccessoryHost extends StatefulWidget {
  const CupertinoAccessoryHost({super.key, required this.builder});

  final CupertinoAccessoryBuilder builder;

  @override
  State<CupertinoAccessoryHost> createState() => _CupertinoAccessoryHostState();
}

class _CupertinoAccessoryHostState extends State<CupertinoAccessoryHost> {
  late final CupertinoAccessoryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CupertinoAccessoryController._();
    accessoryChannel.setMethodCallHandler(_handleCall);
    // Ready after the first build so [builder] had a chance to install its
    // [CupertinoAccessoryController.onInvoke] handler.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        accessoryChannel.invokeMethod<void>('ready');
      }
    });
  }

  @override
  void dispose() {
    accessoryChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'invoke') {
      throw MissingPluginException(
        'No implementation found for method ${call.method} '
        'on channel ${accessoryChannel.name}',
      );
    }
    final arguments = (call.arguments as Map?) ?? const {};
    _controller.onInvoke?.call(
      arguments['method'] as String? ?? '',
      arguments['arguments'],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _AccessorySizer(builder: widget.builder, controller: _controller),
    );
  }
}

/// Lays the app's bar out at its natural height and reports that height to native.
///
/// The bar is sized from this value, so the content is laid out with an unbounded height: a
/// composer that grows (a multiline field, a reply preview) can then ask for a taller bar instead
/// of being measured against the height the bar already has.
///
/// The contract for the app's bar: it must be intrinsically sized along the vertical axis. A
/// widget that only makes sense inside a bounded box (`Expanded`, a full-height scrollable) will
/// not report a useful height.
class _AccessorySizer extends StatefulWidget {
  const _AccessorySizer({required this.builder, required this.controller});

  final CupertinoAccessoryBuilder builder;
  final CupertinoAccessoryController controller;

  @override
  State<_AccessorySizer> createState() => _AccessorySizerState();
}

class _AccessorySizerState extends State<_AccessorySizer> {
  final _contentKey = GlobalKey();
  double? _reportedHeight;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: KeyedSubtree(
        key: _contentKey,
        child: widget.builder(context, widget.controller),
      ),
    );
  }

  void _reportHeight() {
    if (!mounted) {
      return;
    }
    final renderObject = _contentKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final height = renderObject.size.height;
    if (height <= 0) {
      return;
    }
    if (_reportedHeight != null && (height - _reportedHeight!).abs() < 0.5) {
      return;
    }
    _reportedHeight = height;
    accessoryChannel.invokeMethod<void>('contentHeight', {'height': height});
  }
}
