import 'package:flutter/foundation.dart';
import 'package:flutter_haptics/flutter_haptics.dart';
import 'package:flutter_haptics/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeHapticsPlatform haptics;

  void install(FakeHapticsPlatform fake) {
    haptics = fake;
    FlutterHapticsPlatform.instance = fake;
  }

  setUp(() {
    install(FakeHapticsPlatform());
    // Unit tests report defaultTargetPlatform as android, so AndroidHaptic
    // values are on-platform here and IOSHaptic values are not.
    FlutterHaptics.onFailure = HapticFailureMode.silent;
  });

  tearDown(() {
    FlutterHaptics.enabled = true;
    FlutterHaptics.onFailure = HapticFailureMode.silent;
    FlutterHaptics.debugResetSupportCache();
    FlutterHapticsPlatform.reset();
  });

  group('play', () {
    test('renders a pattern and says so', () async {
      expect(
        await FlutterHaptics.play(HapticPatterns.success),
        HapticRoute.pattern,
      );
      expect(haptics.played, [HapticPatterns.success]);
    });

    test('an empty pattern never reaches the platform', () async {
      expect(await FlutterHaptics.play(HapticPattern.empty), HapticRoute.none);
      expect(haptics.played, isEmpty);
    });
  });

  group('playSystem', () {
    test('plays a value belonging to this platform', () async {
      expect(
        await FlutterHaptics.playSystem(AndroidHaptic.toggleOn),
        HapticRoute.system,
      );
      expect(haptics.systemHaptics, [AndroidHaptic.toggleOn]);
    });

    test('never reaches the platform with another platform\'s value',
        () async {
      expect(
        await FlutterHaptics.playSystem(IOSHaptic.impactRigid),
        HapticRoute.none,
      );
      expect(haptics.systemHaptics, isEmpty);
    });

    test('never falls back to a pattern', () async {
      install(FakeHapticsPlatform(playsSystemHaptics: false));

      expect(
        await FlutterHaptics.playSystem(AndroidHaptic.confirm),
        HapticRoute.none,
      );
      expect(haptics.systemHaptics, [AndroidHaptic.confirm]);
      expect(haptics.played, isEmpty, reason: 'playSystem has no recovery');
    });

    test('does not ask the device to be second-guessed', () async {
      // The vendor implements these constants for this hardware. playSystem
      // was asked for this exact one, so it hands the request over rather
      // than refusing it on a heuristic.
      await FlutterHaptics.playSystem(AndroidHaptic.clockTick);

      expect(haptics.requiredPerceptible, [false]);
    });

    test('every value carries its platform and minimum version', () {
      for (final haptic in AndroidHaptic.values) {
        expect(haptic.platform, TargetPlatform.android);
        expect(haptic.minimumVersion, greaterThan(0));
      }
      for (final haptic in IOSHaptic.values) {
        expect(haptic.platform, TargetPlatform.iOS);
        expect(haptic.minimumVersion, greaterThan(0));
      }
      expect(AndroidHaptic.values, hasLength(20));
      expect(IOSHaptic.values, hasLength(9));
    });

    test('NO_HAPTICS is not among them', () {
      expect(
        AndroidHaptic.values.map((h) => h.name),
        isNot(anyElement(contains('noHaptics'))),
      );
    });
  });

  group('perform', () {
    const saved = HapticIntent(
      ios: IOSHaptic.notificationSuccess,
      android: AndroidHaptic.confirm,
      pattern: HapticPatterns.success,
    );

    test('takes the native route when the device can', () async {
      expect(await FlutterHaptics.perform(saved), HapticRoute.system);
      expect(haptics.systemHaptics, [AndroidHaptic.confirm]);
      expect(haptics.played, isEmpty);
    });

    test('does ask the device to be second-guessed', () async {
      // Unlike playSystem: this verb carries a pattern it knows works, so a
      // route that might be accepted without being felt is not good enough.
      await FlutterHaptics.perform(saved);

      expect(haptics.requiredPerceptible, [true]);
    });

    test('recovers with the pattern when it cannot', () async {
      install(FakeHapticsPlatform(playsSystemHaptics: false));

      expect(await FlutterHaptics.perform(saved), HapticRoute.pattern);
      expect(haptics.systemHaptics, [AndroidHaptic.confirm]);
      expect(haptics.lastPlayed, HapticPatterns.success);
    });

    test('a null arm is a deliberate silence, not a recovery', () async {
      const iosOnly = HapticIntent(
        ios: IOSHaptic.notificationWarning,
        android: null,
        pattern: HapticPatterns.warning,
      );

      expect(await FlutterHaptics.perform(iosOnly), HapticRoute.none);
      expect(haptics.systemHaptics, isEmpty, reason: 'nothing was asked for');
      expect(haptics.played, isEmpty, reason: 'the pattern is not a substitute');
    });

    test('routeFor picks the arm for the platform', () {
      expect(saved.routeFor(TargetPlatform.android), AndroidHaptic.confirm);
      expect(saved.routeFor(TargetPlatform.iOS), IOSHaptic.notificationSuccess);
      expect(saved.routeFor(TargetPlatform.macOS), isNull);
    });
  });

  group('the app-wide switch', () {
    test('silences every verb', () async {
      FlutterHaptics.enabled = false;

      expect(await FlutterHaptics.play(HapticPatterns.success), HapticRoute.none);
      expect(
        await FlutterHaptics.playSystem(AndroidHaptic.confirm),
        HapticRoute.none,
      );
      expect(
        await FlutterHaptics.perform(
          const HapticIntent(
            android: AndroidHaptic.confirm,
            pattern: HapticPatterns.success,
          ),
        ),
        HapticRoute.none,
      );

      expect(haptics.played, isEmpty);
      expect(haptics.systemHaptics, isEmpty);
    });

    test('stop is exempt', () async {
      FlutterHaptics.enabled = false;
      await FlutterHaptics.stop();
      expect(haptics.stopCount, 1);
    });

    test('being switched off is never a failure', () async {
      FlutterHaptics.onFailure = HapticFailureMode.throwIt;
      FlutterHaptics.enabled = false;

      // None of these may throw: the app asked for silence and got it.
      await FlutterHaptics.play(HapticPatterns.success);
      await FlutterHaptics.playSystem(AndroidHaptic.confirm);
    });
  });

  group('the failure policy', () {
    test('throws only where a haptic was asked for and not delivered',
        () async {
      install(FakeHapticsPlatform(
        playsSystemHaptics: false,
        declineReason: 'requires API 34, this device is 31',
      ));
      FlutterHaptics.onFailure = HapticFailureMode.throwIt;

      await expectLater(
        FlutterHaptics.playSystem(AndroidHaptic.toggleOn),
        throwsA(
          isA<HapticFailure>()
              .having((e) => e.request, 'request', 'playSystem(toggleOn)')
              .having((e) => e.reason, 'reason', contains('API 34')),
        ),
      );
    });

    test('an off-platform value explains itself', () async {
      FlutterHaptics.onFailure = HapticFailureMode.throwIt;

      await expectLater(
        FlutterHaptics.playSystem(IOSHaptic.selection),
        throwsA(
          isA<HapticFailure>()
              .having((e) => e.reason, 'reason', contains('belongs to iOS')),
        ),
      );
    });

    test('an intent that recovers is not a failure', () async {
      install(FakeHapticsPlatform(playsSystemHaptics: false));
      FlutterHaptics.onFailure = HapticFailureMode.throwIt;

      // The native route declined, but the intent did what it promised.
      expect(
        await FlutterHaptics.perform(
          const HapticIntent(
            android: AndroidHaptic.toggleOn,
            pattern: HapticPatterns.mediumTap,
          ),
        ),
        HapticRoute.pattern,
      );
    });

    test('silent mode stays quiet', () async {
      FlutterHaptics.onFailure = HapticFailureMode.silent;
      expect(
        await FlutterHaptics.playSystem(IOSHaptic.selection),
        HapticRoute.none,
      );
    });
  });

  group('handles', () {
    test('replay uses the registration rather than resending', () async {
      final handle = await FlutterHaptics.register(HapticPatterns.selection);

      expect(await handle.play(), HapticRoute.pattern);
      await handle.play();

      expect(handle.isPrepared, isTrue);
      expect(haptics.replays, [1, 1]);
      expect(haptics.played, isEmpty);
    });

    test('a platform that cannot register still plays', () async {
      install(FakeHapticsPlatform(canRegister: false));

      final handle = await FlutterHaptics.register(HapticPatterns.selection);
      expect(await handle.play(), HapticRoute.pattern);

      expect(handle.isPrepared, isFalse);
      expect(haptics.played, [HapticPatterns.selection]);
    });

    test('dispose releases it and silences play', () async {
      final handle = await FlutterHaptics.register(HapticPatterns.selection);
      await handle.dispose();

      expect(haptics.releases, [1]);
      expect(await handle.play(), HapticRoute.none);
    });
  });

  group('the seam', () {
    test('defaults to the channel-backed implementation', () {
      FlutterHapticsPlatform.reset();
      expect(FlutterHapticsPlatform.instance, isA<MethodChannelHaptics>());
    });

    test('support is queried once and cached', () async {
      install(FakeHapticsPlatform(
        support: const HapticSupport(
          fidelity: HapticFidelity.rhythm,
          supportsContinuous: true,
        ),
      ));

      expect((await FlutterHaptics.support).fidelity, HapticFidelity.rhythm);
      expect(await FlutterHaptics.isSupported, isTrue);
    });
  });
}
