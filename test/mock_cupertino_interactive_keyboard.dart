import 'dart:async';
import 'dart:ui';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';

class MockCupertinoInteractiveKeyboard
    extends CupertinoInteractiveKeyboardPlatform {
  final scrollableRects = <int, Rect>{};
  final inputAccessoryHeights = <int, double>{};

  /// Configs passed to [createHostedAccessory], in call order.
  final hostedAccessoryCreateConfigs = <Map<String, Object?>>[];

  /// Configs passed to [updateHostedAccessory], in call order.
  final hostedAccessoryUpdateConfigs = <Map<String, Object?>>[];

  /// Texts passed to [setHostedAccessoryText], in call order.
  final hostedAccessoryTexts = <String>[];

  /// Number of [removeHostedAccessory] calls.
  int removeHostedAccessoryCalls = 0;

  final _hostedAccessoryEvents =
      StreamController<Map<String, Object?>>.broadcast();

  /// Emits a native -> Dart event as the method channel implementation would.
  void emitHostedAccessoryEvent(Map<String, Object?> event) {
    _hostedAccessoryEvents.add(event);
  }

  @override
  Stream<Map<String, Object?>> get hostedAccessoryEvents =>
      _hostedAccessoryEvents.stream;

  @override
  Future<double?> createHostedAccessory(Map<String, Object?> config) {
    hostedAccessoryCreateConfigs.add(config);
    // Null: the widget keeps its placeholder height until a height event.
    return Future.value();
  }

  @override
  Future<void> updateHostedAccessory(Map<String, Object?> config) {
    hostedAccessoryUpdateConfigs.add(config);
    return Future.value();
  }

  @override
  Future<void> setHostedAccessoryText(String text) {
    hostedAccessoryTexts.add(text);
    return Future.value();
  }

  @override
  Future<void> removeHostedAccessory() {
    removeHostedAccessoryCalls++;
    return Future.value();
  }

  @override
  Future<bool?> initialize({required bool firstTime}) {
    if (firstTime) {
      scrollableRects.clear();
      inputAccessoryHeights.clear();
    }
    return Future.value(true);
  }

  @override
  Future<void> setScrollableRect(int id, Rect rect) {
    scrollableRects[id] = rect;
    return Future.value();
  }

  @override
  Future<void> removeScrollableRect(int id) {
    scrollableRects.remove(id);
    return Future.value();
  }

  @override
  Future<void> setInputAccessoryHeight(int id, double height) {
    inputAccessoryHeights[id] = height;
    return Future.value();
  }

  @override
  Future<void> removeInputAccessoryHeight(int id) {
    inputAccessoryHeights.remove(id);
    return Future.value();
  }
}
