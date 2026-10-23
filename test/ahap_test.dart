import 'dart:convert';

import 'package:flutter_haptics/flutter_haptics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ahap.decode', () {
    test('reads a transient event', () {
      final pattern = Ahap.decode('''
      {
        "Version": 1,
        "Pattern": [
          { "Event": {
              "Time": 0.25,
              "EventType": "HapticTransient",
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 0.8 },
                { "ParameterID": "HapticSharpness", "ParameterValue": 0.3 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as TransientEvent;
      expect(event.delay, const Duration(milliseconds: 250));
      expect(event.intensity, 0.8);
      expect(event.sharpness, 0.3);
    });

    test('reads a continuous event with no curve as a constant', () {
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 0,
              "EventType": "HapticContinuous",
              "EventDuration": 0.5,
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 0.6 },
                { "ParameterID": "HapticSharpness", "ParameterValue": 0.4 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      expect(event.duration, const Duration(milliseconds: 500));
      expect(event.intensity, const ConstantParam(0.6));
      expect(event.sharpness, const ConstantParam(0.4));
    });

    test('control point times are relative to the curve, as Apple writes them',
        () {
      // Apple's own authored AHAP does exactly this: a curve at Time 1.207
      // carrying control points that start at 0.0. Read as absolute, these
      // points land before the event and collapse to a single value.
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 2.0,
              "EventType": "HapticContinuous",
              "EventDuration": 1.0,
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 }
              ] } },
          { "ParameterCurve": {
              "ParameterID": "HapticIntensityControl",
              "Time": 2.0,
              "ParameterCurveControlPoints": [
                { "Time": 0.0, "ParameterValue": 0.2 },
                { "Time": 0.5, "ParameterValue": 0.9 },
                { "Time": 1.0, "ParameterValue": 0.0 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      final points = event.intensity.toControlPoints();

      expect(points.map((p) => p['time']), [0.0, 0.5, 1.0]);
      expect(points.map((p) => p['value']), [0.2, 0.9, 0.0]);
    });

    test('a curve claimed by an already-running event keeps its offset', () {
      // The curve starts half a second into a two-second rumble, so its
      // points land in the second half of the event rather than across it.
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 0.0,
              "EventType": "HapticContinuous",
              "EventDuration": 2.0,
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 }
              ] } },
          { "ParameterCurve": {
              "ParameterID": "HapticIntensityControl",
              "Time": 1.0,
              "ParameterCurveControlPoints": [
                { "Time": 0.0, "ParameterValue": 1.0 },
                { "Time": 1.0, "ParameterValue": 0.0 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      expect(event.intensity.toControlPoints().map((p) => p['time']),
          [0.5, 1.0]);
    });

    test('a curve with no Time starts at zero, not at its first point', () {
      // A missing key takes its default, and Time defaults to 0. Falling
      // back to the first point's time is the absolute reading.
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 0.0,
              "EventType": "HapticContinuous",
              "EventDuration": 2.0,
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 }
              ] } },
          { "ParameterCurve": {
              "ParameterID": "HapticIntensityControl",
              "ParameterCurveControlPoints": [
                { "Time": 1.0, "ParameterValue": 1.0 },
                { "Time": 2.0, "ParameterValue": 0.0 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      expect(event.intensity.toControlPoints().map((p) => p['time']),
          [0.5, 1.0]);
    });

    test('numbers written as strings are read, not skipped', () {
      // Exported AHAP in the wild quotes numbers. Casting threw a TypeError,
      // which a caller catching FormatException never saw — and merely not
      // throwing would have dropped the values instead.
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": "0.5",
              "EventType": "HapticContinuous",
              "EventDuration": "1.0",
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": "1.0" }
              ] } },
          { "ParameterCurve": {
              "ParameterID": "HapticIntensityControl",
              "Time": "0.5",
              "ParameterCurveControlPoints": [
                { "Time": "0.5", "ParameterValue": "0.2" },
                { "Time": "1.5", "ParameterValue": "1.0" }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      expect(event.delay, const Duration(milliseconds: 500));
      expect(event.duration, const Duration(seconds: 1));
      expect(
        event.intensity.toControlPoints().map((p) => p['value']),
        [0.2, 1.0],
      );
    });

    test('NaN and the infinities are read as absent, not carried', () {
      // Each of these parses to a double that throws UnsupportedError out of
      // Duration's .round() — invisible to a caller catching
      // FormatException. `1e400` is a legal JSON number literal, so this is
      // not only about quoted values.
      for (final time in ['"NaN"', '"Infinity"', '1e400', '"1e400"']) {
        HapticPattern decode() => Ahap.decode('''
        {
          "Pattern": [
            { "Event": {
                "Time": $time,
                "EventType": "HapticTransient",
                "EventParameters": [
                  { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 }
                ] } }
          ]
        }''');

        expect(decode, returnsNormally, reason: 'Time was $time');
        // Unreadable means absent, so the event lands at AHAP's own default.
        final event = decode().events.single as TransientEvent;
        expect(event.delay, Duration.zero, reason: time);
      }
    });

    test('a continuous event with a non-finite duration is skipped', () {
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 0,
              "EventType": "HapticContinuous",
              "EventDuration": "Infinity",
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 }
              ] } }
        ]
      }''');

      expect(pattern.events, isEmpty);
    });

    test('a curve whose Time is unreadable starts at zero', () {
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 0,
              "EventType": "HapticContinuous",
              "EventDuration": 1.0,
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 }
              ] } },
          { "ParameterCurve": {
              "ParameterID": "HapticIntensityControl",
              "Time": "not a number",
              "ParameterCurveControlPoints": [
                { "Time": 0.0, "ParameterValue": 0.2 },
                { "Time": 1.0, "ParameterValue": 1.0 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      expect(
        event.intensity.toControlPoints().map((p) => p['value']),
        [0.2, 1.0],
      );
    });

    test('intensity control multiplies the event intensity', () {
      // Event intensity 0.5, curve peaking at 1.0 -> effective peak 0.5.
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 0, "EventType": "HapticContinuous", "EventDuration": 1.0,
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 0.5 }
              ] } },
          { "ParameterCurve": {
              "ParameterID": "HapticIntensityControl", "Time": 0,
              "ParameterCurveControlPoints": [
                { "Time": 0.0, "ParameterValue": 0.0 },
                { "Time": 1.0, "ParameterValue": 1.0 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      expect(event.intensity.toControlPoints().map((p) => p['value']), [0.0, 0.5]);
    });

    test('sharpness control offsets the event sharpness', () {
      // Event sharpness 0.5 with an offset curve of -0.5 -> 0.5 gives 0.0 -> 1.0.
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 0, "EventType": "HapticContinuous", "EventDuration": 1.0,
              "EventParameters": [
                { "ParameterID": "HapticSharpness", "ParameterValue": 0.5 }
              ] } },
          { "ParameterCurve": {
              "ParameterID": "HapticSharpnessControl", "Time": 0,
              "ParameterCurveControlPoints": [
                { "Time": 0.0, "ParameterValue": -0.5 },
                { "Time": 1.0, "ParameterValue": 0.5 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      expect(event.sharpness.toControlPoints().map((p) => p['value']), [0.0, 1.0]);
    });

    test('a neutral curve is a reset, and is not claimed by an event', () {
      // How a writer with only pattern-wide parameters undoes an earlier
      // curve. Read as a shape, it would mask the event's own curve.
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": {
              "Time": 1.0,
              "EventType": "HapticContinuous",
              "EventDuration": 1.0,
              "EventParameters": [
                { "ParameterID": "HapticIntensity", "ParameterValue": 0.4 }
              ] } },
          { "ParameterCurve": {
              "ParameterID": "HapticIntensityControl",
              "Time": 1.0,
              "ParameterCurveControlPoints": [
                { "Time": 0.0, "ParameterValue": 1.0 },
                { "Time": 1.0, "ParameterValue": 1.0 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      expect(event.intensity, const ConstantParam(0.4),
          reason: 'the event keeps its own intensity');
    });

    test('audio events and standalone parameters are dropped', () {
      final pattern = Ahap.decode('''
      {
        "Pattern": [
          { "Event": { "Time": 0, "EventType": "AudioContinuous", "EventDuration": 1.0 } },
          { "Parameter": { "ParameterID": "HapticIntensityControl", "Time": 0, "ParameterValue": 0.5 } },
          { "Event": { "Time": 0, "EventType": "HapticTransient",
              "EventParameters": [ { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 } ] } }
        ]
      }''');

      expect(pattern.events, hasLength(1));
      expect(pattern.events.single, isA<TransientEvent>());
    });

    test('a continuous event with no duration is skipped', () {
      final pattern = Ahap.decode(
        '{"Pattern": [{"Event": {"Time": 0, "EventType": "HapticContinuous"}}]}',
      );
      expect(pattern.events, isEmpty);
    });

    test('rejects documents that are not AHAP', () {
      expect(() => Ahap.decode('not json'), throwsFormatException);
      expect(() => Ahap.decode('[1,2,3]'), throwsFormatException);
      expect(() => Ahap.decode('{"Version": 1}'), throwsFormatException);
    });
  });

  group('Ahap.encode', () {
    test('writes a transient event', () {
      final json = Ahap.encodeMap(
        const HapticPattern([
          TransientEvent(
            intensity: 0.8,
            sharpness: 0.3,
            delay: Duration(milliseconds: 250),
          ),
        ]),
      );

      final event = (json['Pattern'] as List).single as Map;
      expect(json['Version'], 1);
      expect((event['Event'] as Map)['Time'], 0.25);
      expect((event['Event'] as Map)['EventType'], 'HapticTransient');
    });

    test('a curved event gets neutral event parameters plus curves', () {
      final json = Ahap.encodeMap(HapticPatterns.explosion);
      final entries = (json['Pattern'] as List).cast<Map>();

      final event = entries.first['Event'] as Map;
      final parameters = (event['EventParameters'] as List).cast<Map>();
      final intensity = parameters
          .firstWhere((p) => p['ParameterID'] == 'HapticIntensity')['ParameterValue'];

      // Intensity control multiplies, so the event parameter must be 1.0 or
      // the curve would be applied twice.
      expect(intensity, 1.0);
      expect(entries.any((e) => e.containsKey('ParameterCurve')), isTrue);
    });

    test('a constant parameter is written on the event, with no curve', () {
      final json = Ahap.encodeMap(
        HapticPattern([
          ContinuousEvent(
            intensity: 0.6,
            sharpness: 0.4,
            duration: const Duration(milliseconds: 200),
          ),
        ]),
      );

      final entries = (json['Pattern'] as List).cast<Map>();
      expect(entries, hasLength(1));
      expect(entries.single.containsKey('ParameterCurve'), isFalse);

      final parameters =
          ((entries.single['Event'] as Map)['EventParameters'] as List).cast<Map>();
      expect(
        parameters.firstWhere((p) => p['ParameterID'] == 'HapticIntensity')['ParameterValue'],
        0.6,
      );
    });

    test('curve control point times are relative to the curve', () {
      final json = Ahap.encodeMap(
        HapticPattern([
          ContinuousEvent.curved(
            intensity: HapticParam.fadeOut,
            duration: const Duration(seconds: 1),
            delay: const Duration(seconds: 2),
          ),
        ]),
      );

      final curve = (json['Pattern'] as List)
          .cast<Map>()
          .firstWhere((e) => e.containsKey('ParameterCurve'))['ParameterCurve'] as Map;

      // The curve sits at 2.0s; its points run 0.0 -> 1.0 from there, not
      // 2.0 -> 3.0. Writing them absolute double-offsets the curve in any
      // Core Haptics player.
      expect(curve['Time'], 2.0);
      expect(
        (curve['ParameterCurveControlPoints'] as List)
            .cast<Map>()
            .map((p) => p['Time']),
        [0.0, 1.0],
      );
    });

    test('refuses a curve Core Haptics would silently truncate', () {
      final tooMany = CurveParam([
        for (var i = 0; i <= Ahap.maxControlPoints; i++)
          (i / Ahap.maxControlPoints, i.isEven ? 0.2 : 0.9),
      ]);

      expect(
        () => Ahap.encodeMap(
          HapticPattern([
            ContinuousEvent.curved(
              intensity: tooMany,
              duration: const Duration(seconds: 1),
            ),
          ]),
        ),
        throwsStateError,
      );
    });

    test('a curved rumble is followed by a reset to neutral', () {
      final json = Ahap.encodeMap(
        HapticPattern([
          ContinuousEvent.curved(
            intensity: HapticParam.fadeOut,
            sharpness: HapticParam.rampUp,
            duration: const Duration(milliseconds: 400),
          ),
          const TransientEvent(
            intensity: 1,
            sharpness: 1,
            delay: Duration(milliseconds: 600),
          ),
        ]),
      );

      final resets = (json['Pattern'] as List)
          .cast<Map>()
          .where((e) => e.containsKey('Parameter'))
          .map((e) => e['Parameter'] as Map)
          .toList();

      // Without these the tap at 600ms would play at the curve's last
      // value, which fadeOut leaves at zero: silent.
      expect(resets, hasLength(2));
      expect(
        resets.map((r) => (r['ParameterID'], r['ParameterValue'], r['Time'])),
        containsAll([
          ('HapticIntensityControl', 1.0, 0.4),
          ('HapticSharpnessControl', 0.0, 0.4),
        ]),
      );
    });

    test('no reset where another curve starts at that instant', () {
      // Back-to-back rumbles: the second curve takes over exactly where the
      // first ends, and two parameter writes at one moment have no defined
      // winner.
      final json = Ahap.encodeMap(
        HapticPattern([
          ContinuousEvent.curved(
            intensity: HapticParam.fadeOut,
            duration: const Duration(milliseconds: 400),
          ),
          ContinuousEvent.curved(
            intensity: HapticParam.fadeIn,
            duration: const Duration(milliseconds: 400),
            delay: const Duration(milliseconds: 400),
          ),
        ]),
      );

      final resets = (json['Pattern'] as List)
          .cast<Map>()
          .where((e) => e.containsKey('Parameter'))
          .map((e) => e['Parameter'] as Map)
          .toList();

      expect(resets, hasLength(1), reason: 'only the last one needs it');
      expect(resets.single['Time'], 0.8);
    });

    test('no reset while another curve is still running', () {
      // The first rumble ends halfway through the second. A reset there
      // would cut straight through the second rumble's curve, which is the
      // leak it was meant to prevent, pointed the other way.
      final json = Ahap.encodeMap(
        HapticPattern([
          ContinuousEvent.curved(
            intensity: HapticParam.fadeOut,
            duration: const Duration(milliseconds: 400),
          ),
          ContinuousEvent.curved(
            intensity: HapticParam.fadeIn,
            duration: const Duration(milliseconds: 400),
            delay: const Duration(milliseconds: 200),
          ),
        ]),
      );

      final resets = (json['Pattern'] as List)
          .cast<Map>()
          .where((e) => e.containsKey('Parameter'))
          .map((e) => e['Parameter'] as Map)
          .toList();

      expect(resets, hasLength(1), reason: 'only after the last curve ends');
      expect(resets.single['Time'], 0.6);
    });

    test('produces parseable JSON', () {
      final source = Ahap.encode(HapticPatterns.success, metadata: {'Project': 'demo'});
      final decoded = jsonDecode(source) as Map<String, Object?>;

      expect(decoded['Metadata'], {'Project': 'demo'});
      expect(decoded['Pattern'], isA<List>());
    });
  });

  group('round trip', () {
    /// Compares patterns by what actually reaches the platform, since a
    /// decoded curve is a CurveParam even where the original was a LinearParam.
    void expectSameShape(HapticPattern actual, HapticPattern expected) {
      expect(actual.events.length, expected.events.length);
      for (var i = 0; i < expected.events.length; i++) {
        expect(actual.events[i].toMap(), expected.events[i].toMap(), reason: 'event $i');
      }
    }

    for (final entry in <String, HapticPattern>{
      'success': HapticPatterns.success,
      'heartbeat': HapticPatterns.heartbeat,
      'explosion': HapticPatterns.explosion,
      'engineRev': HapticPatterns.engineRev,
      'pulseWave': HapticPatterns.pulseWave,
      'chargeUp': HapticPatterns.chargeUp,
      'impactDecay': HapticPatterns.impactDecay,
    }.entries) {
      test('${entry.key} survives encode then decode', () {
        expectSameShape(Ahap.decode(Ahap.encode(entry.value)), entry.value);
      });
    }

    test('a composed pattern survives', () {
      final pattern = HapticPatterns.success
          .then(HapticPatterns.explosion)
          .repeat(2, gap: const Duration(milliseconds: 100));

      expectSameShape(Ahap.decode(Ahap.encode(pattern)), pattern);
    });
  });
}
