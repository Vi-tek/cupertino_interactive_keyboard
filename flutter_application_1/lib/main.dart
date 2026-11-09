import 'package:flutter_application_1/catalog.dart';
import 'package:flutter_application_1/input_accessory.dart';
import 'package:flutter_application_1/nested_navigation.dart';
import 'package:flutter_application_1/reversed_scroll_view.dart';
import 'package:flutter_application_1/simple_scroll_view.dart';
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
        "/input_accessory": (context) => const InputAccessory(),
        "/nested_navigation": (context) => const NestedNavigation(),
        "/reversed_scroll_view": (context) => const ReversedScrollView(),
      },
    );
  }
}