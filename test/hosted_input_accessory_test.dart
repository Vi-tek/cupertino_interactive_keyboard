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
  const entrypoint = 'customAccessoryMain';
  const libraryURI = 'package:app/accessory.dart';

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

  Widget accessory({
    double height = 48,
    CupertinoHostedInputAccessoryController? controller,
  }) {
    return host(
      CupertinoKeyboardAccessory(
        entrypoint: entrypoint,
        libraryURI: libraryURI,
        height: height,
        controller: controller,
      ),
    );
  }

  testWidgets(
    'creates with the entrypoint, library URI and height, and reserves the placeholder height until a height event arrives',
    (tester) async {
      await tester.pumpWidget(accessory());
      await tester.pump();

      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));
      expect(plugin.hostedAccessoryCreateCalls.single, {
        'entrypoint': entrypoint,
        'libraryURI': libraryURI,
        'height': 48.0,
      });

      expect(
        tester.getSize(find.byType(CupertinoKeyboardAccessory)).height,
        48 + bottomPadding,
      );

      await emit(tester, {'type': 'height', 'height': 96.0});

      expect(
        tester.getSize(find.byType(CupertinoKeyboardAccessory)).height,
        96,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'reserves the height returned by create',
    (tester) async {
      plugin.createResultHeight = 97;

      await tester.pumpWidget(accessory());
      await tester.pump();

      expect(
        tester.getSize(find.byType(CupertinoKeyboardAccessory)).height,
        97,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'routes ready and invoke to the controller and forwards controller calls',
    (tester) async {
      final controller = CupertinoHostedInputAccessoryController();
      var readyCalls = 0;
      String? invokedMethod;
      Object? invokedArguments;
      controller.onReady = () => readyCalls++;
      controller.onInvoke = (method, arguments) {
        invokedMethod = method;
        invokedArguments = arguments;
      };

      await tester.pumpWidget(accessory(controller: controller));
      await tester.pump();

      expect(readyCalls, 0);

      await emit(tester, {'type': 'ready'});
      expect(readyCalls, 1);

      await emit(tester, {
        'type': 'invoke',
        'method': 'theme',
        'arguments': {'surface': 1},
      });
      expect(invokedMethod, 'theme');
      expect(invokedArguments, {'surface': 1});

      controller.invoke('setText', {'text': ''});
      controller.invoke('ping');
      await tester.pump();

      expect(plugin.hostedAccessoryInvokes, [
        {
          'method': 'setText',
          'arguments': {'text': ''},
        },
        {'method': 'ping', 'arguments': null},
      ]);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(plugin.removeHostedAccessoryCalls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'updates the native height and reserves the new requested height until it reports back',
    (tester) async {
      await tester.pumpWidget(accessory());
      await tester.pump();

      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));

      await tester.pumpWidget(accessory(height: 72));
      await tester.pump();

      expect(plugin.hostedAccessoryHeights, [72.0]);
      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));
      expect(
        tester.getSize(find.byType(CupertinoKeyboardAccessory)).height,
        72 + bottomPadding,
      );

      await emit(tester, {'type': 'height', 'height': 106.0});

      expect(
        tester.getSize(find.byType(CupertinoKeyboardAccessory)).height,
        106,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'renders nothing and calls nothing on non-iOS platforms',
    (tester) async {
      await tester.pumpWidget(accessory());
      await tester.pump();

      expect(
        tester.getSize(find.byType(CupertinoKeyboardAccessory)).height,
        0,
      );
      expect(plugin.hostedAccessoryCreateCalls, isEmpty);
      expect(plugin.hostedAccessoryHeights, isEmpty);
      expect(plugin.hostedAccessoryInvokes, isEmpty);

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
        await implementation.createHostedAccessory(
          entrypoint: entrypoint,
          libraryURI: libraryURI,
          height: 56,
        ),
        96,
      );
      await implementation.updateHostedAccessoryHeight(64);
      await implementation.invokeHostedAccessory('theme', {'surface': 1});
      await implementation.invokeHostedAccessory('ping', null);
      await implementation.removeHostedAccessory();

      expect(calls.map((call) => call.method), [
        'createHostedAccessory',
        'updateHostedAccessoryHeight',
        'invokeHostedAccessory',
        'invokeHostedAccessory',
        'removeHostedAccessory',
      ]);
      expect(calls[0].arguments, {
        'entrypoint': entrypoint,
        'libraryURI': libraryURI,
        'height': 56.0,
      });
      expect(calls[1].arguments, {'height': 64.0});
      expect(calls[2].arguments, {
        'method': 'theme',
        'arguments': {'surface': 1},
      });
      expect(calls[3].arguments, {'method': 'ping', 'arguments': null});
      expect(calls[4].arguments, isNull);
    },
  );

  testWidgets('maps the native calls to hosted accessory events',
      (tester) async {
    final implementation = MethodChannelCupertinoInteractiveKeyboard();
    final events = <Map<String, Object?>>[];
    final subscription =
        implementation.hostedAccessoryEvents.listen(events.add);
    addTearDown(subscription.cancel);

    Future<void> nativeCall(String method, Object? arguments) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'cupertino_interactive_keyboard',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
    }

    await nativeCall('hostedAccessoryHeight', {'height': 96.0});
    await nativeCall('hostedAccessoryReady', null);
    await nativeCall('hostedAccessoryInvoke', {
      'method': 'textChanged',
      'arguments': {'text': 'hi'},
    });
    await nativeCall('hostedAccessoryInvoke', {
      'method': 'ping',
      'arguments': null,
    });

    expect(events, [
      {'type': 'height', 'height': 96.0},
      {'type': 'ready'},
      {
        'type': 'invoke',
        'method': 'textChanged',
        'arguments': {'text': 'hi'},
      },
      {'type': 'invoke', 'method': 'ping', 'arguments': null},
    ]);
  });
}
