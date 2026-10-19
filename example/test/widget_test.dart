import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_haptics/flutter_haptics.dart';
import 'package:flutter_haptics/testing.dart';
import 'package:flutter_haptics_example/app_haptics.dart';
import 'package:flutter_haptics_example/main.dart';

void main() {
  // No method channel anywhere in this file: the app talks to the seam, and
  // the seam is a recorder. This is how an app using the package should test
  // its own haptics.
  // Widget tests report defaultTargetPlatform as android, which is what
  // playSystem compares against — so the iOS values below are genuinely
  // off-platform here, with no override needed.
  late FakeHapticsPlatform haptics;

  /// Several turns of bounded pumping, never `pumpAndSettle`. Two things on
  /// screen animate indefinitely — the loading indicator on the Device tab
  /// and the TabBar's ink — so settling either times out or races. The extra
  /// turns are for pages whose initState awaits the seam before rendering.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openTab(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await settle(tester);
  }

  setUp(() {
    FlutterHaptics.debugResetSupportCache();
    haptics = FakeHapticsPlatform();
    FlutterHapticsPlatform.instance = haptics;
  });

  tearDown(() {
    FlutterHaptics.enabled = true;
    FlutterHaptics.onFailure = HapticFailureMode.silent;
    FlutterHapticsPlatform.reset();
  });

  testWidgets('opens on the Device tab and reports what the device can do',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await settle(tester);

    expect(find.text('flutter_haptics'), findsOneWidget);
    expect(find.text('fidelity: full'), findsOneWidget);
    expect(find.text('Anything plays at all'), findsOneWidget);
  });

  testWidgets('every tab renders its content', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await settle(tester);

    for (final entry in {
      'Android': 'Twenty constants, not nine',
      'iOS': 'Impact',
      'Intents': 'Defined by this app',
      'Patterns': 'Taps',
      'Advanced': 'Registered handle',
    }.entries) {
      await openTab(tester, entry.key);

      expect(tester.takeException(), isNull, reason: '${entry.key} tab threw');
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: '${entry.key} tab did not render its content',
      );
    }
  });

  testWidgets('the Android tab plays Android constants', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await settle(tester);
    await openTab(tester, 'Android');

    await tester.tap(find.widgetWithText(FilledButton, 'longPress').first);
    await settle(tester);

    expect(haptics.lastSystemHaptic, AndroidHaptic.longPress);
    expect(haptics.played, isEmpty, reason: 'playSystem never falls back');
    expect(find.text('system'), findsWidgets, reason: 'the route is reported');
  });

  testWidgets('iOS values report none while running on Android',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await settle(tester);
    await openTab(tester, 'iOS');

    await tester.tap(find.widgetWithText(FilledButton, 'impactRigid').first);
    await settle(tester);

    // Never reached the platform at all — the type said it was iOS-only.
    expect(haptics.systemHaptics, isEmpty);
    expect(haptics.played, isEmpty);
    expect(find.text('none'), findsWidgets);
  });

  testWidgets('an intent takes the native route when the device can',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await settle(tester);
    await openTab(tester, 'Intents');

    await tester.tap(find.widgetWithText(FilledButton, 'saved').first);
    await settle(tester);

    expect(haptics.lastSystemHaptic, AndroidHaptic.confirm);
    expect(haptics.played, isEmpty, reason: 'no recovery was needed');
  });

  testWidgets('an intent recovers with its pattern when it cannot',
      (tester) async {
    haptics = FakeHapticsPlatform(playsSystemHaptics: false);
    FlutterHapticsPlatform.instance = haptics;

    await tester.pumpWidget(const ExampleApp());
    await settle(tester);
    await openTab(tester, 'Intents');

    await tester.tap(find.widgetWithText(FilledButton, 'saved').first);
    await settle(tester);

    expect(haptics.lastSystemHaptic, AndroidHaptic.confirm);
    expect(haptics.lastPlayed, AppHaptics.saved.pattern);
    expect(find.text('pattern'), findsWidgets);
  });

  testWidgets('the app-wide switch drives FlutterHaptics.enabled',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await settle(tester);
    expect(FlutterHaptics.enabled, isTrue);

    await tester.tap(find.byType(Switch));
    await settle(tester);

    expect(FlutterHaptics.enabled, isFalse);
  });

  testWidgets('the Advanced tab replays through a registered handle',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await settle(tester);
    await openTab(tester, 'Advanced');

    expect(haptics.registrations, isNotEmpty);

    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await settle(tester);

    expect(haptics.replays, isNotEmpty);
    expect(haptics.played, isEmpty, reason: 'the pattern was not resent');
  });
}
