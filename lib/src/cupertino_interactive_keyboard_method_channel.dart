import 'dart:async';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An implementation of [CupertinoInteractiveKeyboardPlatform] that uses method channels.
class MethodChannelCupertinoInteractiveKeyboard
    extends CupertinoInteractiveKeyboardPlatform {
  MethodChannelCupertinoInteractiveKeyboard() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('cupertino_interactive_keyboard');

  final _hostedAccessoryEvents =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get hostedAccessoryEvents =>
      _hostedAccessoryEvents.stream;

  @override
  Future<void> setTraceEnabled(bool enabled) {
    return methodChannel.invokeMethod('setTraceEnabled', {'enabled': enabled});
  }

  @override
  Future<bool?> initialize({required bool firstTime}) async {
    return methodChannel.invokeMethod<bool>('initialize', {
      'firstTime': firstTime,
    });
  }

  @override
  Future<void> setScrollableRect(int id, Rect rect) {
    return methodChannel.invokeMethod('setScrollableRect', {
      'id': id,
      'rect': _rectArguments(rect),
    });
  }

  @override
  Future<void> removeScrollableRect(int id) {
    return methodChannel.invokeMethod('removeScrollableRect', {
      'id': id,
    });
  }

  @override
  Future<void> setInputAccessoryHeight(int id, double height) {
    return methodChannel.invokeMethod('setInputAccessoryHeight', {
      'id': id,
      'height': height,
    });
  }

  @override
  Future<void> removeInputAccessoryHeight(int id) {
    return methodChannel.invokeMethod('removeInputAccessoryHeight', {
      'id': id,
    });
  }

  @override
  Future<double?> createHostedAccessory({
    required String entrypoint,
    required String libraryURI,
    required double height,
    bool hidden = false,
    Rect? rect,
    int? id,
    bool behind = false,
  }) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'createHostedAccessory',
      {
        'entrypoint': entrypoint,
        'libraryURI': libraryURI,
        'height': height,
        'hidden': hidden,
        if (rect != null) 'rect': _rectArguments(rect),
        if (id != null) 'id': id,
        if (behind) 'behind': true,
      },
    );
    return (result?['height'] as num?)?.toDouble();
  }

  @override
  Future<void> updateHostedAccessoryHidden(bool hidden) {
    return methodChannel.invokeMethod('updateHostedAccessoryHidden', {
      'hidden': hidden,
    });
  }

  @override
  Future<void> updateHostedAccessoryHeight(double height) {
    return methodChannel.invokeMethod('updateHostedAccessoryHeight', {
      'height': height,
    });
  }

  @override
  Future<void> setHostedSurfaceInteractive(bool interactive) {
    return methodChannel.invokeMethod('setHostedSurfaceInteractive', {
      'interactive': interactive,
    });
  }

  @override
  Future<void> updateHostedAccessoryRect(Rect rect) {
    return methodChannel.invokeMethod('updateHostedAccessoryRect', {
      'rect': _rectArguments(rect),
    });
  }

  @override
  Future<void> invokeHostedAccessory(String method, Object? arguments) {
    return methodChannel.invokeMethod('invokeHostedAccessory', {
      'method': method,
      'arguments': arguments,
    });
  }

  @override
  Future<void> removeHostedAccessory({int? id}) {
    if (id == null) {
      return methodChannel.invokeMethod('removeHostedAccessory');
    }
    return methodChannel.invokeMethod('removeHostedAccessory', {'id': id});
  }

  /// The channel shape of a logical-pixel rectangle, shared by every call that
  /// carries one.
  Map<String, double> _rectArguments(Rect rect) => {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      };

  Future<Object?> _handleMethodCall(MethodCall call) {
    final arguments = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'trace':
        debugPrint(arguments['line'] as String? ?? '');
        return Future.value();
      case 'hostedAccessoryHeight':
        _hostedAccessoryEvents.add({
          'type': 'height',
          'height': (arguments['height'] as num).toDouble(),
        });
        return Future.value();
      case 'keyboardDragging':
        keyboardDraggingState.value = arguments['dragging'] as bool? ?? false;
        return Future.value();
      case 'hostedAccessoryReady':
        _hostedAccessoryEvents.add({'type': 'ready'});
        return Future.value();
      case 'hostedAccessoryReleased':
        _hostedAccessoryEvents.add({
          'type': 'released',
          'id': (arguments['id'] as num?)?.toInt(),
        });
        return Future.value();
      case 'hostedAccessoryInvoke':
        _hostedAccessoryEvents.add({
          'type': 'invoke',
          'method': arguments['method'] as String? ?? '',
          'arguments': arguments['arguments'],
        });
        return Future.value();
      default:
        return Future.error(
          MissingPluginException(
            'No implementation found for method ${call.method} '
            'on channel ${methodChannel.name}',
          ),
        );
    }
  }
}
