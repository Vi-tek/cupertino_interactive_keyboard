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
    Object? arguments,
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

  testWidgets('runCupertinoAccessory renders the builder and reports ready',
      (tester) async {
    late CupertinoAccessoryController controller;

    runCupertinoAccessory((context, value) {
      controller = value;
      return const Center(child: Text('accessory'));
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('accessory'), findsOneWidget);
    expect(controller, isA<CupertinoAccessoryController>());
    expect(calls.where((call) => call.method == 'ready'), hasLength(1));
  });

  testWidgets(
      'routes native calls to onInvoke and accessory calls to the channel',
      (tester) async {
    late CupertinoAccessoryController controller;
    final received = <Map<String, Object?>>[];

    runCupertinoAccessory((context, value) {
      controller = value;
      return const SizedBox.shrink();
    });
    await tester.pump();
    await tester.pump();

    controller.onInvoke = (method, arguments) {
      received.add({'method': method, 'arguments': arguments});
    };

    await push(tester, 'invoke', {
      'method': 'theme',
      'arguments': {'surface': 1},
    });

    expect(received, [
      {
        'method': 'theme',
        'arguments': {'surface': 1},
      },
    ]);

    calls.clear();
    controller.invoke('textChanged', {'text': 'hello'});
    controller.invoke('ping');
    await tester.pump();

    expect(calls.map((call) => call.method), ['invoke', 'invoke']);
    expect(calls[0].arguments, {
      'method': 'textChanged',
      'arguments': {'text': 'hello'},
    });
    expect(calls[1].arguments, {'method': 'ping', 'arguments': null});
  });

  testWidgets('reports the bar content height to native', (tester) async {
    runCupertinoAccessory(
      (context, value) => const SizedBox(
        height: 120,
        width: 10,
        child: ColoredBox(color: Colors.red),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final heights = calls
        .where((call) => call.method == 'contentHeight')
        .map((call) => ((call.arguments as Map)['height'] as num).toDouble())
        .toList();
    expect(heights, isNotEmpty);
    expect(heights.last, closeTo(120, 0.5));
  });

  testWidgets('removes the channel handler on dispose', (tester) async {
    late CupertinoAccessoryController controller;
    var invokes = 0;

    runCupertinoAccessory((context, value) {
      controller = value;
      return const SizedBox.shrink();
    });
    await tester.pump();
    await tester.pump();

    controller.onInvoke = (method, arguments) => invokes++;

    await tester.pumpWidget(const SizedBox.shrink());
    await push(tester, 'invoke', {'method': 'theme', 'arguments': null});

    expect(invokes, 0);
  });

  testWidgets('runCupertinoKeyboardSurface is a full-size host without a sizer',
      (tester) async {
    late CupertinoAccessoryController controller;

    runCupertinoKeyboardSurface((context, value) {
      controller = value;
      return const Align(child: Text('surface'));
    });
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('surface'), findsOneWidget);
    expect(controller, isA<CupertinoAccessoryController>());
    expect(tester.getSize(find.byType(Align)), const Size(800, 600));
    expect(calls.where((call) => call.method == 'ready'), hasLength(1));
    expect(calls.where((call) => call.method == 'contentHeight'), isEmpty);
  });

  testWidgets('the surface host unfocuses the composer when hidden',
      (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);

    runCupertinoKeyboardSurface(
      (context, value) => Focus(focusNode: node, child: const Text('composer')),
    );
    await tester.pump();
    await tester.pump();

    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);

    await push(tester, 'invoke', {
      'method': 'hidden',
      'arguments': {'hidden': true},
    });
    expect(node.hasFocus, isFalse);
  });

  testWidgets('forwards keyboardDragging to the controller, not to onInvoke',
      (tester) async {
    late CupertinoAccessoryController controller;

    runCupertinoKeyboardSurface((context, value) {
      controller = value;
      return const SizedBox.shrink();
    });
    await tester.pump();
    await tester.pump();

    final dragging = <bool>[];
    final invoked = <String>[];
    controller.onKeyboardDragging = dragging.add;
    controller.onInvoke = (method, arguments) => invoked.add(method);

    await push(tester, 'invoke', {
      'method': 'keyboardDragging',
      'arguments': {'dragging': true},
    });
    await push(tester, 'invoke', {
      'method': 'keyboardDragging',
      'arguments': {'dragging': false},
    });

    expect(dragging, [true, false]);
    expect(invoked, isEmpty);
  });
}
