import 'dart:async';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:cupertino_interactive_keyboard/src/cupertino_hosted_input_accessory.dart';
import 'package:cupertino_interactive_keyboard/src/current_route_aware.dart';
import 'package:cupertino_interactive_keyboard/src/host_id.dart';
import 'package:cupertino_interactive_keyboard/src/rect_observer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Reserves the area a hosted keyboard surface draws in and owns its native
/// host.
///
/// The surface is a second Flutter engine's view inside a native container that
/// UIKit moves with the keyboard, so the scrollable content it draws stays
/// frame for frame with the keyboard. This widget only takes that area, reports
/// its rectangle to native (post-frame, logical pixels) and routes the
/// surface's calls to [controller]; it paints nothing, because the native
/// surface is drawn above it. [entrypoint] and [libraryURI] identify the Dart
/// function the surface engine runs.
///
/// The widget must be given the whole content area under the app bar: the
/// reported rectangle has to be full width and reach the Flutter view's bottom,
/// since native uses only its top and derives the rest from the view. The page
/// around it must not resize for the keyboard (`resizeToAvoidBottomInset:
/// false` and no inset-driven padding): the surface moves natively instead.
///
/// The surface is hidden while its route is not current, and it is the last
/// widget to create a host that wins: a newer one displaces it, and this widget
/// re-hosts when its route is current again. Its Dart state survives the
/// displacement, only the second engine is recreated.
///
/// On platforms other than iOS, or when the engine cannot be hosted (iOS below
/// 15), it renders [fallback] and calls no method channel.
class CupertinoHostedKeyboardSurface extends StatefulWidget {
  const CupertinoHostedKeyboardSurface({
    super.key,
    required this.entrypoint,
    required this.libraryURI,
    this.controller,
    this.hidden = false,
    this.fallback,
  });

  /// Dart entrypoint the surface engine runs, e.g. `surfaceMain`.
  final String entrypoint;

  /// Library URI that contains [entrypoint].
  final String libraryURI;

  /// The main isolate's half of the bridge; one is created internally when
  /// null, so pass one to receive calls.
  final CupertinoHostedInputAccessoryController? controller;

  /// Whether the surface is hidden.
  ///
  /// A hidden surface keeps its engine and widget state and drops its
  /// keyboard; this widget also hides it while its route is not current. The
  /// area stays reserved either way - unmount the widget to give it back.
  final bool hidden;

  /// What to render when the surface cannot be hosted.
  ///
  /// Defaults to an empty box. Shipping apps must pass a real fallback, since
  /// the hosted content simply does not exist when hosting is unavailable.
  final Widget? fallback;

  @override
  State<CupertinoHostedKeyboardSurface> createState() =>
      _CupertinoHostedKeyboardSurfaceState();
}

class _CupertinoHostedKeyboardSurfaceState
    extends State<CupertinoHostedKeyboardSurface> with CurrentRouteAware {
  late final CupertinoHostedInputAccessoryController _controller;
  StreamSubscription<Map<String, Object?>>? _events;

  /// The last rectangle the placeholder reported, in logical pixels.
  Rect? _rect;

  /// Whether native currently hosts a surface for this widget.
  bool _hosted = false;

  /// This widget's host id, so a `released` event only clears ownership when
  /// it names the host this widget created.
  int? _hostId;

  /// Whether hosting failed; the widget then stays on [fallback].
  bool _failed = false;

  /// Set while `createHostedAccessory` is in flight, so the rect observer and
  /// the route callbacks cannot create a second host.
  bool _creating = false;

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  bool get _shouldHide => widget.hidden || !isRouteCurrent;

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
  }

  @override
  void didUpdateWidget(CupertinoHostedKeyboardSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isIOS) {
      return;
    }
    if (widget.hidden != oldWidget.hidden) {
      _syncHost();
    }
    if (widget.entrypoint != oldWidget.entrypoint ||
        widget.libraryURI != oldWidget.libraryURI) {
      // The hosted app changed: the old engine is running the old entrypoint.
      if (_hosted) {
        CupertinoInteractiveKeyboardPlatform.instance
            .removeHostedAccessory(id: _hostId);
      }
      _hosted = false;
      _hostId = null;
      _failed = false;
      _syncHost();
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    // Only the widget that owns the host may tear it down: a released widget
    // was already displaced, and removing would kill the newer surface.
    if (_isIOS && _hosted) {
      CupertinoInteractiveKeyboardPlatform.instance
          .removeHostedAccessory(id: _hostId);
    }
    super.dispose();
  }

  @override
  void didChangeRouteCurrentState() {
    super.didChangeRouteCurrentState();
    _syncHost();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isIOS || _failed) {
      return widget.fallback ?? const SizedBox.shrink();
    }
    // Take the hosted area, so the rectangle the app declares is this widget's;
    // paint nothing, since the native surface above already draws it.
    return RectObserver(onChange: _handleRect, child: const SizedBox.expand());
  }

  void _handleRect(Rect rect) {
    if (!mounted || rect == _rect) {
      return;
    }
    _checkContract(rect);
    _rect = rect;
    if (_hosted) {
      CupertinoInteractiveKeyboardPlatform.instance
          .updateHostedAccessoryRect(rect);
    } else {
      _syncHost();
    }
  }

  /// Logs a violation of the surface contract: the reported area must be full
  /// width and reach the Flutter view's bottom, since native derives the
  /// container and the engine view height from its top only.
  void _checkContract(Rect rect) {
    final size = MediaQuery.maybeSizeOf(context);
    if (size == null) {
      return;
    }
    if (rect.width < size.width - 0.5 || rect.bottom < size.height - 0.5) {
      debugPrint(
        '[cik] CupertinoHostedKeyboardSurface needs a full-width area that '
        'reaches the bottom of the screen; got $rect in a $size view. The '
        'surface will use its top only.',
      );
    }
  }

  /// Brings native ownership in line with the widget's state: hosts the surface
  /// when it is current and visible, hides it otherwise.
  void _syncHost() {
    if (!_isIOS || !mounted) {
      return;
    }
    if (_hosted) {
      CupertinoInteractiveKeyboardPlatform.instance
          .updateHostedAccessoryHidden(_shouldHide);
    } else if (!_failed && isRouteCurrent && !widget.hidden && _rect != null) {
      _create();
    }
  }

  Future<void> _create() async {
    final rect = _rect;
    if (rect == null || _creating) {
      return;
    }
    _creating = true;
    final hidden = _shouldHide;
    final id = nextHostedThingId();
    double? height;
    try {
      height = await CupertinoInteractiveKeyboardPlatform.instance
          .createHostedAccessory(
        entrypoint: widget.entrypoint,
        libraryURI: widget.libraryURI,
        height: rect.height,
        hidden: hidden,
        rect: rect,
        id: id,
      );
    } catch (error) {
      debugPrint('[cik] surface hosting failed: $error');
      if (mounted) {
        setState(() => _failed = true);
      }
      return;
    } finally {
      _creating = false;
    }
    if (!mounted) {
      // The widget went away while the engine was starting: the surface it just
      // created has no owner any more, but a newer widget may own the plugin by
      // now, so only the host this widget created may be removed.
      if (height != null) {
        CupertinoInteractiveKeyboardPlatform.instance
            .removeHostedAccessory(id: id);
      }
      return;
    }
    if (height == null) {
      setState(() => _failed = true);
      return;
    }
    _hosted = true;
    _hostId = id;
    final latest = _rect;
    if (latest != null && latest != rect) {
      // The area changed while the engine was starting; native applied the
      // rectangle it was created with.
      CupertinoInteractiveKeyboardPlatform.instance
          .updateHostedAccessoryRect(latest);
    }
    if (hidden != _shouldHide) {
      // The route or the hidden flag changed while the engine was starting.
      _syncHost();
    }
  }

  void _handleEvent(Map<String, Object?> event) {
    if (!mounted) {
      return;
    }
    switch (event['type']) {
      case 'ready':
        _controller.onReady?.call();
        break;
      case 'invoke':
        _controller.onInvoke?.call(
          event['method'] as String? ?? '',
          event['arguments'],
        );
        break;
      case 'released':
        // A newer host displaced this one and its engine is gone: stop owning
        // it so dispose cannot tear the newer one down, and re-host when this
        // widget's route is current again. The id names the displaced host: a
        // surface that displaced someone else must not drop its own ownership.
        if (_hostId != null && event['id'] == _hostId) {
          _hostId = null;
          _hosted = false;
        }
        break;
    }
  }
}
