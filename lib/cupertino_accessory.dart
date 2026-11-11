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

  /// Called with the interactive keyboard drag state while a hosted keyboard
  /// surface is being dragged down.
  ///
  /// The surface's whole view already moves natively with the keyboard, so
  /// scrollable content inside it must pin its offset instead of scrolling as
  /// well. Only a surface receives this; the accessory bar never does.
  void Function(bool dragging)? onKeyboardDragging;

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

/// Runs [builder] as the Flutter half of a hosted keyboard surface.
///
/// Use it from a top-level entrypoint the app points at with the
/// `CupertinoHostedKeyboardSurface` widget's entrypoint:
///
/// ```dart
/// @pragma('vm:entry-point')
/// void surfaceMain() => runCupertinoKeyboardSurface(
///   (context, controller) => MyChat(controller: controller),
/// );
/// ```
///
/// Unlike [runCupertinoAccessory] this is a full-size host: the builder gets
/// the whole fixed-size surface and no content height is reported. The layout
/// must fill that surface and must not depend on `MediaQuery.viewInsets`: the
/// surface's keyboard inset stays 0 by design, and the native container moves
/// the whole view instead.
void runCupertinoKeyboardSurface(CupertinoAccessoryBuilder builder) {
  runApp(CupertinoAccessoryHost(builder: builder, fullSize: true));
}

/// The chrome around an accessory UI or a surface: owns the channel and routes
/// calls between the main isolate and [builder]. [runCupertinoAccessory] and
/// [runCupertinoKeyboardSurface] pump it.
class CupertinoAccessoryHost extends StatefulWidget {
  const CupertinoAccessoryHost({
    super.key,
    required this.builder,
    this.fullSize = false,
  });

  final CupertinoAccessoryBuilder builder;

  /// Whether the host fills a fixed-size keyboard surface instead of sizing
  /// itself to its content: no scrollable sizer and no content-height
  /// reporting.
  final bool fullSize;

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
    final method = arguments['method'] as String? ?? '';
    final payload = arguments['arguments'];
    switch (method) {
      // The surface was hidden natively; drop focus so this isolate's focus
      // state matches the dismissed keyboard. The app does not need the call.
      case 'hidden':
        if (payload is Map && payload['hidden'] == true) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        return;
      case 'keyboardDragging':
        _controller.onKeyboardDragging?.call(
          payload is Map && payload['dragging'] == true,
        );
        return;
    }
    _controller.onInvoke?.call(method, payload);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: widget.fullSize
          ? Builder(
              builder: (context) => widget.builder(context, _controller),
            )
          : _AccessorySizer(builder: widget.builder, controller: _controller),
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
