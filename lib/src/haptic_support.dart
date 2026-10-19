import 'package:flutter/foundation.dart';

/// How much of a pattern survives on this device.
///
/// The levels are ordered: each one keeps everything the level below it keeps.
/// They describe the *best* a device can do — on Android the renderer is still
/// chosen per pattern, so a rumble may land a tier lower than a tap.
enum HapticFidelity {
  /// Nothing plays. No vibrator, no haptic hardware, or a platform without
  /// haptics at all. Calls still succeed silently.
  none,

  /// Timing only. Events play at whatever strength the actuator has;
  /// intensity and sharpness are both lost.
  rhythm,

  /// Intensity survives, sharpness does not. Curves arrive as a stepped
  /// approximation of their shape.
  intensity,

  /// Intensity, sharpness and parameter curves all survive. Core Haptics on
  /// iOS, `BasicEnvelopeBuilder` on Android 16 hardware.
  full;

  /// Whether this level keeps at least as much as [other].
  bool atLeast(HapticFidelity other) => index >= other.index;
}

/// What the current device can actually reproduce.
///
/// Read it through [FlutterHaptics.support]. Both platforms report into
/// the same vocabulary, so a caller never needs a platform check:
///
/// ```dart
/// final support = await FlutterHaptics.support;
///
/// // Hide the app's haptics setting where nothing can play.
/// if (!support.isSupported) hideHapticsToggle();
///
/// // Pick a pattern the hardware can actually render.
/// await FlutterHaptics.play(
///   support.supportsSharpness ? HapticPatterns.chargeUp : HapticPatterns.success,
/// );
/// ```
@immutable
final class HapticSupport {
  /// How much of a pattern survives on this device.
  final HapticFidelity fidelity;

  /// Whether a [ContinuousEvent] can sustain here.
  ///
  /// This is the one capability that does not fit on the [fidelity] ladder.
  /// Every Android vibrator can hold a buzz, even if only on/off. On iOS the
  /// UIKit fallback used by devices without Core Haptics plays taps and
  /// nothing else, so a rumble is dropped there.
  final bool supportsContinuous;

  const HapticSupport({
    required this.fidelity,
    required this.supportsContinuous,
  });

  /// Reported for devices with no haptic hardware, and for platforms where
  /// the plugin has no implementation.
  static const unsupported = HapticSupport(
    fidelity: HapticFidelity.none,
    supportsContinuous: false,
  );

  /// Whether anything at all will play.
  bool get isSupported => fidelity != HapticFidelity.none;

  /// Whether sharpness — the dull-to-crisp axis — reaches the actuator.
  bool get supportsSharpness => fidelity.atLeast(HapticFidelity.full);

  /// Whether per-event intensity reaches the actuator.
  bool get supportsIntensity => fidelity.atLeast(HapticFidelity.intensity);

  /// Reads the map sent by the platform. Anything unrecognised is treated as
  /// [unsupported], so a newer native side can never crash an older Dart one.
  factory HapticSupport.fromMap(Map<Object?, Object?> map) {
    final fidelity = switch (map['fidelity']) {
      'full' => HapticFidelity.full,
      'intensity' => HapticFidelity.intensity,
      'rhythm' => HapticFidelity.rhythm,
      _ => HapticFidelity.none,
    };

    if (fidelity == HapticFidelity.none) return unsupported;

    return HapticSupport(
      fidelity: fidelity,
      supportsContinuous: map['continuous'] == true,
    );
  }

  @override
  String toString() =>
      'HapticSupport(${fidelity.name}, continuous: $supportsContinuous)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HapticSupport &&
          fidelity == other.fidelity &&
          supportsContinuous == other.supportsContinuous;

  @override
  int get hashCode => Object.hash(fidelity, supportsContinuous);
}
