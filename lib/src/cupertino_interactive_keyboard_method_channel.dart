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
  Future<double?> createHostedAccessory(Map<String, Object?> config) async {
    final result = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'createHostedAccessory',
      config,
    );
    return (result?['height'] as num?)?.toDouble();
  }

  @override
  Future<void> updateHostedAccessory(Map<String, Object?> config) {
    return methodChannel.invokeMethod('updateHostedAccessory', config);
  }

  @override
  Future<void> setHostedAccessoryText(String text) {
    return methodChannel.invokeMethod('setHostedAccessoryText', {'text': text});
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
      case 'hostedAccessoryTextChanged':
        _hostedAccessoryEvents.add({
          'type': 'textChanged',
          'text': arguments['text'] as String? ?? '',
        });
        return Future.value();
      case 'hostedAccessorySend':
        _hostedAccessoryEvents.add({
          'type': 'send',
          'text': arguments['text'] as String? ?? '',
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
