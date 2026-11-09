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

  Future<void> push(
    WidgetTester tester,
    String method,
    Map<String, Object?> arguments,
  ) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets('hosts a custom accessory UI and bridges config, text and callbacks',
      (tester) async {
    late CupertinoAccessoryController accessory;

    await tester.pumpWidget(
      CupertinoAccessoryHost(
        builder: (context, controller) {
          accessory = controller;
          return Column(
            children: [
              ValueListenableBuilder<CupertinoAccessoryConfig>(
                valueListenable: controller.config,
                builder: (context, config, _) => Text(
                  'hint:${config.placeholder} bg:${config.backgroundColor}',
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: controller.text,
                builder: (context, text, _) => Text('text:$text'),
              ),
            ],
          );
        },
      ),
    );
    await tester.pump();

    expect(calls.where((call) => call.method == 'ready'), hasLength(1));

    await push(tester, 'config', {
      'placeholder': 'Say something...',
      'text': 'hello',
      'backgroundColor': 0xFF102030,
    });

    expect(find.text('hint:Say something... bg:${const Color(0xFF102030)}'),
        findsOneWidget);
    expect(find.text('text:hello'), findsOneWidget);

    await push(tester, 'setText', {'text': 'from native'});
    expect(find.text('text:from native'), findsOneWidget);

    calls.clear();
    accessory.textChanged('typed');
    accessory.send('typed');
    expect(
      calls.map((call) => call.method).toList(),
      ['textChanged', 'send'],
    );
    expect(calls.first.arguments, {'text': 'typed'});

    // A later config push carries the stale create-time text; it must not
    // overwrite what the user typed.
    await push(tester, 'config', {'placeholder': 'Say something...', 'text': 'stale'});
    expect(find.text('text:from native'), findsOneWidget);
  });
}
