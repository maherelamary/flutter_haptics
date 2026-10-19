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

    test('control point times are absolute, not relative to the curve', () {
      // The curve starts at 2.0s and its points run 2.0 -> 3.0 in absolute
      // pattern time. Normalised onto a 1s event that is 0.0 -> 1.0.
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
                { "Time": 2.0, "ParameterValue": 0.2 },
                { "Time": 2.5, "ParameterValue": 0.9 },
                { "Time": 3.0, "ParameterValue": 0.0 }
              ] } }
        ]
      }''');

      final event = pattern.events.single as ContinuousEvent;
      final points = event.intensity.toControlPoints();

      expect(points.map((p) => p['time']), [0.0, 0.5, 1.0]);
      expect(points.map((p) => p['value']), [0.2, 0.9, 0.0]);
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

    test('curve control point times are absolute', () {
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

      expect(curve['Time'], 2.0);
      expect(
        (curve['ParameterCurveControlPoints'] as List)
            .cast<Map>()
            .map((p) => p['Time']),
        [2.0, 3.0],
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
