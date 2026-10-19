import 'package:flutter/material.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

import 'pages/advanced_page.dart';
import 'pages/android_page.dart';
import 'pages/device_page.dart';
import 'pages/intents_page.dart';
import 'pages/ios_page.dart';
import 'pages/patterns_page.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_haptics',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B4ACB)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // Warms the iOS engine so the first tap is not the slow one.
    FlutterHaptics.prepare();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_haptics'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Device', icon: Icon(Icons.smartphone)),
              Tab(text: 'Android', icon: Icon(Icons.android)),
              Tab(text: 'iOS', icon: Icon(Icons.phone_iphone)),
              Tab(text: 'Intents', icon: Icon(Icons.swap_horiz)),
              Tab(text: 'Patterns', icon: Icon(Icons.graphic_eq)),
              Tab(text: 'Advanced', icon: Icon(Icons.tune)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            DevicePage(),
            AndroidPage(),
            IOSPage(),
            IntentsPage(),
            PatternsPage(),
            AdvancedPage(),
          ],
        ),
      ),
    );
  }
}
