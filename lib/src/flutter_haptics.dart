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
  ///
  /// Each distinct `(request, reason)` is reported once per run. A haptic
  /// firing on every frame of a drag would otherwise bury the console in one
  /// repeated line, and the repeat says nothing new — the device's
  /// limitations do not change mid-session. [HapticFailureMode.throwIt] is
  /// the exception and always throws.
  static HapticFailureMode onFailure =
      kDebugMode ? HapticFailureMode.log : HapticFailureMode.silent;

  /// Send failures somewhere of your own instead of the console.
  ///
  /// When set this replaces [onFailure] entirely — nothing is printed and
  /// nothing is thrown, whatever the mode says — so a release build can
  /// record what is not being felt in the field:
  ///
  /// ```dart
  /// FlutterHaptics.onFailureReport = (failure) {
  ///   FirebaseCrashlytics.instance.log('$failure');
  /// };
  /// ```
  ///
  /// Called once per distinct `(request, reason)`, on the same deduplication
  /// as the log, so a reporter cannot be flooded either.
  static HapticFailureReporter? onFailureReport;

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

    _failed(
      'play(${pattern.events.length} events, '
      '${pattern.duration.inMilliseconds}ms)',
      result.reason,
      pattern: pattern,
    );
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
        haptic: haptic,
      );
      return HapticRoute.none;
    }

    // Not requirePerceptible: the caller asked for this exact constant, and
    // the device vendor tuned it for this hardware. Refusing it on a guess
    // would both overreach and hide whether it works.
    final result = await FlutterHapticsPlatform.instance
        .playSystem(haptic, requirePerceptible: false);
    if (result.played) return HapticRoute.system;

    _failed('playSystem(${haptic.name})', result.reason, haptic: haptic);
    return HapticRoute.none;
  }

  /// Play an intent — what this platform's arm says to do.
  ///
  /// Each arm resolves to exactly one outcome:
  ///
  /// | Arm | Result |
  /// |---|---|
  /// | [HapticArm.native], delivered | [HapticRoute.system] |
  /// | [HapticArm.native], not delivered | [HapticRoute.pattern] — recovered |
  /// | [HapticArm.pattern] | [HapticRoute.pattern] — chosen |
  /// | [HapticArm.silent] | [HapticRoute.none] |
  ///
  /// A chosen pattern and a recovered one both report
  /// [HapticRoute.pattern]; which it was is written in the intent.
  static Future<HapticRoute> perform(HapticIntent intent) async {
    // Noted before the switch, and before `enabled` is consulted: this
    // records what the app asked for, which is a fact about the app and not
    // about the device or the user's settings.
    FlutterHapticsPlatform.instance.noteIntent(intent);
    if (!enabled) return HapticRoute.none;

    final arm = intent.armFor(defaultTargetPlatform);

    switch (arm) {
      // No implementation for this platform at all.
      case null:
      // Nothing is meant to happen here, so nothing does. Not a failure, and
      // the pattern is deliberately not consulted.
      case SilentArm():
        return HapticRoute.none;

      // The pattern is the answer here, not a consolation for missing one.
      case PatternArm():
        return play(intent.pattern);

      case NativeArm(haptic: final haptic):
        // requirePerceptible: this verb is asked to make a *meaning* felt and
        // carries a pattern this package knows works, so where the native
        // route may be accepted without being rendered, the pattern wins.
        final result = await FlutterHapticsPlatform.instance
            .playSystem(haptic, requirePerceptible: true);
        if (result.played) return HapticRoute.system;

        // Asked for and not delivered — this is what the pattern is for. The
        // decline is not reported: the intent did what it promised.
        return play(intent.pattern);
    }
  }

  /// Hand a pattern to the platform once, so it can be replayed cheaply and
  /// no faster than the actuator can separate.
  ///
  /// [play] rebuilds a pattern natively on every call. For anything fired
  /// repeatedly — a picker tick, a step counter, a game loop — register it
  /// instead and play the handle:
  ///
  /// ```dart
  /// final tick = FlutterHaptics.register(HapticPatterns.selection);
  /// void onItemChanged() => tick.play();
  /// ...
  /// tick.dispose();
  /// ```
  ///
  /// Returns synchronously so a handle can be built in `initState` or a field
  /// initialiser. Registration runs in the background; a [HapticHandle.play]
  /// that arrives first waits for it.
  ///
  /// [minInterval] is the floor on how often the handle will replay. It
  /// defaults to the device's own fidelity — see [HapticHandle] for the
  /// table — never to which platform it is. Pass [Duration.zero] to fire
  /// every call.
  ///
  /// Always returns a usable handle. Where the platform cannot hold a
  /// prepared pattern it falls back to [play] and reports
  /// `isPrepared == false`, so a caller never needs to branch.
  static HapticHandle register(HapticPattern pattern, {Duration? minInterval}) =>
      HapticHandle.internal(pattern, minInterval);

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

  /// Failures already reported, so a per-frame haptic cannot flood the log.
  ///
  /// A device that cannot play something will not start being able to
  /// halfway through a session, so the second identical report carries no
  /// information. The same call failing for a *new* reason is news, and is
  /// said again.
  ///
  /// Keyed by the thing that failed rather than the sentence describing it:
  /// patterns have no names, and two different ones can read the same.
  /// Records, patterns and system haptics all compare by value, and a [Set]
  /// settles a hash collision with `==`, so two distinct subjects can never
  /// collapse into one report.
  static final Set<(Object subject, String reason)> _reported = {};

  static void _failed(
    String request,
    String reason, {
    HapticPattern? pattern,
    SystemHaptic? haptic,
  }) {
    final reporter = onFailureReport;
    final failure = HapticFailure(
      request: request,
      reason: reason,
      pattern: pattern,
      haptic: haptic,
    );

    // Throwing is never deduplicated: a swallowed second throw would be a
    // worse surprise than a repeated one.
    if (reporter == null && onFailure == HapticFailureMode.throwIt) {
      throw failure;
    }

    if (!_reported.add((pattern ?? haptic ?? request, reason))) return;

    reportHapticFailure(onFailure, failure: failure, reporter: reporter);
  }

  /// Drops the cached [support] result so the next read queries the platform
  /// again. Only useful in tests.
  @visibleForTesting
  static void debugResetSupportCache() => _support = null;

  /// Forgets which failures have already been reported, so the next one is
  /// said again. Only useful in tests.
  @visibleForTesting
  static void debugResetFailureLog() => _reported.clear();
}
