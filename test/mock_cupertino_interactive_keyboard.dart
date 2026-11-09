import 'dart:async';
import 'dart:ui';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';

class MockCupertinoInteractiveKeyboard
    extends CupertinoInteractiveKeyboardPlatform {
  final scrollableRects = <int, Rect>{};
  final inputAccessoryHeights = <int, double>{};

  /// Arguments passed to [createHostedAccessory], in call order.
  final hostedAccessoryCreateCalls = <Map<String, Object?>>[];

  /// Heights passed to [updateHostedAccessoryHeight], in call order.
  final hostedAccessoryHeights = <double>[];

  /// Hidden values passed to [updateHostedAccessoryHidden], in call order.
  final hostedAccessoryHiddenCalls = <bool>[];

  /// Calls passed to [invokeHostedAccessory], in call order.
  final hostedAccessoryInvokes = <Map<String, Object?>>[];

  /// Number of [removeHostedAccessory] calls.
  int removeHostedAccessoryCalls = 0;

  /// The total height returned by [createHostedAccessory]; null keeps the
  /// widget on its placeholder height until a height event arrives.
  double? createResultHeight;

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
  Future<double?> createHostedAccessory({
    required String entrypoint,
    required String libraryURI,
    required double height,
    bool hidden = false,
  }) {
    hostedAccessoryCreateCalls.add({
      'entrypoint': entrypoint,
      'libraryURI': libraryURI,
      'height': height,
      'hidden': hidden,
    });
    return Future.value(createResultHeight);
  }

  @override
  Future<void> updateHostedAccessoryHidden(bool hidden) {
    hostedAccessoryHiddenCalls.add(hidden);
    return Future.value();
  }

  @override
  Future<void> updateHostedAccessoryHeight(double height) {
    hostedAccessoryHeights.add(height);
    return Future.value();
  }

  @override
  Future<void> invokeHostedAccessory(String method, Object? arguments) {
    hostedAccessoryInvokes.add({'method': method, 'arguments': arguments});
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
