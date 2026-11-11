import 'dart:ui';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:flutter/foundation.dart';
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

  final ValueNotifier<bool> _isKeyboardDragging = ValueNotifier(false);

  /// Whether the interactive keyboard is being dragged down right now.
  ///
  /// True from the moment the drag starts moving the keyboard until the finger is released,
  /// before the keyboard animates back or away.
  ValueListenable<bool> get isKeyboardDragging => _isKeyboardDragging;

  /// The writable side of [isKeyboardDragging], for implementations that receive the state
  /// natively.
  @protected
  ValueNotifier<bool> get keyboardDraggingState => _isKeyboardDragging;

  Future<bool?> initialize({required bool firstTime}) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Enables or disables the native DEBUG trace (no-op in release builds).
  Future<void> setTraceEnabled(bool enabled) {
    throw UnimplementedError('setTraceEnabled() has not been implemented.');
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

  /// Creates the hosted accessory running [entrypoint] from [libraryURI].
  ///
  /// [hidden] creates the bar without showing it, so an app that starts with
  /// the bar off screen does not flash it. [rect], when given, hosts a keyboard
  /// surface (a full-size second engine) instead of a bar: it is the surface's
  /// rectangle in logical pixels, which the plugin uses as its top and derives
  /// the rest from the Flutter view. [id] identifies the caller's host, so the
  /// released event can name the host it displaced. Returns the total bar
  /// height, including the bottom safe area, or null on platforms that cannot
  /// host one.
  Future<double?> createHostedAccessory({
    required String entrypoint,
    required String libraryURI,
    required double height,
    bool hidden = false,
    Rect? rect,
    int? id,
  }) {
    throw UnimplementedError(
      'createHostedAccessory() has not been implemented.',
    );
  }

  /// Shows or hides the hosted accessory bar without tearing its engine down.
  ///
  /// A hidden bar keeps its isolate and widget state; it is only skipped when
  /// drawing and hit-testing, so toggling it is cheap.
  Future<void> updateHostedAccessoryHidden(bool hidden) {
    throw UnimplementedError(
      'updateHostedAccessoryHidden() has not been implemented.',
    );
  }

  /// Changes the requested bar height, without the bottom safe area.
  Future<void> updateHostedAccessoryHeight(double height) {
    throw UnimplementedError(
      'updateHostedAccessoryHeight() has not been implemented.',
    );
  }

  /// Re-reports the hosted surface's rectangle, in logical pixels.
  ///
  /// Called when the surface's size or position changes without a drag: a
  /// rotation, a split view resize or an app bar change. A hosted bar ignores
  /// it.
  Future<void> updateHostedAccessoryRect(Rect rect) {
    throw UnimplementedError(
      'updateHostedAccessoryRect() has not been implemented.',
    );
  }

  /// Invokes [method] with [arguments] in the accessory isolate.
  Future<void> invokeHostedAccessory(String method, Object? arguments) {
    throw UnimplementedError(
      'invokeHostedAccessory() has not been implemented.',
    );
  }

  /// Removes the hosted accessory and destroys its engine.
  ///
  /// [id] names the host the caller owns: when it does not match the host that is alive, the
  /// call is ignored, so a widget that unmounts while its engine was starting cannot tear down a
  /// newer host.
  Future<void> removeHostedAccessory({int? id}) {
    throw UnimplementedError(
      'removeHostedAccessory({int? id}) has not been implemented.',
    );
  }

  Stream<Map<String, Object?>> get hostedAccessoryEvents =>
      const Stream.empty();
}
