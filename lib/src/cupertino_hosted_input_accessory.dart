import 'dart:async';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Holds the text of a [CupertinoHostedInputAccessory] and forwards explicit
/// writes to the hosted Flutter bar.
class CupertinoHostedInputAccessoryController {
  String _text = '';

  /// The last text known to Dart: typed in the bar, or written through [text].
  String get text => _text;

  /// Replaces the text of the bar's field.
  set text(String value) {
    _text = value;
    CupertinoInteractiveKeyboardPlatform.instance.setHostedAccessoryText(value);
  }

  /// Clears the bar's field.
  void clear() => text = '';
}

/// Reserves the height of the hosted Flutter input accessory bar and configures
/// it.
///
/// The bar itself is a second Flutter engine's view inside a native container
/// owned by the plugin; this widget only keeps the Flutter layout clear of it
/// and pushes its configuration. On platforms other than iOS it renders nothing
/// and calls nothing.
class CupertinoHostedInputAccessory extends StatefulWidget {
  const CupertinoHostedInputAccessory({
    super.key,
    required this.placeholder,
    this.controller,
    this.initialText = '',
    this.onChanged,
    this.onSend,
    this.icon = 'paperplane.fill',
    this.backgroundColor,
    this.textColor,
    this.placeholderColor,
    this.iconColor,
    this.height = 56,
    this.accessoryEntrypoint,
    this.accessoryLibraryURI,
  });

  /// Text shown by the bar's field while it is empty.
  final String placeholder;

  /// Holds the field's text; one is created internally when null.
  final CupertinoHostedInputAccessoryController? controller;

  /// The field's text when the bar is created.
  final String initialText;

  /// Called with the field's text whenever it changes in the bar.
  final ValueChanged<String>? onChanged;

  /// Called with the field's text when the send button is tapped.
  final ValueChanged<String>? onSend;

  /// Icon name for the send button; `paperplane.fill` maps to
  /// [Icons.send] in the bar.
  final String icon;

  final Color? backgroundColor;
  final Color? textColor;
  final Color? placeholderColor;
  final Color? iconColor;

  /// The bar's height without the bottom safe area.
  final double height;

  /// Dart entrypoint run by the accessory engine; the plugin's composer is
  /// used when null.
  final String? accessoryEntrypoint;

  /// Library URI of [accessoryEntrypoint]; the plugin's entrypoint library is
  /// used when null.
  final String? accessoryLibraryURI;

  @override
  State<CupertinoHostedInputAccessory> createState() =>
      _CupertinoHostedInputAccessoryState();
}

class _CupertinoHostedInputAccessoryState
    extends State<CupertinoHostedInputAccessory> {
  late final CupertinoHostedInputAccessoryController _controller;
  late Map<String, Object?> _pushedConfig;
  StreamSubscription<Map<String, Object?>>? _events;
  double? _height;

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? CupertinoHostedInputAccessoryController();
    _controller._text = widget.initialText;
    if (!_isIOS) {
      return;
    }
    _pushedConfig = _updateConfig();
    _events = CupertinoInteractiveKeyboardPlatform
        .instance.hostedAccessoryEvents
        .listen(_handleEvent);
    _create();
  }

  @override
  void didUpdateWidget(CupertinoHostedInputAccessory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isIOS) {
      return;
    }
    final config = _updateConfig();
    if (mapEquals(config, _pushedConfig)) {
      return;
    }
    _pushedConfig = config;
    CupertinoInteractiveKeyboardPlatform.instance.updateHostedAccessory(config);
  }

  @override
  void dispose() {
    _events?.cancel();
    if (_isIOS) {
      CupertinoInteractiveKeyboardPlatform.instance.removeHostedAccessory();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isIOS) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: _height ?? (widget.height + MediaQuery.paddingOf(context).bottom),
    );
  }

  /// The full map sent on create: the only one that carries the text and the
  /// accessory entrypoint.
  Map<String, Object?> _config() => {
        'placeholder': widget.placeholder,
        'text': widget.initialText,
        'icon': widget.icon,
        'backgroundColor': widget.backgroundColor?.toARGB32(),
        'textColor': widget.textColor?.toARGB32(),
        'placeholderColor': widget.placeholderColor?.toARGB32(),
        'iconColor': widget.iconColor?.toARGB32(),
        'height': widget.height,
        'accessoryEntrypoint': widget.accessoryEntrypoint,
        'accessoryLibraryURI': widget.accessoryLibraryURI,
      };

  /// Re-sending the text would wipe what the user typed in the bar, and the
  /// entrypoint only matters when the bar is created.
  Map<String, Object?> _updateConfig() => _config()
    ..remove('text')
    ..remove('accessoryEntrypoint')
    ..remove('accessoryLibraryURI');

  Future<void> _create() async {
    final height = await CupertinoInteractiveKeyboardPlatform.instance
        .createHostedAccessory(_config());
    if (!mounted || height == null) {
      return;
    }
    setState(() => _height = height);
  }

  void _handleEvent(Map<String, Object?> event) {
    if (!mounted) {
      return;
    }
    switch (event['type']) {
      case 'height':
        final height = (event['height'] as num?)?.toDouble();
        if (height != null) {
          setState(() => _height = height);
        }
        break;
      case 'textChanged':
        final text = event['text'] as String? ?? '';
        _controller._text = text;
        widget.onChanged?.call(text);
        break;
      case 'send':
        widget.onSend?.call(event['text'] as String? ?? '');
        break;
    }
  }
}
