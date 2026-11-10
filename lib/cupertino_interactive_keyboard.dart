import 'package:cupertino_interactive_keyboard/src/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

export 'cupertino_accessory.dart';
export 'src/cupertino_hosted_input_accessory.dart';
export 'src/cupertino_input_accessory.dart';
export 'src/cupertino_interactive_keyboard.dart';

/// Whether the keyboard is being dragged down right now.
///
/// True from the moment the interactive dismissal gesture starts moving the keyboard until the
/// finger is released, before the keyboard animates back or away. Listen to it to react to the
/// gesture (an overlay, a scroll indicator, a paused animation), or read its
/// [ValueListenable.value] for the current state.
///
/// It is a package-level value, not a widget: it is the same everywhere, even outside the widget
/// tree. iOS only - it stays false on platforms without the interactive keyboard.
ValueListenable<bool> get isKeyboardDragging =>
    CupertinoInteractiveKeyboardPlatform.instance.isKeyboardDragging;

/// Turns the plugin's native DEBUG trace on or off for this run.
///
/// While it is on, every keyboard event, inset write and bar layout change is printed to the Dart
/// console (`flutter run` shows them), which is how a device-side pacing problem gets diagnosed.
/// It does nothing in release builds, and it has a per-frame cost - turn it off again once the
/// gesture you were investigating is captured.
///
/// On iOS it also prints the Dart half of the pacing probe: one line per metrics push with a push
/// counter, wall-clock milliseconds, the scheduler phase and the `viewInsets` the framework
/// actually received. The native lines come from the plugin's own trace, so a write and the frame
/// that consumed it can be matched in the same console.
Future<void> setKeyboardTraceEnabled(bool enabled) async {
  await CupertinoInteractiveKeyboardPlatform.instance.setTraceEnabled(enabled);
  _metricsTrace.setEnabled(enabled);
}

/// The Dart half of the pacing probe; inert until [setKeyboardTraceEnabled] turns it on.
final _MetricsTrace _metricsTrace = _MetricsTrace();

class _MetricsTrace with WidgetsBindingObserver {
  bool _enabled = false;
  int _pushed = 0;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    if (enabled) {
      WidgetsBinding.instance.addObserver(this);
    } else {
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  void didChangeMetrics() {
    final binding = WidgetsBinding.instance;
    final views = binding.platformDispatcher.views;
    if (views.isEmpty) {
      return;
    }
    final view = views.first;
    final insets = view.viewInsets.bottom / view.devicePixelRatio;
    debugPrint(
      '[CIKTrace] metrics n=${++_pushed} '
      'ms=${DateTime.now().millisecondsSinceEpoch} '
      'phase=${binding.schedulerPhase} '
      'insets=${insets.toStringAsFixed(2)}',
    );
  }
}
