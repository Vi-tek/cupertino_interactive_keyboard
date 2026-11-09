import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_cupertino_interactive_keyboard.dart';

void main() {
  late MockCupertinoInteractiveKeyboard plugin;

  setUp(() {
    CupertinoInteractiveKeyboardPlatform.instance =
        plugin = MockCupertinoInteractiveKeyboard();
  });

  const bottomPadding = 34.0;

  /// Emits a native event and pumps the frame its listener schedules.
  Future<void> emit(WidgetTester tester, Map<String, Object?> event) async {
    plugin.emitHostedAccessoryEvent(event);
    await tester.pump(); // delivers the stream event
    await tester.pump(); // builds the state it changed
  }

  /// Hosts [child] in a [Column] so it can size itself, with a bottom safe
  /// area the real device would provide.
  Widget host(Widget child) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(bottom: bottomPadding),
          ),
          child: Column(children: [child]),
        ),
      ),
    );
  }

  testWidgets(
    'pushes its full config on create and reserves the placeholder height until a height event arrives',
    (tester) async {
      await tester.pumpWidget(
        host(
          const CupertinoHostedInputAccessory(
            placeholder: 'Comment...',
            icon: 'arrow.up.circle.fill',
            height: 48,
            accessoryEntrypoint: 'customAccessoryMain',
            accessoryLibraryURI: 'package:app/accessory.dart',
          ),
        ),
      );
      await tester.pump();

      expect(plugin.hostedAccessoryCreateConfigs, hasLength(1));
      final config = plugin.hostedAccessoryCreateConfigs.single;
      expect(config['placeholder'], 'Comment...');
      expect(config['icon'], 'arrow.up.circle.fill');
      expect(config['text'], '');
      expect(config['height'], 48);
      expect(config['accessoryEntrypoint'], 'customAccessoryMain');
      expect(config['accessoryLibraryURI'], 'package:app/accessory.dart');

      expect(
        tester.getSize(find.byType(CupertinoHostedInputAccessory)).height,
        48 + bottomPadding,
      );

      await emit(tester, {'type': 'height', 'height': 96.0});

      expect(
        tester.getSize(find.byType(CupertinoHostedInputAccessory)).height,
        96,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'pushes a config update when its configuration changes, without the text or entrypoint',
    (tester) async {
      Widget accessory(String placeholder) => host(
            CupertinoHostedInputAccessory(placeholder: placeholder),
          );

      await tester.pumpWidget(accessory('Comment...'));
      await tester.pump();

      expect(plugin.hostedAccessoryUpdateConfigs, isEmpty);

      await tester.pumpWidget(accessory('Reply...'));
      await tester.pump();

      expect(plugin.hostedAccessoryUpdateConfigs, hasLength(1));
      final update = plugin.hostedAccessoryUpdateConfigs.single;
      expect(update['placeholder'], 'Reply...');
      // Re-sending the text would wipe what the user typed in the bar.
      expect(update.containsKey('text'), isFalse);
      expect(update.containsKey('accessoryEntrypoint'), isFalse);
      expect(update.containsKey('accessoryLibraryURI'), isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'reports text changes, send, and controller writes to the hosted bar',
    (tester) async {
      final controller = CupertinoHostedInputAccessoryController();
      String? changed;
      String? sent;

      await tester.pumpWidget(
        host(
          CupertinoHostedInputAccessory(
            placeholder: 'Comment...',
            controller: controller,
            onChanged: (text) => changed = text,
            onSend: (text) => sent = text,
          ),
        ),
      );
      await tester.pump();

      await emit(tester, {'type': 'textChanged', 'text': 'hello'});

      expect(changed, 'hello');
      expect(controller.text, 'hello');
      // Echoing the text back from Dart would fight the bar's field.
      expect(plugin.hostedAccessoryTexts, isEmpty);

      await emit(tester, {'type': 'send', 'text': 'hello'});

      expect(sent, 'hello');

      controller.clear();

      expect(controller.text, '');
      expect(plugin.hostedAccessoryTexts, ['']);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(plugin.removeHostedAccessoryCalls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'renders nothing and calls nothing on non-iOS platforms',
    (tester) async {
      await tester.pumpWidget(
        host(
          const CupertinoHostedInputAccessory(placeholder: 'Comment...'),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byType(CupertinoHostedInputAccessory)).height,
        0,
      );
      expect(plugin.hostedAccessoryCreateConfigs, isEmpty);
      expect(plugin.hostedAccessoryUpdateConfigs, isEmpty);
      expect(plugin.hostedAccessoryTexts, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(plugin.removeHostedAccessoryCalls, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'sends the channel contract payloads and unwraps the height',
    (tester) async {
      const channel = MethodChannel('cupertino_interactive_keyboard');
      final implementation = MethodChannelCupertinoInteractiveKeyboard();
      final calls = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'createHostedAccessory' ? {'height': 96.0} : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      expect(
        await implementation.createHostedAccessory({'height': 56.0}),
        96,
      );
      await implementation.updateHostedAccessory({'placeholder': 'y'});
      await implementation.setHostedAccessoryText('hi');
      await implementation.removeHostedAccessory();

      expect(calls.map((call) => call.method), [
        'createHostedAccessory',
        'updateHostedAccessory',
        'setHostedAccessoryText',
        'removeHostedAccessory',
      ]);
      expect(calls[0].arguments, {'height': 56.0});
      expect(calls[2].arguments, {'text': 'hi'});
      expect(calls[3].arguments, isNull);
    },
  );

  testWidgets('maps the native calls to hosted accessory events',
      (tester) async {
    final implementation = MethodChannelCupertinoInteractiveKeyboard();
    final events = <Map<String, Object?>>[];
    final subscription =
        implementation.hostedAccessoryEvents.listen(events.add);
    addTearDown(subscription.cancel);

    Future<void> nativeCall(
      String method,
      Map<String, Object?> arguments,
    ) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'cupertino_interactive_keyboard',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
    }

    await nativeCall('hostedAccessoryHeight', {'height': 96.0});
    await nativeCall('hostedAccessoryTextChanged', {'text': 'hi'});
    await nativeCall('hostedAccessorySend', {'text': 'hi'});

    expect(events, [
      {'type': 'height', 'height': 96.0},
      {'type': 'textChanged', 'text': 'hi'},
      {'type': 'send', 'text': 'hi'},
    ]);
  });
}
