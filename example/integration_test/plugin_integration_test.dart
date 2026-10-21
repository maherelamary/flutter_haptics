// Integration tests run against the real plugin, so unlike the Dart unit
// tests these exercise the actual Kotlin and Swift.
//
// Nothing here asserts that something was *felt* — no API can observe that.
// What they check is the contract: every verb answers, the answer is
// self-consistent with what the device reports, and nothing throws under the
// default failure policy.
//
// https://flutter.dev/to/integration-testing

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_haptics/flutter_haptics.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterHaptics.onFailure = HapticFailureMode.silent);

  testWidgets('support answers with a real capability report', (tester) async {
    final support = await FlutterHaptics.support;

    expect(HapticFidelity.values, contains(support.fidelity));
    expect(support.isSupported, support.fidelity != HapticFidelity.none);
    if (support.supportsSharpness) expect(support.supportsIntensity, isTrue);
  });

  testWidgets('playing patterns answers for every shape', (tester) async {
    await FlutterHaptics.prepare();

    for (final pattern in [
      HapticPatterns.mediumTap,
      HapticPatterns.success,
      HapticPatterns.explosion,
      HapticPatterns.chargeUp,
      HapticPatterns.heartbeat.repeat(2),
      HapticPatterns.success.then(HapticPatterns.buzz),
    ]) {
      final route = await FlutterHaptics.play(pattern);
      expect(route, isIn([HapticRoute.pattern, HapticRoute.none]));
    }

    // An empty pattern is a no-op, never a failure.
    expect(await FlutterHaptics.play(HapticPattern.empty), HapticRoute.none);

    await FlutterHaptics.stop();
  });

  testWidgets('this platform\'s own vocabulary answers for every value',
      (tester) async {
    final mine = defaultTargetPlatform == TargetPlatform.android
        ? AndroidHaptic.values.cast<SystemHaptic>()
        : IOSHaptic.values.cast<SystemHaptic>();

    var played = 0;
    for (final haptic in mine) {
      final route = await FlutterHaptics.playSystem(haptic);
      // playSystem never falls back, so only these two are possible.
      expect(route, isIn([HapticRoute.system, HapticRoute.none]));
      if (route == HapticRoute.system) played++;
    }

    debugPrint(
      '${defaultTargetPlatform.name}: $played of ${mine.length} '
      'system haptics played natively',
    );
  });

  testWidgets('the other platform\'s vocabulary always reports none',
      (tester) async {
    final theirs = defaultTargetPlatform == TargetPlatform.android
        ? IOSHaptic.values.cast<SystemHaptic>()
        : AndroidHaptic.values.cast<SystemHaptic>();

    for (final haptic in theirs) {
      expect(await FlutterHaptics.playSystem(haptic), HapticRoute.none);
    }
  });

  testWidgets('an intent takes a route and never nothing', (tester) async {
    // Native on both, so whatever this device is, one of them resolves.
    const intent = HapticIntent(
      ios: HapticArm.native(IOSHaptic.notificationSuccess),
      android: HapticArm.native(AndroidHaptic.confirm),
      pattern: HapticPatterns.success,
    );

    final route = await FlutterHaptics.perform(intent);
    expect(route, isIn([HapticRoute.system, HapticRoute.pattern]));
  });

  testWidgets('a silent arm plays nothing and never the pattern',
      (tester) async {
    const silentEverywhere = HapticIntent(
      ios: HapticArm.silent(),
      android: HapticArm.silent(),
      pattern: HapticPatterns.success,
    );

    expect(await FlutterHaptics.perform(silentEverywhere), HapticRoute.none);
  });

  testWidgets('a pattern arm plays the pattern on any device', (tester) async {
    const patternEverywhere = HapticIntent(
      ios: HapticArm.pattern(),
      android: HapticArm.pattern(),
      pattern: HapticPatterns.success,
    );

    // Chosen, not recovered — nothing native was attempted.
    expect(await FlutterHaptics.perform(patternEverywhere), HapticRoute.pattern);
  });

  testWidgets('a registered handle plays and disposes', (tester) async {
    // Synchronous now; registration resolves in the background.
    final handle = FlutterHaptics.register(
      HapticPatterns.selection,
      minInterval: Duration.zero, // no pacing, so both plays land
    );

    await handle.play();
    await handle.play();
    await handle.dispose();

    expect(await handle.play(), HapticRoute.none);
    expect(handle.isDisposed, isTrue);
  });

  testWidgets('an AHAP asset decodes and plays', (tester) async {
    final pattern = await Ahap.loadAsset('assets/haptics/boing.ahap');

    expect(pattern.events, hasLength(2));
    expect(pattern.events.first, isA<TransientEvent>());
    expect(pattern.events.last, isA<ContinuousEvent>());

    await FlutterHaptics.play(pattern);
  });

  testWidgets('the app-wide switch silences every verb', (tester) async {
    addTearDown(() => FlutterHaptics.enabled = true);
    FlutterHaptics.enabled = false;

    expect(await FlutterHaptics.play(HapticPatterns.heavyTap), HapticRoute.none);
    expect(
      await FlutterHaptics.playSystem(
        defaultTargetPlatform == TargetPlatform.android
            ? AndroidHaptic.longPress
            : IOSHaptic.impactHeavy,
      ),
      HapticRoute.none,
    );

    // stop() is deliberately exempt, so it still has to work.
    await FlutterHaptics.stop();
  });
}
