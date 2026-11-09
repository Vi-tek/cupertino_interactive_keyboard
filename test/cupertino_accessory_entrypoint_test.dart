import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('cupertino_interactive_keyboard/accessory');
  late TestDefaultBinaryMessenger messenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// Delivers a native -> accessory call and pumps the resulting frame.
  Future<void> push(
    WidgetTester tester,
    String method,
    Map<String, Object?> arguments,
  ) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets('reports ready and renders the pushed config', (tester) async {
    await tester.pumpWidget(const CupertinoAccessoryApp());
    await tester.pump();

    expect(calls.where((call) => call.method == 'ready'), hasLength(1));

    await push(tester, 'config', {
      'placeholder': 'Say something...',
      'text': 'hello',
      'icon': 'paperplane.fill',
      'backgroundColor': 0xFF102030,
      'textColor': 0xFFFFFFFF,
      'placeholderColor': 0xFF778899,
      'iconColor': 0xFFAABBCC,
      'height': 56,
    });

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'hello');
    expect(field.decoration!.hintText, 'Say something...');
    expect(field.style!.color, const Color(0xFFFFFFFF));
    expect(field.decoration!.hintStyle!.color, const Color(0xFF778899));
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFF102030),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.send);
    expect(
        tester.widget<Icon>(find.byType(Icon)).color, const Color(0xFFAABBCC));
  });

  testWidgets('emits textChanged while typing and send on press',
      (tester) async {
    await tester.pumpWidget(const CupertinoAccessoryApp());
    await push(tester, 'config', {'placeholder': 'Say something...'});
    calls.clear();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    expect(calls.last.method, 'textChanged');
    expect(calls.last.arguments, {'text': 'hello'});

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(calls.last.method, 'send');
    expect(calls.last.arguments, {'text': 'hello'});
  });

  testWidgets('setText updates the field without echoing textChanged', (
    tester,
  ) async {
    await tester.pumpWidget(const CupertinoAccessoryApp());
    await push(tester, 'config', {'placeholder': 'Say something...'});
    calls.clear();

    await push(tester, 'setText', {'text': 'from native'});

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'from native',
    );
    expect(calls, isEmpty);

    // A later config push carries the stale create-time text; it must not
    // overwrite what the user (or setText) put in the field.
    await push(tester, 'config', {
      'placeholder': 'Say something...',
      'text': 'stale',
    });

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'from native',
    );
  });
}
