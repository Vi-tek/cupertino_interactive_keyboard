import 'dart:math';

import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard.dart';
import 'package:cupertino_interactive_keyboard/cupertino_interactive_keyboard_platform_interface.dart';
import 'package:cupertino_interactive_keyboard/src/interactive_keyboard_scroll_physics.dart';
import 'package:flutter/material.dart';
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

  testWidgets(
    'keeps the accessory attached to the keyboard while the keyboard moves',
    (tester) async {
      // The accessory is laid out at the bottom of the content area, which is the bottom of the
      // view minus the viewport inset. While the keyboard is dragged the native side pushes the
      // distance the accessory has to be moved to stay glued to the keyboard.
      const accessoryHeight = 50.0;

      Future<void> pumpWithKeyboard({required bool keyboardVisible}) {
        return tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(800, 600),
                viewInsets: EdgeInsets.only(bottom: keyboardVisible ? 300 : 0),
              ),
              child: const Scaffold(
                body: Column(
                  children: [
                    Expanded(child: SizedBox.shrink()),
                    CupertinoInputAccessory(
                      child: SizedBox(height: accessoryHeight),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      await pumpWithKeyboard(keyboardVisible: true);
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(CupertinoInputAccessory)).height,
        accessoryHeight,
      );
      expect(
        tester.getRect(find.byType(CupertinoInputAccessory)).bottom,
        600 - 300,
        reason: 'the accessory sits right above the keyboard',
      );

      // The keyboard is dragged down by 40 points, the accessory follows it.
      plugin.keyboardTranslation.value = 40;
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(CupertinoInputAccessory)).bottom,
        600 - 300 + 40,
        reason: 'the accessory follows the keyboard down',
      );

      // The keyboard is dismissed, the viewport grows and the accessory moves down with it.
      plugin.keyboardTranslation.value = 0;
      await pumpWithKeyboard(keyboardVisible: false);
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(CupertinoInputAccessory)).bottom,
        600,
        reason: 'the accessory returns to the bottom of the view',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'moves the accessory without rebuilding the rest of the tree',
    (tester) async {
      // The translation is applied with a transform, so the widget tree is not relayouted on
      // every frame of the drag. A relayout drops frames, which makes the accessory trail
      // behind the keyboard.
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      buildCount++;
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                const CupertinoInputAccessory(
                  child: SizedBox(height: 50),
                ),
              ],
            ),
          ),
        ),
      );

      expect(buildCount, 1);

      plugin.keyboardTranslation.value = 20;
      await tester.pumpAndSettle();

      expect(
        buildCount,
        1,
        reason: 'the translation does not rebuild the rest of the tree',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
