import 'dart:async';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:cupertino_interactive_keyboard/src/host_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_cupertino_interactive_keyboard.dart';

void main() {
  late MockCupertinoInteractiveKeyboard plugin;

  setUp(() {
    CupertinoInteractiveKeyboardPlatform.instance =
        plugin = MockCupertinoInteractiveKeyboard();
    // Hosting succeeds unless a test overrides it.
    plugin.createResultHeight = 96;
  });

  const entrypoint = 'surfaceMain';
  const libraryURI = 'package:example/chat_surface.dart';
  const fallbackText = 'fallback';

  Widget surface({
    bool hidden = false,
    Widget? fallback,
    CupertinoHostedInputAccessoryController? controller,
  }) {
    return CupertinoHostedKeyboardSurface(
      entrypoint: entrypoint,
      libraryURI: libraryURI,
      hidden: hidden,
      fallback: fallback,
      controller: controller,
    );
  }

  /// Hosts the surface in the app body, so it fills the [Scaffold] like the
  /// placeholder the app is meant to pass.
  Widget app({
    bool hidden = false,
    Widget? fallback,
    CupertinoHostedInputAccessoryController? controller,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: surface(
          hidden: hidden,
          fallback: fallback,
          controller: controller,
        ),
      ),
    );
  }

  /// Hosts the surface at a known, resizable rect.
  Widget sizedApp(double height) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, height: height, child: surface()),
        ),
      ),
    );
  }

  /// The route-aware app: a second route on top hides the surface.
  Widget routedApp(GlobalKey<NavigatorState> navigatorKey,
      {bool hidden = false}) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      routes: {
        '/': (context) => Scaffold(body: surface(hidden: hidden)),
        '/second': (context) => const SizedBox.shrink(),
      },
    );
  }

  testWidgets(
    'reports its rect and creates the hosted accessory once with that rect',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));
      final call = plugin.hostedAccessoryCreateCalls.single;
      expect(call['entrypoint'], entrypoint);
      expect(call['libraryURI'], libraryURI);
      expect(call['rect'], const Rect.fromLTWH(0, 0, 800, 600));
      expect(call['hidden'], false);
      expect(
        tester.getSize(find.byType(CupertinoHostedKeyboardSurface)),
        const Size(800, 600),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'reports a rect change with updateHostedAccessoryRect and does not create again',
    (tester) async {
      await tester.pumpWidget(sizedApp(300));
      await tester.pump();
      await tester.pump();

      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));
      expect(
        plugin.hostedAccessoryCreateCalls.single['rect'],
        const Rect.fromLTWH(0, 0, 400, 300),
      );

      await tester.pumpWidget(sizedApp(200));
      await tester.pump();
      await tester.pump();

      expect(plugin.hostedAccessoryRectUpdates, [
        const Rect.fromLTWH(0, 0, 400, 200),
      ]);
      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'routes ready and invoke events to the controller',
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

      await tester.pumpWidget(app(controller: controller));
      await tester.pump();

      plugin.emitHostedAccessoryEvent({'type': 'ready'});
      await tester.pump();
      expect(readyCalls, 1);

      plugin.emitHostedAccessoryEvent({
        'type': 'invoke',
        'method': 'textChanged',
        'arguments': {'text': 'hi'},
      });
      await tester.pump();
      expect(invokedMethod, 'textChanged');
      expect(invokedArguments, {'text': 'hi'});
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'forwards the hidden flag without recreating the surface',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(plugin.hostedAccessoryHiddenCalls, isEmpty);

      await tester.pumpWidget(app(hidden: true));
      await tester.pump();
      expect(plugin.hostedAccessoryHiddenCalls, [true]);

      await tester.pumpWidget(app());
      await tester.pump();
      expect(plugin.hostedAccessoryHiddenCalls, [true, false]);
      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'hides when its route is no longer current and shows it again on return',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(routedApp(navigatorKey));
      await tester.pump();

      expect(plugin.hostedAccessoryHiddenCalls, isEmpty);

      navigatorKey.currentState!.pushNamed('/second');
      await tester.pumpAndSettle();
      expect(plugin.hostedAccessoryHiddenCalls, [true]);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(plugin.hostedAccessoryHiddenCalls, [true, false]);
      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'stops owning the host when released, so its dispose does not remove it',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(routedApp(navigatorKey));
      await tester.pump();
      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));

      navigatorKey.currentState!.pushNamed('/second');
      await tester.pumpAndSettle();

      final hostId = plugin.hostedAccessoryCreateCalls.single['id'];
      plugin.emitHostedAccessoryEvent({'type': 'released', 'id': hostId});
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(plugin.removeHostedAccessoryCalls, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    're-hosts when its route is current again after a release',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(routedApp(navigatorKey));
      await tester.pump();
      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));

      navigatorKey.currentState!.pushNamed('/second');
      await tester.pumpAndSettle();

      final hostId = plugin.hostedAccessoryCreateCalls.single['id'];
      plugin.emitHostedAccessoryEvent({'type': 'released', 'id': hostId});
      await tester.pump();
      await tester.pump();

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(plugin.hostedAccessoryCreateCalls, hasLength(2));
      expect(
        plugin.hostedAccessoryCreateCalls.last['rect'],
        const Rect.fromLTWH(0, 0, 800, 600),
      );
      // The re-host gets its own id: the released id belonged to the old host.
      expect(
        plugin.hostedAccessoryCreateCalls.last['id'],
        isNot(plugin.hostedAccessoryCreateCalls.first['id']),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      expect(plugin.removeHostedAccessoryCalls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'keeps ownership when a released event names another host',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(routedApp(navigatorKey));
      await tester.pump();
      final hostId = plugin.hostedAccessoryCreateCalls.single['id'];

      plugin.emitHostedAccessoryEvent({
        'type': 'released',
        'id': (hostId! as int) + 1000,
      });
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(plugin.removeHostedAccessoryCalls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'renders the fallback when the host cannot be created',
    (tester) async {
      plugin.createResultHeight = null;

      await tester.pumpWidget(app(fallback: const Text(fallbackText)));
      await tester.pump();
      await tester.pump();

      expect(plugin.hostedAccessoryCreateCalls, hasLength(1));
      expect(find.text(fallbackText), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'renders the fallback and touches no channel on non-iOS platforms',
    (tester) async {
      await tester.pumpWidget(app(fallback: const Text(fallbackText)));
      await tester.pump();

      expect(find.text(fallbackText), findsOneWidget);
      expect(plugin.hostedAccessoryCreateCalls, isEmpty);
      expect(plugin.hostedAccessoryRectUpdates, isEmpty);
      expect(plugin.hostedAccessoryHiddenCalls, isEmpty);
      expect(plugin.hostedAccessoryInvokes, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(plugin.removeHostedAccessoryCalls, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'sends the rect contract and maps hostedAccessoryReleased to an event',
    (tester) async {
      const channel = MethodChannel('cupertino_interactive_keyboard');
      final implementation = MethodChannelCupertinoInteractiveKeyboard();
      final calls = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'createHostedAccessory'
            ? {'height': 666.0}
            : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const rect = Rect.fromLTWH(0, 100, 390, 600);
      expect(
        await implementation.createHostedAccessory(
          entrypoint: entrypoint,
          libraryURI: libraryURI,
          height: 600,
          rect: rect,
        ),
        666,
      );
      await implementation.updateHostedAccessoryRect(rect);

      expect(calls.map((call) => call.method), [
        'createHostedAccessory',
        'updateHostedAccessoryRect',
      ]);
      expect(calls[0].arguments, {
        'entrypoint': entrypoint,
        'libraryURI': libraryURI,
        'height': 600.0,
        'hidden': false,
        'rect': {'x': 0.0, 'y': 100.0, 'width': 390.0, 'height': 600.0},
      });
      expect(calls[1].arguments, {
        'rect': {'x': 0.0, 'y': 100.0, 'width': 390.0, 'height': 600.0},
      });

      final events = <Map<String, Object?>>[];
      final subscription =
          implementation.hostedAccessoryEvents.listen(events.add);
      addTearDown(subscription.cancel);
      await messenger.handlePlatformMessage(
        'cupertino_interactive_keyboard',
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('hostedAccessoryReleased')),
        (_) {},
      );
      await tester.pump();
      expect(events, [
        {'type': 'released', 'id': null},
      ]);
    },
  );

  testWidgets(
    'a widget that unmounts while its engine is starting removes only its own host',
    (tester) async {
      final create = Completer<double?>();
      plugin.createHostedAccessoryFuture = create.future;

      await tester.pumpWidget(app());
      await tester.pump();
      final hostId = plugin.hostedAccessoryCreateCalls.single['id'];

      await tester.pumpWidget(const SizedBox.shrink());
      create.complete(96);
      await tester.pump();

      expect(plugin.removeHostedAccessoryCalls, 1);
      expect(plugin.removeHostedAccessoryIds, [hostId]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  test('host ids are shared by the bar and the surface', () {
    final first = nextHostedThingId();
    final second = nextHostedThingId();
    expect(second, greaterThan(first));
  });
}
