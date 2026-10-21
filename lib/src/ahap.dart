import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'haptic_event.dart';
import 'haptic_param.dart';
import 'haptic_pattern.dart';

/// Reads and writes AHAP — Apple Haptic and Audio Pattern — the JSON format
/// Core Haptics loads with `CHHapticPattern(contentsOf:)`.
///
/// AHAP is what haptic design tools export, so this is the door into that
/// ecosystem: author a pattern in a designer, ship the `.ahap` as an asset,
/// and play it through the whole Android ladder rather than only on iOS.
///
/// ```dart
/// final pattern = await Ahap.loadAsset('assets/haptics/explosion.ahap');
/// await FlutterHaptics.play(pattern);
/// ```
///
/// It also doubles as pattern serialisation — [encode] of a pattern this
/// package built is a valid `.ahap`.
///
/// ## What crosses over
///
/// Transient and continuous haptic events, with their intensity and sharpness
/// parameter curves. Audio events (`AudioCustom`, `AudioContinuous`) and
/// standalone `Parameter` entries are **dropped**: this plugin plays haptics
/// only, and never attaches to the app's audio session.
///
/// ## Two details the format gets counter-intuitively
///
/// Both are handled here, and both are easy to get wrong by reading the
/// Core Haptics API instead of the file format:
///
/// - **Control point times are absolute**, measured from the start of the
///   pattern — not relative to the curve's own `Time`, which is how the
///   `CHHapticParameterCurve` *API* expresses them.
/// - **Curves modulate, they do not replace.** `HapticIntensityControl` is a
///   multiplier over the event's `HapticIntensity` (neutral 1.0), and
///   `HapticSharpnessControl` is an offset added to `HapticSharpness`
///   (neutral 0.0). Decoding folds the two together; encoding writes a
///   neutral event parameter whenever a curve carries the shape.
abstract final class Ahap {
  /// The `Version` written into encoded files.
  static const version = 1;

  /// Core Haptics silently ignores control points past the sixteenth in any
  /// one curve, so [encode] refuses to write a curve longer than this rather
  /// than emit a file that plays differently from the pattern it came from.
  static const maxControlPoints = 16;

  // ─────────────────────────────────────────────────────────────────
  // Decoding
  // ─────────────────────────────────────────────────────────────────

  /// Parses AHAP JSON into a pattern.
  ///
  /// Throws [FormatException] if the document is not valid AHAP. Unlike
  /// playback, which fails silently, a malformed asset is a mistake worth
  /// surfacing while you are building.
  static HapticPattern decode(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Not valid JSON: ${error.message}');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('AHAP root must be a JSON object.');
    }
    return decodeMap(json);
  }

  /// Loads an AHAP file from the asset bundle and parses it.
  static Future<HapticPattern> loadAsset(
    String key, {
    AssetBundle? bundle,
  }) async =>
      decode(await (bundle ?? rootBundle).loadString(key));

  /// Parses an already-decoded AHAP document.
  static HapticPattern decodeMap(Map<String, Object?> map) {
    final raw = map['Pattern'];
    if (raw is! List) {
      throw const FormatException('AHAP is missing its "Pattern" array.');
    }

    // Curves are collected first: a continuous event needs the curves that
    // point at it before it can be built.
    final curves = <_Curve>[];
    final events = <Map<String, Object?>>[];

    for (final entry in raw) {
      if (entry is! Map) continue;
      final event = entry['Event'];
      if (event is Map) {
        events.add(event.cast<String, Object?>());
        continue;
      }
      final curve = entry['ParameterCurve'];
      if (curve is Map) {
        final parsed = _Curve.parse(curve.cast<String, Object?>());
        if (parsed != null) curves.add(parsed);
      }
      // A standalone "Parameter" entry is a one-shot dynamic parameter with
      // no event of its own. Nothing in this package's model holds one.
    }

    final decoded = <HapticEvent>[];
    for (final event in events) {
      final built = _decodeEvent(event, curves);
      if (built != null) decoded.add(built);
    }

    return HapticPattern(List.unmodifiable(decoded));
  }

  static HapticEvent? _decodeEvent(
    Map<String, Object?> event,
    List<_Curve> curves,
  ) {
    final time = _seconds(event['Time']) ?? 0;
    final parameters = _eventParameters(event['EventParameters']);

    switch (event['EventType']) {
      case 'HapticTransient':
        return TransientEvent(
          intensity: (parameters['HapticIntensity'] ?? 1).clamp(0.0, 1.0),
          sharpness: (parameters['HapticSharpness'] ?? 0.5).clamp(0.0, 1.0),
          delay: _duration(time),
        );

      case 'HapticContinuous':
        final durationSeconds = _seconds(event['EventDuration']);
        if (durationSeconds == null || durationSeconds <= 0) return null;

        final baseIntensity = parameters['HapticIntensity'] ?? 1;
        final baseSharpness = parameters['HapticSharpness'] ?? 0.5;

        return ContinuousEvent.curved(
          intensity: _resolve(
            curves: curves,
            parameterId: 'HapticIntensityControl',
            start: time,
            duration: durationSeconds,
            base: baseIntensity,
            // Intensity control multiplies the event's own intensity.
            combine: (base, value) => base * value,
            fallback: baseIntensity,
          ),
          sharpness: _resolve(
            curves: curves,
            parameterId: 'HapticSharpnessControl',
            start: time,
            duration: durationSeconds,
            base: baseSharpness,
            // Sharpness control shifts the event's own sharpness.
            combine: (base, value) => base + value,
            fallback: baseSharpness,
          ),
          duration: _duration(durationSeconds),
          delay: _duration(time),
        );

      // Audio events are intentionally dropped — see the class docs.
      default:
        return null;
    }
  }

  /// Folds the curve that applies to this event into a [HapticParam].
  ///
  /// A curve is claimed by the event it starts on; failing that, by an event
  /// already running when it starts. AHAP dynamic parameters are global in
  /// principle, but every tool that writes them pairs a curve with the event
  /// it shapes, and this package has nowhere to put a truly global one.
  static HapticParam _resolve({
    required List<_Curve> curves,
    required String parameterId,
    required double start,
    required double duration,
    required double base,
    required double Function(double base, double value) combine,
    required double fallback,
  }) {
    final end = start + duration;
    final candidates = curves.where((c) => c.parameterId == parameterId);

    final curve = candidates.firstWhereOrNull((c) => _near(c.time, start)) ??
        candidates.firstWhereOrNull((c) => c.time >= start && c.time <= end);

    if (curve == null || curve.points.isEmpty) {
      return ConstantParam(fallback.clamp(0.0, 1.0));
    }

    final points = <(double, double)>[];
    for (final point in curve.points) {
      // Control point times are absolute; normalise onto the event's span.
      // Rounded because the subtract-then-divide leaves float noise that
      // would otherwise show up as a control point at 0.9999999999999999.
      final fraction = _round(((point.$1 - start) / duration).clamp(0.0, 1.0));
      final value = _round(combine(base, point.$2).clamp(0.0, 1.0));
      points.add((fraction, value));
    }

    final collapsed = points.map((p) => p.$2).toSet();
    if (collapsed.length == 1) return ConstantParam(collapsed.first);

    return CurveParam(List.unmodifiable(points));
  }

  // ─────────────────────────────────────────────────────────────────
  // Encoding
  // ─────────────────────────────────────────────────────────────────

  /// Serialises a pattern as AHAP JSON.
  ///
  /// The result is a valid `.ahap` that Core Haptics and third-party haptic
  /// tools can open. [metadata] is written verbatim into the file's
  /// `Metadata` object.
  ///
  /// Throws [StateError] if any curve exceeds [maxControlPoints], since Core
  /// Haptics would silently drop the extra points and play something other
  /// than the pattern given.
  static String encode(
    HapticPattern pattern, {
    Map<String, Object?>? metadata,
    bool pretty = true,
  }) {
    final map = encodeMap(pattern, metadata: metadata);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(map)
        : jsonEncode(map);
  }

  /// Builds the AHAP document for [pattern] without serialising it.
  static Map<String, Object?> encodeMap(
    HapticPattern pattern, {
    Map<String, Object?>? metadata,
  }) {
    final entries = <Map<String, Object?>>[];

    for (final event in pattern.events) {
      switch (event) {
        case TransientEvent():
          entries.add({
            'Event': {
              'Time': _toSeconds(event.delay),
              'EventType': 'HapticTransient',
              'EventParameters': [
                _parameter('HapticIntensity', event.intensity),
                _parameter('HapticSharpness', event.sharpness),
              ],
            },
          });

        case ContinuousEvent():
          final start = _toSeconds(event.delay);
          final duration = _toSeconds(event.duration);

          final intensity = _encodeCurve(
            event.intensity,
            parameterId: 'HapticIntensityControl',
            start: start,
            duration: duration,
          );
          final sharpness = _encodeCurve(
            event.sharpness,
            parameterId: 'HapticSharpnessControl',
            start: start,
            duration: duration,
          );

          entries.add({
            'Event': {
              'Time': start,
              'EventType': 'HapticContinuous',
              'EventDuration': duration,
              'EventParameters': [
                // Neutral where a curve carries the shape, so the two do not
                // compound — intensity control multiplies, sharpness offsets.
                _parameter(
                  'HapticIntensity',
                  intensity == null ? _constantOf(event.intensity) : 1.0,
                ),
                _parameter(
                  'HapticSharpness',
                  sharpness == null ? _constantOf(event.sharpness) : 0.0,
                ),
              ],
            },
          });
          if (intensity != null) entries.add({'ParameterCurve': intensity});
          if (sharpness != null) entries.add({'ParameterCurve': sharpness});
      }
    }

    return {
      'Version': version,
      if (metadata != null) 'Metadata': metadata,
      'Pattern': entries,
    };
  }

  /// Returns the curve dictionary, or null when the parameter is constant and
  /// the event parameter alone can carry it.
  static Map<String, Object?>? _encodeCurve(
    HapticParam param,
    {required String parameterId,
    required double start,
    required double duration}) {
    final points = param.toControlPoints();
    final values = points.map((p) => p['value']!).toSet();
    if (values.length <= 1) return null;

    if (points.length > maxControlPoints) {
      throw StateError(
        'A $parameterId curve has ${points.length} control points; Core '
        'Haptics ignores everything past $maxControlPoints. Simplify the '
        'curve before encoding it as AHAP.',
      );
    }

    return {
      'ParameterID': parameterId,
      'Time': start,
      'ParameterCurveControlPoints': [
        for (final point in points)
          {
            // Absolute, from the start of the pattern.
            'Time': _round(start + point['time']! * duration),
            'ParameterValue': _round(point['value']!),
          },
      ],
    };
  }

  static double _constantOf(HapticParam param) =>
      param.toControlPoints().first['value']!;

  static Map<String, Object?> _parameter(String id, double value) => {
        'ParameterID': id,
        'ParameterValue': _round(value.clamp(0.0, 1.0)),
      };

  // ─────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────

  static Map<String, double> _eventParameters(Object? raw) {
    final parameters = <String, double>{};
    if (raw is! List) return parameters;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = entry['ParameterID'];
      final value = entry['ParameterValue'];
      final parsed = _asDouble(value);
      if (id is String && parsed != null) parameters[id] = parsed;
    }
    return parameters;
  }

  static double? _seconds(Object? raw) => _asDouble(raw);

  /// Reads a number that may have been written as a string.
  ///
  /// AHAP is JSON, so every number in a hand-written or exported file is
  /// *meant* to be a JSON number — but quoted numbers turn up in the wild,
  /// and a file that is otherwise valid should not lose an event over a pair
  /// of quotes. Anything unreadable is `null`, and the caller decides whether
  /// that means a default or a skipped event.
  ///
  /// NaN and the infinities are unreadable too, from either form. JSON has no
  /// literal for them, but `"NaN"` parses to one and so does `1e400` — even
  /// unquoted, since `jsonDecode` yields `Infinity` for it. A non-finite
  /// number of seconds then throws `UnsupportedError` out of the `.round()`
  /// that builds a [Duration], which a caller catching [FormatException]
  /// would never see: the same class of surprise as the `TypeError` this
  /// helper replaced. Rejected here, such a value is simply absent, and the
  /// field's own default applies.
  static double? _asDouble(Object? raw) {
    final value = switch (raw) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value),
      _ => null,
    };
    return value != null && value.isFinite ? value : null;
  }

  /// AHAP counts in seconds; this package counts in [Duration].
  static Duration _duration(double seconds) =>
      Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

  static double _toSeconds(Duration duration) =>
      _round(duration.inMicroseconds / Duration.microsecondsPerSecond);

  /// Keeps the JSON readable and free of float noise like `0.30000000000000004`.
  static double _round(double value) =>
      double.parse(value.toStringAsFixed(6));

  static bool _near(double a, double b) => (a - b).abs() < 1e-6;
}

/// One `ParameterCurve` entry, with its control points in absolute seconds.
class _Curve {
  _Curve({
    required this.parameterId,
    required this.time,
    required this.points,
  });

  final String parameterId;
  final double time;
  final List<(double time, double value)> points;

  static _Curve? parse(Map<String, Object?> map) {
    final id = map['ParameterID'];
    if (id is! String) return null;

    final raw = map['ParameterCurveControlPoints'];
    if (raw is! List) return null;

    final points = <(double, double)>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final time = Ahap._asDouble(entry['Time']);
      final value = Ahap._asDouble(entry['ParameterValue']);
      if (time != null && value != null) points.add((time, value));
    }
    if (points.isEmpty) return null;
    points.sort((a, b) => a.$1.compareTo(b.$1));

    // A curve with no usable `Time` starts where its first point does, which
    // is where Core Haptics would put it anyway. Read rather than cast: a
    // file with `"Time": "0.5"` used to throw a TypeError, which callers
    // catching FormatException never saw.
    return _Curve(
      parameterId: id,
      time: Ahap._asDouble(map['Time']) ?? points.first.$1,
      points: points,
    );
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
