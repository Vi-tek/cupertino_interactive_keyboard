import 'dart:async';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The main isolate's end of the hosted Flutter accessory bridge.
///
/// The accessory runs in a second Flutter engine, so it cannot share objects
/// with this isolate. Instead it calls back with a method name and an optional
/// argument, and this controller calls into it the same way.
class CupertinoHostedInputAccessoryController {
  /// Called with every method call the accessory invokes.
  void Function(String method, Object? arguments)? onInvoke;

  /// Called once the accessory engine is listening for calls.
  VoidCallback? onReady;

  /// Invokes [method] with [arguments] in the accessory isolate.
  ///
  /// Calls made before the accessory is ready are queued by the plugin until
  /// it is.
  void invoke(String method, [Object? arguments]) {
    CupertinoInteractiveKeyboardPlatform.instance
        .invokeHostedAccessory(method, arguments);
  }
}

/// Reserves the height of the hosted Flutter input accessory bar and gives the
/// app a channel to its widgets.
///
/// The bar itself is a second Flutter engine's view inside a native container
/// owned by the plugin; this widget only keeps the Flutter layout clear of it
/// and routes messages. [entrypoint] and [libraryURI] identify the Dart
/// function the accessory engine runs. On platforms other than iOS it renders
/// nothing and calls nothing.
class CupertinoKeyboardAccessory extends StatefulWidget {
  const CupertinoKeyboardAccessory({
    super.key,
    required this.entrypoint,
    required this.libraryURI,
    this.height = 56,
    this.controller,
  });

  /// Dart entrypoint the accessory engine runs, e.g. `accessoryMain`.
  final String entrypoint;

  /// Library URI that contains [entrypoint].
  final String libraryURI;

  /// The bar's height without the bottom safe area.
  final double height;

  /// The main isolate's half of the bridge; one is created internally when
  /// null, so pass one to receive calls.
  final CupertinoHostedInputAccessoryController? controller;

  @override
  State<CupertinoKeyboardAccessory> createState() =>
      _CupertinoKeyboardAccessoryState();
}

class _CupertinoKeyboardAccessoryState
    extends State<CupertinoKeyboardAccessory> {
  late final CupertinoHostedInputAccessoryController _controller;
  StreamSubscription<Map<String, Object?>>? _events;

  /// The total bar height reported by native, including the bottom safe area.
  double? _reportedHeight;

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? CupertinoHostedInputAccessoryController();
    if (!_isIOS) {
      return;
    }
    _events = CupertinoInteractiveKeyboardPlatform
        .instance.hostedAccessoryEvents
        .listen(_handleEvent);
    _create();
  }

  @override
  void didUpdateWidget(CupertinoKeyboardAccessory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isIOS || widget.height == oldWidget.height) {
      return;
    }
    // Native will report the new total height; until then reserve the new
    // requested height plus the safe area.
    _reportedHeight = null;
    CupertinoInteractiveKeyboardPlatform.instance
        .updateHostedAccessoryHeight(widget.height);
  }

  @override
  void dispose() {
    _events?.cancel();
    if (_isIOS) {
      CupertinoInteractiveKeyboardPlatform.instance.removeHostedAccessory();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isIOS) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: _reportedHeight ??
          (widget.height + MediaQuery.paddingOf(context).bottom),
    );
  }

  Future<void> _create() async {
    final height = await CupertinoInteractiveKeyboardPlatform.instance
        .createHostedAccessory(
      entrypoint: widget.entrypoint,
      libraryURI: widget.libraryURI,
      height: widget.height,
    );
    if (!mounted || height == null) {
      return;
    }
    setState(() => _reportedHeight = height);
  }

  void _handleEvent(Map<String, Object?> event) {
    if (!mounted) {
      return;
    }
    switch (event['type']) {
      case 'height':
        final height = (event['height'] as num?)?.toDouble();
        if (height != null) {
          setState(() => _reportedHeight = height);
        }
        break;
      case 'ready':
        _controller.onReady?.call();
        break;
      case 'invoke':
        _controller.onInvoke?.call(
          event['method'] as String? ?? '',
          event['arguments'],
        );
        break;
    }
  }
}
