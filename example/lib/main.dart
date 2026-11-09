import 'package:example/catalog.dart';
import 'package:example/keyboard_accessory.dart';
import 'package:example/nested_navigation.dart';
import 'package:example/reversed_scroll_view.dart';
import 'package:example/simple_scroll_view.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        "/": (context) => const Catalog(),
        "/simple_scroll_view": (context) => const SimpleScrollView(),
        "/input_accessory": (context) => const KeyboardAccessory(),
        "/nested_navigation": (context) => const NestedNavigation(),
        "/reversed_scroll_view": (context) => const ReversedScrollView(),
      },
    );
  }
}
