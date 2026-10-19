import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_haptics');
  final log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      // What the real Kotlin and Swift answer for the two verbs that report.
      if (methodCall.method == 'play' || methodCall.method == 'playSystem') {
        return <String, Object?>{'played': true, 'reason': ''};
      }
      return null;
    });
  });

  tearDown(() {
    FlutterHaptics.onFailure = HapticFailureMode.silent;
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FlutterHaptics', () {
    test('play sends correct method call', () async {
      await FlutterHaptics.play(HapticPatterns.mediumTap);

      expect(log, hasLength(1));
      expect(log.first.method, 'play');
      expect(log.first.arguments, isA<Map>());
      expect((log.first.arguments as Map)['events'], isA<List>());
    });

    test('play with empty pattern does not call native', () async {
      await FlutterHaptics.play(HapticPattern.empty);

      expect(log, isEmpty);
    });

    test('prepare sends correct method call', () async {
      await FlutterHaptics.prepare();

      expect(log, hasLength(1));
      expect(log.first.method, 'prepare');
    });

    test('stop sends correct method call', () async {
      await FlutterHaptics.stop();

      expect(log, hasLength(1));
      expect(log.first.method, 'stop');
    });
  });

  group('HapticPattern', () {
    test('then combines patterns sequentially', () {
      final p1 = HapticPattern([
        TransientEvent(intensity: 0.5, delay: Duration.zero),
      ]);
      final p2 = HapticPattern([
        TransientEvent(intensity: 0.8, delay: Duration.zero),
      ]);

      final combined = p1.then(p2);

      expect(combined.events, hasLength(2));
    });

    test('repeat creates correct number of events', () {
      final pattern = HapticPatterns.mediumTap;
      final repeated = pattern.repeat(3);

      expect(repeated.events, hasLength(3));
    });

    test('duration counts a closing transient as one tap wide', () {
      // heartbeat's last tap starts at 130ms; the pattern ends when that tap
      // does, not when it begins.
      expect(
        HapticPatterns.heartbeat.duration,
        Duration(milliseconds: 130) + HapticEvent.transientWidth,
      );
    });

    test('repeat does not stack repetitions on top of each other', () {
      final repeated = HapticPatterns.heartbeat.repeat(3);

      final delays =
          repeated.events.map((e) => (e as TransientEvent).delay).toList();

      expect(repeated.events, hasLength(6));
      expect(delays.toSet(), hasLength(6), reason: 'no two beats collide');
      expect(delays, orderedEquals(List.of(delays)..sort()));
    });

    test('then does not overlap the seam between patterns', () {
      final chained = HapticPatterns.success.then(HapticPatterns.success);

      final delays =
          chained.events.map((e) => (e as TransientEvent).delay).toList();

      expect(delays.toSet(), hasLength(6), reason: 'no tap shares an instant');
      // Every event of the second pattern starts after the first has finished.
      expect(
        delays.skip(3).every((d) => d >= HapticPatterns.success.duration),
        isTrue,
      );
    });

    test('overlay still allows deliberate simultaneity', () {
      final layered = HapticPatterns.mediumTap.overlay(HapticPatterns.soft);

      expect(layered.events, hasLength(2));
      expect(layered.events.every((e) => e.start == Duration.zero), isTrue);
    });

    test('event end reflects transient width and continuous duration', () {
      const tap = TransientEvent(intensity: 1.0, delay: Duration(seconds: 1));
      final rumble = ContinuousEvent(
        intensity: 0.5,
        duration: Duration(milliseconds: 200),
        delay: Duration(milliseconds: 50),
      );

      expect(tap.end, Duration(seconds: 1) + HapticEvent.transientWidth);
      expect(rumble.end, Duration(milliseconds: 250));
    });

    test('scaled adjusts intensity', () {
      final pattern = HapticPattern([
        TransientEvent(intensity: 1.0),
      ]);
      final scaled = pattern.scaled(0.5);

      final event = scaled.events.first as TransientEvent;
      expect(event.intensity, 0.5);
    });

    test('forPlatform resolves android pattern on Android', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ios = HapticPattern([TransientEvent(intensity: 1.0)]);
      final android = HapticPattern([TransientEvent(intensity: 0.5)]);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        HapticPattern.forPlatform(ios: ios, android: android),
        same(android),
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        HapticPattern.forPlatform(ios: ios, android: android),
        same(ios),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    test('forPlatform falls back to ios pattern when android omitted', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ios = HapticPattern([TransientEvent(intensity: 1.0)]);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(HapticPattern.forPlatform(ios: ios), same(ios));
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('HapticSupport', () {
    test('reports the platform result', () async {
      FlutterHaptics.debugResetSupportCache();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'support') return null;
        return {'fidelity': 'full', 'continuous': true};
      });

      final support = await FlutterHaptics.support;

      expect(support.fidelity, HapticFidelity.full);
      expect(support.supportsContinuous, isTrue);
      expect(support.supportsSharpness, isTrue);
      expect(support.supportsIntensity, isTrue);
      expect(await FlutterHaptics.isSupported, isTrue);
    });

    test('is queried once and cached', () async {
      FlutterHaptics.debugResetSupportCache();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'support') calls++;
        return {'fidelity': 'rhythm', 'continuous': true};
      });

      await FlutterHaptics.support;
      await FlutterHaptics.support;

      expect(calls, 1);
    });

    test('falls back to unsupported when the platform has no implementation',
        () async {
      FlutterHaptics.debugResetSupportCache();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException('no implementation');
      });

      final support = await FlutterHaptics.support;

      expect(support, HapticSupport.unsupported);
      expect(support.isSupported, isFalse);
      expect(await FlutterHaptics.isSupported, isFalse);
    });

    test('an unrecognised fidelity reads as unsupported', () {
      expect(
        HapticSupport.fromMap({'fidelity': 'quantum', 'continuous': true}),
        HapticSupport.unsupported,
      );
    });

    test('rhythm keeps neither intensity nor sharpness', () {
      const support = HapticSupport(
        fidelity: HapticFidelity.rhythm,
        supportsContinuous: true,
      );

      expect(support.isSupported, isTrue);
      expect(support.supportsIntensity, isFalse);
      expect(support.supportsSharpness, isFalse);
    });
  });

  group('FlutterHaptics.enabled', () {
    tearDown(() => FlutterHaptics.enabled = true);

    test('play is a no-op while disabled', () async {
      FlutterHaptics.enabled = false;

      await FlutterHaptics.play(HapticPatterns.success);

      expect(log, isEmpty);
    });

    test('stop still works while disabled', () async {
      FlutterHaptics.enabled = false;

      await FlutterHaptics.stop();

      expect(log.single.method, 'stop');
    });

    test('re-enabling restores playback', () async {
      FlutterHaptics.enabled = false;
      await FlutterHaptics.play(HapticPatterns.success);
      FlutterHaptics.enabled = true;
      await FlutterHaptics.play(HapticPatterns.success);

      expect(log.single.method, 'play');
    });
  });

  group('HapticEvent', () {
    test('TransientEvent toMap produces correct format', () {
      final event = TransientEvent(
        intensity: 0.8,
        sharpness: 0.6,
        delay: Duration(milliseconds: 100),
      );

      final map = event.toMap();

      expect(map['type'], 'transient');
      expect(map['intensity'], 0.8);
      expect(map['sharpness'], 0.6);
      expect(map['delayMs'], 100);
    });

    test('ContinuousEvent toMap produces correct format', () {
      final event = ContinuousEvent(
        intensity: 0.7,
        sharpness: 0.5,
        duration: Duration(milliseconds: 200),
        delay: Duration(milliseconds: 50),
      );

      final map = event.toMap();

      expect(map['type'], 'continuous');
      expect(map['durationMs'], 200);
      expect(map['delayMs'], 50);
      expect(map['intensityCurve'], isA<List>());
      expect(map['sharpnessCurve'], isA<List>());
    });

    test('ContinuousEvent.curved with HapticParam.fadeOut', () {
      final event = ContinuousEvent.curved(
        intensity: HapticParam.fadeOut,
        duration: Duration(milliseconds: 300),
      );

      final map = event.toMap();
      final curve = map['intensityCurve'] as List;

      expect(curve.first['value'], 1.0);
      expect(curve.last['value'], 0.0);
    });
  });

  group('HapticPatternBuilder', () {
    test('builds pattern with taps and waits', () {
      final pattern = HapticPatternBuilder()
          .tap(intensity: 0.5)
          .waitMs(50)
          .tap(intensity: 1.0)
          .build();

      expect(pattern.events, hasLength(2));

      final first = pattern.events[0] as TransientEvent;
      final second = pattern.events[1] as TransientEvent;

      // The wait is a gap *after* the first tap, so the second lands at the
      // tap's width plus the wait.
      expect(first.delay, Duration.zero);
      expect(second.delay, Duration(milliseconds: 75));
    });

    test('consecutive taps land on separate instants', () {
      final pattern =
          HapticPatternBuilder().tap().tap().tap().build();

      final delays =
          pattern.events.map((e) => (e as TransientEvent).delay).toList();

      expect(delays, [
        Duration.zero,
        HapticEvent.transientWidth,
        HapticEvent.transientWidth * 2,
      ]);
      expect(delays.toSet(), hasLength(3));
    });

    test('builds pattern with rumble', () {
      final pattern = HapticPatternBuilder()
          .rumble(duration: Duration(milliseconds: 100), intensity: 0.6)
          .build();

      expect(pattern.events, hasLength(1));
      expect(pattern.events.first, isA<ContinuousEvent>());
    });
  });
}
