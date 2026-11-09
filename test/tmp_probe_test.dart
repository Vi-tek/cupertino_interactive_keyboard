import 'package:cupertino_interactive_keyboard/src/height_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('probe transform with proxy box', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.shrink()),
              Transform.translate(
                offset: const Offset(0, 40),
                child: HeightObserver(
                  onChange: _noop,
                  child: const SizedBox(height: 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    debugPrint('proxy rect: ' + tester.getRect(find.byType(HeightObserver)).toString());
    debugPrint('sizedbox rect: ' + tester.getRect(find.byType(SizedBox).last).toString());
  });
}

void _noop(double height) {}
