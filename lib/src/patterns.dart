import 'haptic_event.dart';
import 'haptic_param.dart';
import 'haptic_pattern.dart';

/// Built-in haptic pattern library.
///
/// These patterns can be used directly or composed to create custom patterns.
abstract final class HapticPatterns {
  // ─────────────────────────────────────────────────────────────────
  // Simple taps
  // ─────────────────────────────────────────────────────────────────

  /// Light tap - subtle feedback.
  static const lightTap = HapticPattern([
    TransientEvent(intensity: 0.4, sharpness: 0.5),
  ]);

  /// Medium tap - standard feedback.
  static const mediumTap = HapticPattern([
    TransientEvent(intensity: 0.7, sharpness: 0.5),
  ]);

  /// Heavy tap - strong feedback.
  static const heavyTap = HapticPattern([
    TransientEvent(intensity: 1.0, sharpness: 0.5),
  ]);

  // ─────────────────────────────────────────────────────────────────
  // Feel variations
  // ─────────────────────────────────────────────────────────────────

  /// Soft tap - dull, cushioned feel.
  static const soft = HapticPattern([
    TransientEvent(intensity: 0.7, sharpness: 0.2),
  ]);

  /// Rigid tap - sharp, mechanical feel.
  static const rigid = HapticPattern([
    TransientEvent(intensity: 0.7, sharpness: 1.0),
  ]);

  // ─────────────────────────────────────────────────────────────────
  // UI feedback
  // ─────────────────────────────────────────────────────────────────

  /// Selection changed feedback.
  static const selection = HapticPattern([
    TransientEvent(intensity: 0.5, sharpness: 0.8),
  ]);

  /// Double click/tap pattern.
  static const doubleClick = HapticPattern([
    TransientEvent(intensity: 0.7, sharpness: 0.6),
    TransientEvent(
      intensity: 0.7,
      sharpness: 0.6,
      delay: Duration(milliseconds: 100),
    ),
  ]);

  /// Triple click/tap pattern.
  static const tripleClick = HapticPattern([
    TransientEvent(intensity: 0.6, sharpness: 0.6),
    TransientEvent(
      intensity: 0.7,
      sharpness: 0.6,
      delay: Duration(milliseconds: 80),
    ),
    TransientEvent(
      intensity: 0.8,
      sharpness: 0.6,
      delay: Duration(milliseconds: 160),
    ),
  ]);

  // ─────────────────────────────────────────────────────────────────
  // Notifications
  // ─────────────────────────────────────────────────────────────────

  /// Success notification - ascending intensity.
  static const success = HapticPattern([
    TransientEvent(intensity: 0.5, sharpness: 0.5),
    TransientEvent(
      intensity: 0.7,
      sharpness: 0.6,
      delay: Duration(milliseconds: 80),
    ),
    TransientEvent(
      intensity: 1.0,
      sharpness: 0.8,
      delay: Duration(milliseconds: 160),
    ),
  ]);

  /// Warning notification - attention-grabbing.
  static const warning = HapticPattern([
    TransientEvent(intensity: 0.8, sharpness: 0.6),
    TransientEvent(
      intensity: 0.6,
      sharpness: 0.4,
      delay: Duration(milliseconds: 120),
    ),
  ]);

  /// Error notification - strong, distinctive.
  static const error = HapticPattern([
    TransientEvent(intensity: 1.0, sharpness: 0.8),
    TransientEvent(
      intensity: 0.8,
      sharpness: 0.6,
      delay: Duration(milliseconds: 100),
    ),
    TransientEvent(
      intensity: 1.0,
      sharpness: 0.8,
      delay: Duration(milliseconds: 200),
    ),
  ]);

  // ─────────────────────────────────────────────────────────────────
  // Expressive patterns
  // ─────────────────────────────────────────────────────────────────

  /// Heartbeat - two-beat pulse like a heart.
  static const heartbeat = HapticPattern([
    TransientEvent(intensity: 0.6, sharpness: 0.3),
    TransientEvent(
      intensity: 0.9,
      sharpness: 0.5,
      delay: Duration(milliseconds: 130),
    ),
  ]);

  /// Buzz - short vibration.
  static final buzz = HapticPattern([
    ContinuousEvent(
      intensity: 0.6,
      sharpness: 0.5,
      duration: Duration(milliseconds: 100),
    ),
  ]);

  /// Long buzz - extended vibration.
  static final longBuzz = HapticPattern([
    ContinuousEvent(
      intensity: 0.6,
      sharpness: 0.5,
      duration: Duration(milliseconds: 300),
    ),
  ]);

  // ─────────────────────────────────────────────────────────────────
  // Curved patterns (using parameter curves)
  // ─────────────────────────────────────────────────────────────────

  /// Explosion - strong impact that fades out.
  static const explosion = HapticPattern([
    ContinuousEvent.curved(
      intensity: HapticParam.fadeOut,
      sharpness: ConstantParam(0.7),
      duration: Duration(milliseconds: 400),
    ),
  ]);

  /// Engine rev - builds up intensity.
  static const engineRev = HapticPattern([
    ContinuousEvent.curved(
      intensity: HapticParam.rampUp,
      sharpness: LinearParam(from: 0.3, to: 0.8),
      duration: Duration(milliseconds: 600),
    ),
  ]);

  /// Pulse wave - rises and falls.
  static const pulseWave = HapticPattern([
    ContinuousEvent.curved(
      intensity: HapticParam.pulse,
      sharpness: ConstantParam(0.5),
      duration: Duration(milliseconds: 400),
    ),
  ]);

  /// Impact with decay - sharp hit that fades.
  static const impactDecay = HapticPattern([
    TransientEvent(intensity: 1.0, sharpness: 0.9),
    ContinuousEvent.curved(
      intensity: HapticParam.fadeOut,
      sharpness: ConstantParam(0.4),
      duration: Duration(milliseconds: 200),
      delay: Duration.zero,
    ),
  ]);

  /// Charging up - intensity builds to a peak.
  static const chargeUp = HapticPattern([
    ContinuousEvent.curved(
      intensity: CurveParam([
        (0.0, 0.1),
        (0.7, 0.5),
        (0.9, 0.8),
        (1.0, 1.0),
      ]),
      sharpness: LinearParam(from: 0.3, to: 0.9),
      duration: Duration(milliseconds: 800),
    ),
  ]);
}
