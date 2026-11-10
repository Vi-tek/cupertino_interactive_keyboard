import 'dart:math';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:cupertino_interactive_keyboard/src/interactive_keyboard_scroll_physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'mock_cupertino_interactive_keyboard.dart';

void main() {
  var plugin = MockCupertinoInteractiveKeyboard();

  setUp(() {
    CupertinoInteractiveKeyboardPlatform.instance =
        plugin = MockCupertinoInteractiveKeyboard();
  });

  testWidgets(
    'removes scrollable rects and input accessory heights on route change',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          routes: {
            '/': (context) => const CupertinoInteractiveKeyboard(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CupertinoInputAccessory(
                        child: SizedBox(height: 50),
                      ),
                    ],
                  ),
                ),
            '/second': (context) => const SizedBox.shrink(),
          },
        ),
      );

      expect(plugin.scrollableRects.length, 1);
      expect(
        plugin.scrollableRects.values.first,
        Offset.zero & const Size(800, 600),
      );
      expect(plugin.inputAccessoryHeights.length, 1);
      expect(plugin.inputAccessoryHeights.values.first, 50);

      navigatorKey.currentState?.pushNamed('/second');
      await tester.pumpAndSettle();

      expect(plugin.scrollableRects.length, 0);
      expect(plugin.inputAccessoryHeights.length, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'removes scrollable rects and input accessory heights on route change with GoRouter (TickerMode aware)',
    (tester) async {
      // StatefulShellRoute uses TickerMode to hide inactive branches.
      // This test ensures that the CurrentRouteAware mixin works correctly
      // with TickerMode changes.
      final router = GoRouter(
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) => navigationShell,
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (context, state) =>
                        const CupertinoInteractiveKeyboard(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CupertinoInputAccessory(
                            child: SizedBox(height: 50),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/second',
                    builder: (context, state) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );

      expect(plugin.scrollableRects.length, 1);
      expect(
        plugin.scrollableRects.values.first,
        Offset.zero & const Size(800, 600),
      );
      expect(plugin.inputAccessoryHeights.length, 1);
      expect(plugin.inputAccessoryHeights.values.first, 50);

      router.go('/second');
      await tester.pumpAndSettle();

      expect(plugin.scrollableRects.length, 0);
      expect(plugin.inputAccessoryHeights.length, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'scrolls correctly with InteractiveKeyboardScrollPhysics in reverse',
    (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      var keyboardHeight = 300.0;
      late StateSetter setState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerMove: (details) {
                setState(() {
                  keyboardHeight =
                      300 - max(0, (details.position.dy - 300).abs());
                });
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      physics: const InteractiveKeyboardScrollPhysics(),
                      reverse: true,
                      itemBuilder: (_, index) => ListTile(
                        title: Text("$index"),
                      ),
                    ),
                  ),
                  StatefulBuilder(
                    builder: (_, setter) {
                      setState = setter;
                      return SizedBox(height: keyboardHeight);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(const Offset(400, 200));
      await gesture.moveBy(const Offset(0, 100));
      await tester.pumpAndSettle();

      await gesture.moveBy(const Offset(0, 50));
      await tester.pumpAndSettle();

      expect(scrollController.offset, 100);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'dynamically updates input accessory height when child resizes',
    (tester) async {
      double height = 44.0;
      late StateSetter stateSetter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                stateSetter = setState;
                return CupertinoInputAccessory(
                  child: SizedBox(height: height),
                );
              },
            ),
          ),
        ),
      );

      expect(plugin.inputAccessoryHeights.length, 1);
      expect(plugin.inputAccessoryHeights.values.first, 44.0);

      stateSetter(() {
        height = 60.0;
      });
      await tester.pumpAndSettle();

      expect(plugin.inputAccessoryHeights.length, 1);
      expect(plugin.inputAccessoryHeights.values.first, 60.0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'supports multiple accessories and removes height on unmount',
    (tester) async {
      bool showSecond = true;
      late StateSetter stateSetter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                stateSetter = setState;
                return Column(
                  children: [
                    const CupertinoInputAccessory(
                      child: SizedBox(height: 48),
                    ),
                    if (showSecond)
                      const CupertinoInputAccessory(
                        child: SizedBox(height: 72),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      expect(plugin.inputAccessoryHeights.length, 2);
      expect(plugin.inputAccessoryHeights.values.toSet(), {48.0, 72.0});

      stateSetter(() {
        showSecond = false;
      });
      await tester.pumpAndSettle();

      expect(plugin.inputAccessoryHeights.length, 1);
      expect(plugin.inputAccessoryHeights.values.first, 48.0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  test('updates the public drag state from the native channel call', () async {
    final implementation = MethodChannelCupertinoInteractiveKeyboard();
    final changes = <bool>[];
    implementation.isKeyboardDragging.addListener(
      () => changes.add(implementation.isKeyboardDragging.value),
    );

    Future<void> nativeCall(String method, Object? arguments) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'cupertino_interactive_keyboard',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
    }

    await nativeCall('keyboardDragging', {'dragging': true});
    expect(implementation.isKeyboardDragging.value, isTrue);
    await nativeCall('keyboardDragging', {'dragging': false});
    expect(implementation.isKeyboardDragging.value, isFalse);
    expect(changes, [true, false]);
  });

  test('exposes the drag state through the public getter', () {
    expect(isKeyboardDragging.value, isFalse);
    final changes = <bool>[];
    isKeyboardDragging.addListener(() => changes.add(isKeyboardDragging.value));

    plugin.emitKeyboardDragging(true);
    expect(isKeyboardDragging.value, isTrue);
    plugin.emitKeyboardDragging(false);
    expect(isKeyboardDragging.value, isFalse);
    expect(changes, [true, false]);
  });

  testWidgets(
    'does not register platform height or scrollable rect on non-iOS platforms',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CupertinoInteractiveKeyboard(
              child: CupertinoInputAccessory(
                child: SizedBox(height: 50),
              ),
            ),
          ),
        ),
      );

      expect(plugin.scrollableRects, isEmpty);
      expect(plugin.inputAccessoryHeights, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
