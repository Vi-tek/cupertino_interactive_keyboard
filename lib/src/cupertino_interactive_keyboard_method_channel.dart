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
  Future<bool?> initialize({required bool firstTime}) async {
    return methodChannel.invokeMethod<bool>('initialize', {
      'firstTime': firstTime,
    });
  }

  @override
  Future<void> setScrollableRect(int id, Rect rect) {
    return methodChannel.invokeMethod('setScrollableRect', {
      'id': id,
      'rect': {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      },
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
  }) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'createHostedAccessory',
      {
        'entrypoint': entrypoint,
        'libraryURI': libraryURI,
        'height': height,
      },
    );
    return (result?['height'] as num?)?.toDouble();
  }

  @override
  Future<void> updateHostedAccessoryHeight(double height) {
    return methodChannel.invokeMethod('updateHostedAccessoryHeight', {
      'height': height,
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
  Future<void> removeHostedAccessory() {
    return methodChannel.invokeMethod('removeHostedAccessory');
  }

  Future<Object?> _handleMethodCall(MethodCall call) {
    final arguments = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'hostedAccessoryHeight':
        _hostedAccessoryEvents.add({
          'type': 'height',
          'height': (arguments['height'] as num).toDouble(),
        });
        return Future.value();
      case 'hostedAccessoryReady':
        _hostedAccessoryEvents.add({'type': 'ready'});
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
