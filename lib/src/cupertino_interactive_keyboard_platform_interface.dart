import 'dart:ui';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class CupertinoInteractiveKeyboardPlatform extends PlatformInterface {
  /// Constructs a CupertinoInteractiveKeyboardPlatform.
  CupertinoInteractiveKeyboardPlatform() : super(token: _token);

  static final Object _token = Object();

  static CupertinoInteractiveKeyboardPlatform _instance =
      MethodChannelCupertinoInteractiveKeyboard();

  /// The default instance of [CupertinoInteractiveKeyboardPlatform] to use.
  ///
  /// Defaults to [MethodChannelCupertinoInteractiveKeyboard].
  static CupertinoInteractiveKeyboardPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [CupertinoInteractiveKeyboardPlatform] when
  /// they register themselves.
  static set instance(CupertinoInteractiveKeyboardPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool?> initialize({required bool firstTime}) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<void> setScrollableRect(int id, Rect rect) {
    throw UnimplementedError('setScrollableRect() has not been implemented.');
  }

  Future<void> removeScrollableRect(int id) {
    throw UnimplementedError(
      'removeScrollableRect() has not been implemented.',
    );
  }

  Future<void> setInputAccessoryHeight(int id, double height) {
    throw UnimplementedError(
      'setInputAccessoryHeight() has not been implemented.',
    );
  }

  Future<void> removeInputAccessoryHeight(int id) {
    throw UnimplementedError(
      'removeInputAccessoryHeight() has not been implemented.',
    );
  }

  Future<double?> createHostedAccessory(Map<String, Object?> config) {
    throw UnimplementedError(
      'createHostedAccessory() has not been implemented.',
    );
  }

  Future<void> updateHostedAccessory(Map<String, Object?> config) {
    throw UnimplementedError(
      'updateHostedAccessory() has not been implemented.',
    );
  }

  Future<void> setHostedAccessoryText(String text) {
    throw UnimplementedError(
      'setHostedAccessoryText() has not been implemented.',
    );
  }

  Future<void> removeHostedAccessory() {
    throw UnimplementedError(
      'removeHostedAccessory() has not been implemented.',
    );
  }

  Stream<Map<String, Object?>> get hostedAccessoryEvents =>
      const Stream.empty();
}
