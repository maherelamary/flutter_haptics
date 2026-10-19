import 'package:flutter/foundation.dart';

import 'haptic_failure.dart';
import 'haptic_handle.dart';
import 'haptic_intent.dart';
import 'haptic_pattern.dart';
import 'haptic_route.dart';
import 'haptic_support.dart';
import 'platform.dart';
import 'system_haptic.dart';

/// Haptic feedback, in three verbs.
///
/// - [play] renders a [HapticPattern] you wrote. Every platform, every device,
///   degrading down whatever the hardware can do.
/// - [playSystem] plays one of a platform's *own* constants. Only on that
///   platform; the argument's type says which.
/// - [perform] plays a [HapticIntent] — a native route per platform with a
///   pattern to fall back on.
///
/// None of them throws by default, and each returns a [HapticRoute] saying
/// what actually happened. Where a haptic was asked for and could not be
/// delivered, [onFailure] decides whether that is ignored, logged or thrown.
///
/// ```dart
/// await FlutterHaptics.play(HapticPatterns.success);
/// await FlutterHaptics.playSystem(AndroidHaptic.toggleOn);
/// await FlutterHaptics.perform(AppHaptics.saved);
/// ```
abstract final class FlutterHaptics {
  /// App-wide haptics switch.
  ///
  /// Set to `false` and every verb becomes a no-op returning
  /// [HapticRoute.none], so an app's "Haptics" setting is honoured without
  /// guarding every call site. [stop] keeps working, so turning haptics off
  /// mid-pattern silences it.
  ///
  /// Switching off is never reported through [onFailure]: it is the app
  /// getting exactly what it asked for.
  ///
  /// Not persisted — store the user's choice yourself and set this on startup.
  static bool enabled = true;

  /// What happens when a haptic was asked for and could not be delivered.
  ///
  /// Defaults to [HapticFailureMode.log] while debugging and
  /// [HapticFailureMode.silent] in a release build, so a haptic that quietly
  /// does nothing shows up while you are building it rather than on someone
  /// else's phone.
  static HapticFailureMode onFailure =
      kDebugMode ? HapticFailureMode.log : HapticFailureMode.silent;

  static Future<HapticSupport>? _support;

  /// What this device can actually reproduce.
  ///
  /// Queried from the platform once and cached: haptic hardware does not
  /// change while the app is running. Never throws — a platform with no
  /// implementation reports [HapticSupport.unsupported].
  static Future<HapticSupport> get support =>
      _support ??= FlutterHapticsPlatform.instance.querySupport();

  /// Whether anything at all will play on this device.
  ///
  /// Independent of [enabled], which is the app's own choice rather than a
  /// hardware fact.
  static Future<bool> get isSupported async => (await support).isSupported;

  /// Render a pattern through this package's synthesiser.
  ///
  /// Returns [HapticRoute.pattern] when it played, [HapticRoute.none] when
  /// nothing could. An empty pattern is a no-op and is never a failure.
  static Future<HapticRoute> play(HapticPattern pattern) async {
    if (!enabled || pattern.events.isEmpty) return HapticRoute.none;

    final result = await FlutterHapticsPlatform.instance.play(pattern);
    if (result.played) return HapticRoute.pattern;

    _failed('play(${pattern.events.length} events)', result.reason);
    return HapticRoute.none;
  }

  /// Play one of a platform's own haptic constants.
  ///
  /// The argument's type carries the platform, so there is no `ios:`/`android:`
  /// pair and no way to pass the wrong one:
  ///
  /// ```dart
  /// await FlutterHaptics.playSystem(AndroidHaptic.toggleOn);
  /// await FlutterHaptics.playSystem(IOSHaptic.impactRigid);
  /// ```
  ///
  /// **No fallback, ever.** On another platform, or on an OS older than the
  /// constant needs, this returns [HapticRoute.none] and plays nothing. Use
  /// [perform] when you want a pattern to cover those cases.
  ///
  /// Unlike [perform], this does not second-guess the device. These constants
  /// are implemented by the vendor for this hardware, which is the whole
  /// reason they exist, so it hands the request over and reports the answer.
  static Future<HapticRoute> playSystem(SystemHaptic haptic) async {
    if (!enabled) return HapticRoute.none;

    if (haptic.platform != defaultTargetPlatform) {
      _failed(
        'playSystem(${haptic.name})',
        'it belongs to ${haptic.platform.name}, this is '
            '${defaultTargetPlatform.name} — perform() is what crosses platforms',
      );
      return HapticRoute.none;
    }

    // Not requirePerceptible: the caller asked for this exact constant, and
    // the device vendor tuned it for this hardware. Refusing it on a guess
    // would both overreach and hide whether it works.
    final result = await FlutterHapticsPlatform.instance
        .playSystem(haptic, requirePerceptible: false);
    if (result.played) return HapticRoute.system;

    _failed('playSystem(${haptic.name})', result.reason);
    return HapticRoute.none;
  }

  /// Play an intent: this platform's own feedback where you declared one, the
  /// intent's pattern where it could not be delivered.
  ///
  /// Returns [HapticRoute.system] when the platform's own feedback played,
  /// [HapticRoute.pattern] when the recovery did, and [HapticRoute.none] when
  /// the intent asks for nothing on this platform — a `null` arm is a
  /// deliberate silence, not a failure, and is never reported.
  static Future<HapticRoute> perform(HapticIntent intent) async {
    if (!enabled) return HapticRoute.none;

    final route = intent.routeFor(defaultTargetPlatform);
    // Nothing was asked for here, so there is nothing to recover from.
    if (route == null) return HapticRoute.none;

    // requirePerceptible: this verb is asked to make a *meaning* felt, and it
    // carries a pattern this package knows works. Where the native route may
    // be accepted without being rendered, the pattern is the safer answer.
    final result = await FlutterHapticsPlatform.instance
        .playSystem(route, requirePerceptible: true);
    if (result.played) return HapticRoute.system;

    // Asked for and not delivered — this is what the pattern is for. The
    // decline itself is not reported: the intent did what it promised.
    return play(intent.pattern);
  }

  /// Hand a pattern to the platform once, so it can be replayed cheaply.
  ///
  /// [play] rebuilds a pattern natively on every call. For anything fired
  /// repeatedly — a picker tick, a step counter, a game loop — register it
  /// instead and play the handle.
  ///
  /// Always returns a usable [HapticHandle]. Where the platform cannot hold a
  /// prepared pattern, the handle falls back to [play] and reports
  /// `isPrepared == false`, so a caller never needs to branch.
  static Future<HapticHandle> register(HapticPattern pattern) async {
    if (pattern.events.isEmpty) return HapticHandle.internal(null, pattern);

    final id = await FlutterHapticsPlatform.instance.register(pattern);
    return HapticHandle.internal(id, pattern);
  }

  /// Prepare the haptic engine for playback.
  ///
  /// Reduces latency on the first play. No-op on Android, which has no engine
  /// to warm.
  static Future<void> prepare() => FlutterHapticsPlatform.instance.prepare();

  /// Stop any currently playing haptic.
  ///
  /// Works regardless of [enabled], so switching haptics off can silence
  /// something already running.
  static Future<void> stop() => FlutterHapticsPlatform.instance.stop();

  static void _failed(String request, String reason) =>
      reportHapticFailure(onFailure, request: request, reason: reason);

  /// Drops the cached [support] result so the next read queries the platform
  /// again. Only useful in tests.
  @visibleForTesting
  static void debugResetSupportCache() => _support = null;
}
