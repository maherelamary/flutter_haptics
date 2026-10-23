import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'haptic_intent.dart';
import 'haptic_pattern.dart';
import 'haptic_support.dart';
import 'system_haptic.dart';

/// What the platform did with one request.
///
/// Carries the reason rather than an error, because "this device cannot do
/// that" is an answer, not a fault. [FlutterHaptics.onFailure] decides whether
/// the reason is ignored, logged or thrown.
@immutable
class NativeResult {
  const NativeResult.played()
      : played = true,
        reason = '',
        registrationLost = false;

  const NativeResult.failed(this.reason, {this.registrationLost = false})
      : played = false;

  /// Whether a haptic actually reached the actuator.
  final bool played;

  /// Why it did not, in the platform's own terms — `requires API 34, device
  /// is 31`, `no vibrator on this device`. Empty when [played].
  final String reason;

  /// Whether the platform no longer holds the registration that was asked
  /// for, as opposed to holding it and failing to play it.
  ///
  /// Only ever set by [playRegistered]. The difference matters to a
  /// [HapticHandle]: a registration that is gone should be forgotten, while
  /// an engine that would not play this time should be tried again rather
  /// than costing the handle its registration for the rest of the session.
  final bool registrationLost;
}

/// The seam between [FlutterHaptics] and the device.
///
/// [FlutterHaptics] is a thin facade: it holds the policy — the app-wide
/// switch, empty patterns, intent resolution, the failure mode — and hands
/// everything else to [instance]. Swapping the instance makes every haptic
/// call an app makes observable without going near a method channel:
///
/// ```dart
/// import 'package:flutter_haptics/testing.dart';
///
/// final haptics = FakeHapticsPlatform();
///
/// setUp(() => FlutterHapticsPlatform.instance = haptics);
/// tearDown(FlutterHapticsPlatform.reset);
/// ```
///
/// This is deliberately *not* a federated `plugin_platform_interface`. There
/// are two platforms and one implementation of each; a package split would
/// cost a lockstep release every time and buy nothing this seam does not.
///
/// Nothing here throws. A device that cannot do something says so in a
/// [NativeResult], which is what lets the public API stay predictable.
abstract class FlutterHapticsPlatform {
  FlutterHapticsPlatform();

  /// The implementation every [FlutterHaptics] call goes through.
  ///
  /// Assign a substitute in a test, and call [reset] afterwards.
  static FlutterHapticsPlatform instance = MethodChannelHaptics();

  /// Restores the real, channel-backed implementation.
  static void reset() => instance = MethodChannelHaptics();

  /// What this device can reproduce. Reports [HapticSupport.unsupported]
  /// rather than throwing where there is no implementation.
  Future<HapticSupport> querySupport();

  /// Render a pattern through the synthesiser.
  Future<NativeResult> play(HapticPattern pattern);

  /// Play one of the platform's own constants.
  ///
  /// The caller has already checked that [haptic] belongs to this platform;
  /// the version check happens natively, where the answer is.
  ///
  /// [requirePerceptible] decides whether a device that may accept the
  /// constant without actually rendering it should be refused. `perform` sets
  /// it, because it carries a pattern that is known to work. `playSystem`
  /// does not: it was asked for this exact constant, and the vendor tuned it
  /// for this hardware.
  Future<NativeResult> playSystem(
    SystemHaptic haptic, {
    required bool requirePerceptible,
  });

  /// Prepare a pattern for replay, returning its id, or null when this
  /// platform cannot hold one.
  Future<int?> register(HapticPattern pattern);

  /// Replay a pattern prepared by [register].
  ///
  /// Reports a lost registration — a rebuilt engine, a detached plugin —
  /// rather than succeeding silently, which is what lets [HapticHandle] fall
  /// back to sending the pattern the long way.
  Future<NativeResult> playRegistered(int id);

  /// Release a pattern prepared by [register].
  Future<void> unregister(int id);

  /// Warm the haptic engine.
  Future<void> prepare();

  /// Stop whatever is playing.
  Future<void> stop();

  /// Told about every intent handed to [FlutterHaptics.perform], before it
  /// is routed and before [FlutterHaptics.enabled] is consulted.
  ///
  /// Nothing on a device needs this — the arm has already been resolved into
  /// a `play` or a `playSystem` by the time anything reaches the actuator.
  /// It exists so a test double can assert on the *meaning* an app asked for
  /// rather than reconstructing it from what the arm happened to resolve to.
  /// See [FakeHapticsPlatform.intents].
  void noteIntent(HapticIntent intent) {}
}

/// The real implementation: one method channel, shared by both platforms.
class MethodChannelHaptics extends FlutterHapticsPlatform {
  /// The channel both the Kotlin and Swift sides listen on.
  static const channel = MethodChannel('flutter_haptics');

  @override
  Future<HapticSupport> querySupport() async {
    try {
      final raw = await channel.invokeMapMethod<String, Object?>('support');
      return raw == null ? HapticSupport.unsupported : HapticSupport.fromMap(raw);
    } catch (_) {
      return HapticSupport.unsupported;
    }
  }

  @override
  Future<NativeResult> play(HapticPattern pattern) => _ask('play', {
        'events': pattern.events.map((e) => e.toMap()).toList(),
      });

  @override
  Future<NativeResult> playSystem(
    SystemHaptic haptic, {
    required bool requirePerceptible,
  }) =>
      _ask('playSystem', {
        'name': haptic.name,
        'minimumVersion': haptic.minimumVersion,
        'requirePerceptible': requirePerceptible,
      });

  /// Both renderers answer `{played: bool, reason: String}`, so one helper
  /// covers them. A missing implementation — desktop, web, a test with no
  /// mock — reads as a device that cannot do it, which is accurate.
  Future<NativeResult> _ask(String method, Map<String, Object?> arguments) async {
    try {
      final raw = await channel.invokeMapMethod<String, Object?>(method, arguments);
      if (raw == null) return const NativeResult.failed('the platform gave no answer');
      if (raw['played'] == true) return const NativeResult.played();
      return NativeResult.failed(
        (raw['reason'] as String?) ?? 'the platform did not say why',
        registrationLost: raw['registrationLost'] == true,
      );
    } on MissingPluginException {
      return const NativeResult.failed('no haptics implementation on this platform');
    } catch (error) {
      return NativeResult.failed('$error');
    }
  }

  @override
  Future<int?> register(HapticPattern pattern) async {
    try {
      return await channel.invokeMethod<int>('register', {
        'events': pattern.events.map((e) => e.toMap()).toList(),
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Future<NativeResult> playRegistered(int id) =>
      _ask('playRegistered', {'id': id});

  @override
  Future<void> unregister(int id) async {
    try {
      await channel.invokeMethod<void>('unregister', {'id': id});
    } catch (_) {
      // Silent fail
    }
  }

  @override
  Future<void> prepare() async {
    try {
      await channel.invokeMethod<void>('prepare');
    } catch (_) {
      // Silent fail
    }
  }

  @override
  Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } catch (_) {
      // Silent fail
    }
  }
}
