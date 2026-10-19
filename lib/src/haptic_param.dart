import 'package:flutter/foundation.dart';

/// Represents a haptic parameter (intensity or sharpness) that can be
/// constant or vary over time using curves.
@immutable
sealed class HapticParam {
  const HapticParam();

  /// Constant value throughout the event duration.
  const factory HapticParam.constant(double value) = ConstantParam;

  /// Linear interpolation from one value to another.
  const factory HapticParam.linear({
    required double from,
    required double to,
  }) = LinearParam;

  /// Custom curve with control points.
  /// Each point is (relativeTime, value) where:
  /// - relativeTime: 0.0 to 1.0 (percentage of event duration)
  /// - value: 0.0 to 1.0 (parameter intensity)
  const factory HapticParam.curve(
    List<(double time, double value)> points,
  ) = CurveParam;

  // ─────────────────────────────────────────────────────────────────
  // Presets
  // ─────────────────────────────────────────────────────────────────

  /// Fade in from silence to full intensity.
  static const fadeIn = LinearParam(from: 0.0, to: 1.0);

  /// Fade out from full intensity to silence.
  static const fadeOut = LinearParam(from: 1.0, to: 0.0);

  /// Ramp up from soft to full intensity.
  static const rampUp = LinearParam(from: 0.3, to: 1.0);

  /// Ramp down from full to soft intensity.
  static const rampDown = LinearParam(from: 1.0, to: 0.3);

  /// Pulse: starts silent, peaks in middle, ends silent.
  static const pulse = CurveParam([
    (0.0, 0.0),
    (0.5, 1.0),
    (1.0, 0.0),
  ]);

  /// Spike: quick rise to peak, long fade out.
  static const spike = CurveParam([
    (0.0, 0.0),
    (0.15, 1.0),
    (1.0, 0.0),
  ]);

  /// Convert to native format (list of control points).
  List<Map<String, double>> toControlPoints();
}

/// Constant parameter value.
@immutable
final class ConstantParam extends HapticParam {
  final double value;

  const ConstantParam(this.value);

  @override
  List<Map<String, double>> toControlPoints() => [
        {'time': 0.0, 'value': value},
        {'time': 1.0, 'value': value},
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ConstantParam && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Linear interpolation parameter.
@immutable
final class LinearParam extends HapticParam {
  final double from;
  final double to;

  const LinearParam({required this.from, required this.to});

  @override
  List<Map<String, double>> toControlPoints() => [
        {'time': 0.0, 'value': from},
        {'time': 1.0, 'value': to},
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinearParam && from == other.from && to == other.to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Custom curve parameter with multiple control points.
@immutable
final class CurveParam extends HapticParam {
  final List<(double time, double value)> points;

  const CurveParam(this.points);

  @override
  List<Map<String, double>> toControlPoints() =>
      points.map((p) => {'time': p.$1, 'value': p.$2}).toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurveParam && listEquals(points, other.points);

  @override
  int get hashCode => Object.hashAll(points);
}
