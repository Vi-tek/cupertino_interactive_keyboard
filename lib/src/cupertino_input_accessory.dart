import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:cupertino_interactive_keyboard/src/current_route_aware.dart';
import 'package:cupertino_interactive_keyboard/src/height_observer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

var _nextViewId = 0;

class CupertinoInputAccessory extends StatelessWidget {
  const CupertinoInputAccessory({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return IOSCupertinoInputAccessory(child: child);
    } else {
      return child;
    }
  }
}

class IOSCupertinoInputAccessory extends StatefulWidget {
  const IOSCupertinoInputAccessory({super.key, required this.child});

  final Widget child;

  @override
  State<StatefulWidget> createState() => _IOSCupertinoInputAccessory();
}

class _IOSCupertinoInputAccessory extends State<IOSCupertinoInputAccessory>
    with CurrentRouteAware {
  final _viewId = _nextViewId++;
  double? _latestHeight;

  @override
  void initState() {
    super.initState();
    CupertinoInteractiveKeyboardPlatform.instance.keyboardTranslation
        .addListener(_onKeyboardTranslationChanged);
  }

  @override
  void dispose() {
    CupertinoInteractiveKeyboardPlatform.instance.keyboardTranslation
        .removeListener(_onKeyboardTranslationChanged);
    super.dispose();
    CupertinoInteractiveKeyboardPlatform.instance
        .removeInputAccessoryHeight(_viewId);
  }

  void _onKeyboardTranslationChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeRouteCurrentState() {
    super.didChangeRouteCurrentState();
    _reportHeight();
  }

  @override
  Widget build(BuildContext context) {
    // While the keyboard is dragged away the native side pushes how far the accessory has to be
    // moved to stay glued to the keyboard. The accessory is moved by a transform, so the widget
    // tree is not rebuilt and relayouted on every frame, which would drop frames and let the
    // accessory trail behind the keyboard.
    //
    // The transform is applied inside the height observer, because the render object of the
    // observer does not report the transform of its ancestors to the geometry of the tree.
    final translation =
        CupertinoInteractiveKeyboardPlatform.instance.keyboardTranslation.value;

    return HeightObserver(
      onChange: (height) {
        _latestHeight = height;
        _reportHeight();
      },
      child: Transform.translate(
        offset: Offset(0, translation),
        child: widget.child,
      ),
    );
  }

  void _reportHeight() {
    if (!isRouteCurrent) {
      CupertinoInteractiveKeyboardPlatform.instance
          .removeInputAccessoryHeight(_viewId);
    } else if (_latestHeight != null) {
      CupertinoInteractiveKeyboardPlatform.instance
          .setInputAccessoryHeight(_viewId, _latestHeight!);
    }
  }
}
