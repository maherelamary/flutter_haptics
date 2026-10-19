import 'package:flutter/foundation.dart';

import 'haptic_param.dart';

/// Base type for all haptic events.
@immutable
sealed class HapticEvent {
  const HapticEvent();

  /// Nominal width of a transient event.
  ///
  /// A transient has no duration of its own — Core Haptics and Android's
  /// composition primitives each decide how long a tap actually lasts.
  /// Composition still needs a number: without one, [HapticPattern.duration]
  /// would report the *start* of a closing tap, and `then`/`repeat` would
  /// stack the next event straight on top of it.
  ///
  /// 25 ms is the width the Android waveform renderer already samples a
  /// transient at, so a pattern's duration in Dart agrees with what Android
  /// plays.
  static const transientWidth = Duration(milliseconds: 25);

  /// Offset of the start of this event from the start of the pattern.
  Duration get start;

  /// Offset of the end of this event from the start of the pattern.
  ///
  /// For a transient this is [start] plus [transientWidth]; a transient is a
  /// point in the native APIs but occupies real time on the actuator.
  Duration get end;

  /// Shift this event forward in time.
  HapticEvent delayed(Duration offset);

  /// Scale the intensity of this event.
  HapticEvent scaled(double factor);

  /// Convert to native format for method channel.
  Map<String, dynamic> toMap();
}

/// A sharp, instantaneous haptic (tap, click, impact).
@immutable
final class TransientEvent extends HapticEvent {
  /// Intensity of the haptic. Range: 0.0 to 1.0.
  final double intensity;

  /// Sharpness of the haptic. Range: 0.0 (dull) to 1.0 (sharp).
  final double sharpness;

  /// Delay from the start of the pattern.
  final Duration delay;

  const TransientEvent({
    required this.intensity,
    this.sharpness = 0.5,
    this.delay = Duration.zero,
  });

  @override
  Duration get start => delay;

  @override
  Duration get end => delay + HapticEvent.transientWidth;

  @override
  TransientEvent delayed(Duration offset) => TransientEvent(
        intensity: intensity,
        sharpness: sharpness,
        delay: delay + offset,
      );

  @override
  TransientEvent scaled(double factor) => TransientEvent(
        intensity: (intensity * factor).clamp(0.0, 1.0),
        sharpness: sharpness,
        delay: delay,
      );

  @override
  Map<String, dynamic> toMap() => {
        'type': 'transient',
        'intensity': intensity,
        'sharpness': sharpness,
        'delayMs': delay.inMilliseconds,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransientEvent &&
          intensity == other.intensity &&
          sharpness == other.sharpness &&
          delay == other.delay;

  @override
  int get hashCode => Object.hash(intensity, sharpness, delay);
}

/// A sustained haptic (rumble, vibration) with constant parameters.
@immutable
final class ContinuousEvent extends HapticEvent {
  /// Intensity parameter (constant or curved).
  final HapticParam intensity;

  /// Sharpness parameter (constant or curved).
  final HapticParam sharpness;

  /// Duration of the continuous haptic.
  final Duration duration;

  /// Delay from the start of the pattern.
  final Duration delay;

  /// Creates a continuous event with constant intensity and sharpness.
  ContinuousEvent({
    required double intensity,
    required this.duration,
    double sharpness = 0.5,
    this.delay = Duration.zero,
  })  : intensity = ConstantParam(intensity),
        sharpness = ConstantParam(sharpness);

  /// Creates a continuous event with curved intensity and/or sharpness.
  const ContinuousEvent.curved({
    required this.intensity,
    required this.duration,
    this.sharpness = const ConstantParam(0.5),
    this.delay = Duration.zero,
  });

  /// Internal constructor for transformations.
  const ContinuousEvent._({
    required this.intensity,
    required this.sharpness,
    required this.duration,
    required this.delay,
  });

  @override
  Duration get start => delay;

  @override
  Duration get end => delay + duration;

  @override
  ContinuousEvent delayed(Duration offset) => ContinuousEvent._(
        intensity: intensity,
        sharpness: sharpness,
        duration: duration,
        delay: delay + offset,
      );

  @override
  ContinuousEvent scaled(double factor) {
    // Scale intensity curve
    final scaledIntensity = switch (intensity) {
      ConstantParam(value: final v) =>
        ConstantParam((v * factor).clamp(0.0, 1.0)),
      LinearParam(from: final f, to: final t) => LinearParam(
          from: (f * factor).clamp(0.0, 1.0),
          to: (t * factor).clamp(0.0, 1.0),
        ),
      CurveParam(points: final pts) => CurveParam(
          pts.map((p) => (p.$1, (p.$2 * factor).clamp(0.0, 1.0))).toList(),
        ),
    };

    return ContinuousEvent._(
      intensity: scaledIntensity,
      sharpness: sharpness,
      duration: duration,
      delay: delay,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
        'type': 'continuous',
        'intensityCurve': intensity.toControlPoints(),
        'sharpnessCurve': sharpness.toControlPoints(),
        'durationMs': duration.inMilliseconds,
        'delayMs': delay.inMilliseconds,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContinuousEvent &&
          intensity == other.intensity &&
          sharpness == other.sharpness &&
          duration == other.duration &&
          delay == other.delay;

  @override
  int get hashCode => Object.hash(intensity, sharpness, duration, delay);
}
