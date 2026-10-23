import 'package:clock/clock.dart';
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
    FlutterHaptics.onFailureReport = null;
    FlutterHaptics.debugResetSupportCache();
    FlutterHaptics.debugResetFailureLog();
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
      ios: HapticArm.native(IOSHaptic.notificationSuccess),
      android: HapticArm.native(AndroidHaptic.confirm),
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

    test('a silent arm plays nothing, and never the pattern', () async {
      const silentHere = HapticIntent(
        ios: HapticArm.native(IOSHaptic.notificationWarning),
        android: HapticArm.silent(),
        pattern: HapticPatterns.warning,
      );

      expect(await FlutterHaptics.perform(silentHere), HapticRoute.none);
      expect(haptics.systemHaptics, isEmpty, reason: 'nothing was asked for');
      expect(haptics.played, isEmpty, reason: 'silence is not a fallback');
    });

    test('a pattern arm plays the pattern without asking the platform',
        () async {
      const patternHere = HapticIntent(
        ios: HapticArm.native(IOSHaptic.notificationWarning),
        android: HapticArm.pattern(),
        pattern: HapticPatterns.warning,
      );

      expect(await FlutterHaptics.perform(patternHere), HapticRoute.pattern);
      expect(haptics.systemHaptics, isEmpty, reason: 'chosen, not recovered');
      expect(haptics.lastPlayed, HapticPatterns.warning);
    });

    test('a chosen pattern and a recovered one differ in the intent only',
        () async {
      install(FakeHapticsPlatform(playsSystemHaptics: false));

      const chosen = HapticIntent(
        ios: HapticArm.pattern(),
        android: HapticArm.pattern(),
        pattern: HapticPatterns.warning,
      );
      const recovered = HapticIntent(
        ios: HapticArm.native(IOSHaptic.notificationWarning),
        android: HapticArm.native(AndroidHaptic.confirm),
        pattern: HapticPatterns.warning,
      );

      expect(await FlutterHaptics.perform(chosen), HapticRoute.pattern);
      expect(haptics.systemHaptics, isEmpty);

      expect(await FlutterHaptics.perform(recovered), HapticRoute.pattern);
      expect(haptics.systemHaptics, [AndroidHaptic.confirm],
          reason: 'the recovery asked first');
    });

    test('armFor picks the arm for the platform', () {
      expect(
        saved.armFor(TargetPlatform.android),
        const HapticArm<AndroidHaptic>.native(AndroidHaptic.confirm),
      );
      expect(
        saved.armFor(TargetPlatform.iOS),
        const HapticArm<IOSHaptic>.native(IOSHaptic.notificationSuccess),
      );
      expect(saved.armFor(TargetPlatform.macOS), isNull);
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
            ios: HapticArm.native(IOSHaptic.notificationSuccess),
            android: HapticArm.native(AndroidHaptic.confirm),
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

  group('arms', () {
    test('equality does not depend on which side the general type is on', () {
      const specific = HapticArm<IOSHaptic>.pattern();
      const general = HapticArm<SystemHaptic>.pattern();

      expect(specific == general, general == specific);
      expect(specific, general);
      expect(specific.hashCode, general.hashCode);

      const silentSpecific = HapticArm<AndroidHaptic>.silent();
      const silentGeneral = HapticArm<SystemHaptic>.silent();
      expect(silentSpecific == silentGeneral, silentGeneral == silentSpecific);
      expect(silentSpecific.hashCode, silentGeneral.hashCode);

      const nativeSpecific = HapticArm<AndroidHaptic>.native(AndroidHaptic.confirm);
      const nativeGeneral = HapticArm<SystemHaptic>.native(AndroidHaptic.confirm);
      expect(nativeSpecific == nativeGeneral, nativeGeneral == nativeSpecific);
      expect(nativeSpecific.hashCode, nativeGeneral.hashCode);
    });

    test('the three arms are distinct, and natives differ by haptic', () {
      expect(
        const HapticArm<AndroidHaptic>.pattern(),
        isNot(const HapticArm<AndroidHaptic>.silent()),
      );
      expect(
        const HapticArm.native(AndroidHaptic.confirm),
        isNot(const HapticArm.native(AndroidHaptic.reject)),
      );
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
            ios: HapticArm.native(IOSHaptic.impactHeavy),
            android: HapticArm.native(AndroidHaptic.toggleOn),
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

    test('a reporter sees each distinct failure once', () async {
      install(FakeHapticsPlatform(
        playsSystemHaptics: false,
        declineReason: 'requires API 34, this device is 31',
      ));
      final seen = <HapticFailure>[];
      FlutterHaptics.onFailureReport = seen.add;

      await FlutterHaptics.playSystem(AndroidHaptic.toggleOn);
      await FlutterHaptics.playSystem(AndroidHaptic.toggleOn);
      await FlutterHaptics.playSystem(AndroidHaptic.toggleOff);

      expect(seen, hasLength(2), reason: 'the repeat said nothing new');
      expect(seen.first.request, 'playSystem(toggleOn)');
      expect(seen.last.request, 'playSystem(toggleOff)');
      expect(seen.first.reason, contains('API 34'));
    });

    test('two patterns that read the same are reported separately', () async {
      install(FakeHapticsPlatform(support: HapticSupport.unsupported));
      final seen = <HapticFailure>[];
      FlutterHaptics.onFailureReport = seen.add;

      // Same event count, same duration — so the same sentence describes
      // both, which is exactly why the sentence cannot be the key.
      const quiet =
          HapticPattern([TransientEvent(intensity: 0.2, sharpness: 0.5)]);
      const loud =
          HapticPattern([TransientEvent(intensity: 0.9, sharpness: 0.5)]);

      await FlutterHaptics.play(quiet);
      await FlutterHaptics.play(loud);
      await FlutterHaptics.play(quiet);

      expect(seen, hasLength(2), reason: 'the repeat of quiet was dropped');
      expect(
        seen.map((f) => f.request).toSet(),
        hasLength(1),
        reason: 'both describe themselves identically',
      );
      expect(seen.map((f) => f.pattern), [quiet, loud]);
    });

    test('a failure names the constant that did not play', () async {
      install(FakeHapticsPlatform(playsSystemHaptics: false));
      final seen = <HapticFailure>[];
      FlutterHaptics.onFailureReport = seen.add;

      await FlutterHaptics.playSystem(AndroidHaptic.toggleOn);

      expect(seen.single.haptic, AndroidHaptic.toggleOn);
      expect(seen.single.pattern, isNull);
    });

    test('a reporter replaces the mode rather than adding to it', () async {
      FlutterHaptics.onFailure = HapticFailureMode.throwIt;
      final seen = <HapticFailure>[];
      FlutterHaptics.onFailureReport = seen.add;

      // Would throw without the reporter.
      expect(
        await FlutterHaptics.playSystem(IOSHaptic.selection),
        HapticRoute.none,
      );
      expect(seen, hasLength(1));
    });

    test('throwing is never deduplicated', () async {
      FlutterHaptics.onFailure = HapticFailureMode.throwIt;

      for (var i = 0; i < 2; i++) {
        await expectLater(
          FlutterHaptics.playSystem(IOSHaptic.selection),
          throwsA(isA<HapticFailure>()),
          reason: 'a swallowed second throw would be the real surprise',
        );
      }
    });
  });

  group('the fake device', () {
    test('a weak actuator declines a perceptible request', () async {
      install(FakeHapticsPlatform(
        support: const HapticSupport(
          fidelity: HapticFidelity.rhythm,
          supportsContinuous: true,
        ),
      ));

      // perform asks for perceptibility, so it recovers with the pattern.
      expect(
        await FlutterHaptics.perform(
          const HapticIntent(
            ios: HapticArm.native(IOSHaptic.notificationSuccess),
            android: HapticArm.native(AndroidHaptic.confirm),
            pattern: HapticPatterns.success,
          ),
        ),
        HapticRoute.pattern,
      );
      expect(haptics.lastPlayed, HapticPatterns.success);

      // playSystem does not, so the same device takes it.
      expect(
        await FlutterHaptics.playSystem(AndroidHaptic.confirm),
        HapticRoute.system,
      );
    });

    test('clear() keeps live registrations alive', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );
      await handle.ready;

      haptics.clear();

      expect(await handle.play(), HapticRoute.pattern);
      expect(haptics.replays, [1], reason: 'it replayed, not resent');
      expect(haptics.played, isEmpty);
    });

    test('a released registration stops replaying', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );
      await handle.ready;
      await handle.dispose();

      // A second handle on the same fake gets a fresh id; the released one
      // must not still answer.
      expect(haptics.releases, [1]);
      expect(
        await FlutterHapticsPlatform.instance.playRegistered(1),
        isA<NativeResult>().having((r) => r.played, 'played', isFalse),
      );
    });

    test('an intent is recorded even while haptics are off', () async {
      const saved = HapticIntent(
        ios: HapticArm.native(IOSHaptic.notificationSuccess),
        android: HapticArm.native(AndroidHaptic.confirm),
        pattern: HapticPatterns.success,
      );
      FlutterHaptics.enabled = false;

      expect(await FlutterHaptics.perform(saved), HapticRoute.none);

      expect(haptics.intents, [saved], reason: 'the app still asked');
      expect(haptics.systemHaptics, isEmpty, reason: 'but nothing was tried');
    });

    test('a device with no hardware plays nothing', () async {
      install(FakeHapticsPlatform(support: HapticSupport.unsupported));

      expect(await FlutterHaptics.play(HapticPatterns.success),
          HapticRoute.none);
      expect(haptics.played, [HapticPatterns.success],
          reason: 'it still records what was asked for');
    });

    test('a taps-only device refuses a pattern with no taps', () async {
      install(FakeHapticsPlatform(
        support: const HapticSupport(
          fidelity: HapticFidelity.intensity,
          supportsContinuous: false,
        ),
      ));

      // What iPhone 7 does: a rumble has nothing to sustain it.
      expect(await FlutterHaptics.play(HapticPatterns.buzz), HapticRoute.none);
      expect(await FlutterHaptics.play(HapticPatterns.success),
          HapticRoute.pattern);
    });

    test('records the intent, not just what it resolved to', () async {
      const saved = HapticIntent(
        ios: HapticArm.native(IOSHaptic.notificationSuccess),
        android: HapticArm.pattern(),
        pattern: HapticPatterns.success,
      );

      await FlutterHaptics.perform(saved);

      expect(haptics.intents, [saved]);
      expect(haptics.lastIntent, saved);
      expect(haptics.systemHaptics, isEmpty);
    });
  });

  group('handles', () {
    test('replay uses the registration rather than resending', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );

      expect(await handle.play(), HapticRoute.pattern);
      await handle.play();

      expect(handle.isPrepared, isTrue);
      expect(haptics.replays, [1, 1]);
      expect(haptics.played, isEmpty);
    });

    test('a platform that cannot register still plays', () async {
      install(FakeHapticsPlatform(canRegister: false));

      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );
      expect(await handle.play(), HapticRoute.pattern);

      expect(handle.isPrepared, isFalse);
      expect(haptics.played, [HapticPatterns.selection]);
    });

    test('dispose releases it and silences play', () async {
      final handle = FlutterHaptics.register(HapticPatterns.selection);
      await handle.ready;
      await handle.dispose();

      expect(haptics.releases, [1]);
      expect(await handle.play(), HapticRoute.none);
    });

    test('ready settles the registration and the interval', () async {
      install(FakeHapticsPlatform(
        support: const HapticSupport(
          fidelity: HapticFidelity.rhythm,
          supportsContinuous: true,
        ),
      ));

      final handle = FlutterHaptics.register(HapticPatterns.selection);
      expect(handle.isPrepared, isFalse, reason: 'nothing has answered yet');
      expect(handle.minInterval, const Duration(milliseconds: 40));

      await handle.ready;

      expect(handle.isPrepared, isTrue);
      expect(handle.minInterval, const Duration(milliseconds: 60));
    });

    test('a play that beats registration waits for it', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );

      // No `await ready` — this is the first frame.
      expect(await handle.play(), HapticRoute.pattern);
      expect(haptics.replays, [1]);
      expect(haptics.played, isEmpty, reason: 'it did not resend the pattern');
    });
  });

  group('pacing', () {
    test('the default floor comes from the device, not the platform', () async {
      for (final (fidelity, expected) in [
        (HapticFidelity.full, 25),
        (HapticFidelity.intensity, 35),
        (HapticFidelity.rhythm, 60),
      ]) {
        install(FakeHapticsPlatform(
          support: HapticSupport(fidelity: fidelity, supportsContinuous: true),
        ));
        FlutterHaptics.debugResetSupportCache();

        final handle = FlutterHaptics.register(HapticPatterns.selection);
        await handle.ready;

        expect(handle.minInterval, Duration(milliseconds: expected),
            reason: '$fidelity');
      }
    });

    test('a second play inside the floor is dropped', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: const Duration(milliseconds: 50),
      );
      await handle.ready;

      await withClock(Clock.fixed(DateTime(2026)), () async {
        expect(await handle.play(), HapticRoute.pattern);
        expect(await handle.play(), HapticRoute.none, reason: 'no time passed');
      });

      expect(haptics.replays, hasLength(1));
    });

    test('a play after the floor is let through', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: const Duration(milliseconds: 50),
      );
      await handle.ready;

      var now = DateTime(2026);
      await withClock(Clock(() => now), () async {
        expect(await handle.play(), HapticRoute.pattern);
        now = now.add(const Duration(milliseconds: 51));
        expect(await handle.play(), HapticRoute.pattern);
      });

      expect(haptics.replays, [1, 1]);
    });

    test('a clock that jumps backwards does not mute the handle', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: const Duration(milliseconds: 50),
      );
      await handle.ready;

      var now = DateTime(2026);
      await withClock(Clock(() => now), () async {
        expect(await handle.play(), HapticRoute.pattern);
        // An NTP correction, or someone changing the clock by hand.
        now = now.subtract(const Duration(hours: 1));
        expect(await handle.play(), HapticRoute.pattern,
            reason: 'otherwise the handle is silent for an hour');
      });
    });

    test('zero fires every call', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );
      await handle.ready;

      await withClock(Clock.fixed(DateTime(2026)), () async {
        for (var i = 0; i < 3; i++) {
          expect(await handle.play(), HapticRoute.pattern);
        }
      });

      expect(haptics.replays, [1, 1, 1]);
    });
  });

  group('a handle that loses its registration', () {
    test('falls back, forgets the id, and stops paying for it', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );
      await handle.ready;
      expect(await handle.play(), HapticRoute.pattern);

      // What Android does when the plugin detaches from its engine.
      haptics.debugLoseRegistrations();

      expect(await handle.play(), HapticRoute.pattern);
      expect(haptics.played, [HapticPatterns.selection]);
      expect(handle.isPrepared, isFalse, reason: 'it stopped claiming it');

      expect(await handle.play(), HapticRoute.pattern);
      expect(haptics.replays, hasLength(2),
          reason: 'the third play did not retry the dead id');
      expect(haptics.played, hasLength(2));
    });

    test('a refusal that is not a loss keeps the registration', () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );
      await handle.ready;
      expect(await handle.play(), HapticRoute.pattern);

      // The engine will not play, but it still holds the pattern.
      haptics.refuseReplays = true;
      expect(await handle.play(), HapticRoute.pattern);
      expect(haptics.played, [HapticPatterns.selection],
          reason: 'it fell back to sending the pattern');
      expect(handle.isPrepared, isTrue,
          reason: 'one bad moment must not cost it the registration');

      haptics.refuseReplays = false;
      expect(await handle.play(), HapticRoute.pattern);
      expect(haptics.replays, hasLength(3));
      expect(haptics.played, hasLength(1), reason: 'back to replaying');
    });

    test('a dispose during registration silences the play waiting on it',
        () async {
      final handle = FlutterHaptics.register(
        HapticPatterns.selection,
        minInterval: Duration.zero,
      );

      // Both start before either resolves.
      final play = handle.play();
      final dispose = handle.dispose();
      await Future.wait([play, dispose]);

      expect(await play, HapticRoute.none);
      expect(haptics.played, isEmpty, reason: 'nothing plays after dispose');
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
