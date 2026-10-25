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
/// - **Control point times are relative to the curve's own `Time`**, the
///   same as the `CHHapticParameterCurve` API. Apple's own authored files
///   show it plainly: a curve at `"Time": 1.207` carries control points
///   starting at `0.0`. A curve that starts at zero reads identically under
///   either convention, which is how the opposite belief survives so easily.
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
  /// already running when it starts. An event is no longer running at its
  /// own end: a curve starting there belongs to whatever starts there, and
  /// claiming it would hand a flat rumble the shape of the one after it.
  /// AHAP dynamic parameters are global in principle, but every tool that
  /// writes them pairs a curve with the event it shapes, and this package has
  /// nowhere to put a truly global one.
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
        candidates.firstWhereOrNull(
            (c) => c.time >= start && c.time < end && !_near(c.time, end));

    if (curve == null || curve.points.isEmpty) {
      return ConstantParam(fallback.clamp(0.0, 1.0));
    }

    final points = <(double, double)>[];
    for (final point in curve.points) {
      // A control point's time is measured from the curve's own `Time`, so
      // its place in the pattern is the two added together. Normalised onto
      // the event's span from there. Rounded because the subtract-then-
      // divide leaves float noise that would otherwise show up as a control
      // point at 0.9999999999999999.
      final at = curve.time + point.$1;
      final fraction = _round(((at - start) / duration).clamp(0.0, 1.0));
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
    // Curves are built first so that a reset can be skipped where another
    // curve for the same parameter begins at the same instant — two of them
    // at one moment have no defined winner.
    final curves = <int, Map<String, Map<String, Object?>>>{};
    // Every curve's span per parameter, so a reset can tell whether that
    // parameter is still being driven by something else when it lands.
    final curveSpans = <String, List<({double start, double end})>>{};

    for (var i = 0; i < pattern.events.length; i++) {
      final event = pattern.events[i];
      if (event is! ContinuousEvent) continue;

      final start = _toSeconds(event.delay);
      final built = <String, Map<String, Object?>>{};

      for (final (id, param) in [
        ('HapticIntensityControl', event.intensity),
        ('HapticSharpnessControl', event.sharpness),
      ]) {
        final curve = _encodeCurve(
          param,
          parameterId: id,
          start: start,
          duration: _toSeconds(event.duration),
        );
        if (curve == null) continue;
        built[id] = curve;
        // `start` arrives rounded from _toSeconds; `end` is a sum of two
        // rounded values, which can bring the noise back, so it rounds
        // again — as the reset time it is compared against does. Without
        // that, an end of 0.6000000000000001 swallows the reset at 0.6 that
        // should have followed it.
        (curveSpans[id] ??= []).add(
          (start: start, end: _round(start + _toSeconds(event.duration))),
        );
      }

      if (built.isNotEmpty) curves[i] = built;
    }

    final entries = <Map<String, Object?>>[];

    for (var i = 0; i < pattern.events.length; i++) {
      final event = pattern.events[i];
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
          final built = curves[i] ?? const {};
          final intensity = built['HapticIntensityControl'];
          final sharpness = built['HapticSharpnessControl'];

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

          // A dynamic parameter is not tied to the event it was written for:
          // it modulates every event in the pattern from the moment it is
          // delivered. Without these resets, a curve that fades to zero
          // silences whatever comes after it, and a tap overlapping a rumble
          // plays at the curve's current value. Putting each parameter back
          // to neutral stops it where the rumble ends. It cannot be
          // stopped *during* the rumble — the format has no per-event
          // curves — so a tap overlapping one is still modulated by it.
          for (final (id, neutral) in [
            if (intensity != null) ('HapticIntensityControl', 1.0),
            if (sharpness != null) ('HapticSharpnessControl', 0.0),
          ]) {
            final at = _round(start + duration);

            // Only written where nothing else is driving this parameter. A
            // curve that begins exactly here would be fighting the reset for
            // one instant with no defined winner, and a curve still running
            // here — an overlapping rumble — would have the reset cut
            // through the middle of it. The event's own curve ends at `at`,
            // so the half-open test does not match it.
            final busy = curveSpans[id]
                    ?.any((span) => span.start <= at && at < span.end) ??
                false;
            if (busy) continue;
            entries.add({
              'Parameter': {
                'ParameterID': id,
                'ParameterValue': neutral,
                'Time': at,
              },
            });
          }
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
            // Measured from this curve's own `Time`, which is `start`.
            'Time': _round(point['time']! * duration),
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

/// One `ParameterCurve` entry. Its control point times are measured from
/// the curve's own [time], the way the format and the API both express them.
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

    // A curve that is neutral all the way through is a reset, not a shape:
    // it exists to undo an earlier curve, which is how a writer that has
    // only pattern-wide parameters stops one event's curve leaking onto the
    // next. Claiming it for an event would hide that event's own curve.
    final neutral = switch (id) {
      'HapticIntensityControl' => 1.0,
      'HapticSharpnessControl' => 0.0,
      _ => null,
    };
    if (neutral != null && points.every((p) => Ahap._near(p.$2, neutral))) {
      return null;
    }

    // A missing key takes the field's default, and `Time` defaults to zero.
    // Falling back to the first control point's time would have been the
    // absolute reading of it, and points are relative. Read rather than
    // cast: a file with `"Time": "0.5"` used to throw a TypeError, which
    // callers catching FormatException never saw.
    return _Curve(
      parameterId: id,
      time: Ahap._asDouble(map['Time']) ?? 0,
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
