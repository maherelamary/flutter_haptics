import 'package:flutter/foundation.dart';

import 'haptic_pattern.dart';
import 'system_haptic.dart';

/// What should happen when a haptic was asked for and could not be delivered.
///
/// Set [FlutterHaptics.onFailure] once; it applies to every verb. To route
/// failures somewhere of your own — a logger, Crashlytics, a counter — set
/// [FlutterHaptics.onFailureReport] instead.
///
/// Not every [HapticRoute.none] is a failure. Switching haptics off through
/// [FlutterHaptics.enabled], and performing an intent whose arm for this
/// platform is [HapticArm.silent], are both the app getting exactly what it
/// asked for. Those are never reported.
enum HapticFailureMode {
  /// Say nothing. The call still returns [HapticRoute.none].
  silent,

  /// Print one line to the console. The default while debugging, so a haptic
  /// that silently does nothing is visible while you are building rather than
  /// discovered on a user's device.
  ///
  /// Each distinct message is printed once — see [FlutterHaptics.onFailure].
  log,

  /// Throw [HapticFailure]. For a build that should not ship a haptic it
  /// cannot play — a test suite, or an app where the feedback is essential.
  ///
  /// Never deduplicated: a swallowed second throw would be a worse surprise
  /// than a repeated one.
  throwIt,
}

/// Thrown by any verb when [FlutterHaptics.onFailure] is
/// [HapticFailureMode.throwIt] and a haptic could not be delivered, and
/// handed to [FlutterHaptics.onFailureReport] when one is set.
///
/// An `Exception` rather than an `Error`: it reports a device limitation the
/// caller may reasonably want to recover from, not a bug in the program.
class HapticFailure implements Exception {
  HapticFailure({
    required this.request,
    required this.reason,
    this.pattern,
    this.haptic,
  });

  /// What was asked for — `playSystem(AndroidHaptic.toggleOn)`, `play(…)`.
  final String request;

  /// Why nothing played, in the platform's own terms where it knows:
  /// `requires API 34, device is 31`, `no vibrator on this device`.
  final String reason;

  /// The pattern that did not play, where one was asked for.
  ///
  /// [request] describes a pattern by its shape, because patterns have no
  /// names — and two different ones can read the same. A reporter that needs
  /// to tell them apart has the pattern itself here.
  final HapticPattern? pattern;

  /// The constant that did not play, where one was asked for.
  final SystemHaptic? haptic;

  @override
  String toString() => 'HapticFailure: $request played nothing — $reason';
}

/// Receives every distinct failure. See [FlutterHaptics.onFailureReport].
typedef HapticFailureReporter = void Function(HapticFailure failure);

/// Applies the configured policy to one failure. Internal.
///
/// A [reporter] replaces [mode] entirely: an app that has said where its
/// failures go does not also want them on the console, or thrown.
/// Deduplication happens in the caller, which is where the policy lives.
void reportHapticFailure(
  HapticFailureMode mode, {
  required HapticFailure failure,
  HapticFailureReporter? reporter,
}) {
  if (reporter != null) {
    reporter(failure);
    return;
  }

  switch (mode) {
    case HapticFailureMode.silent:
      return;
    case HapticFailureMode.log:
      debugPrint(
        'flutter_haptics: ${failure.request} played nothing '
        '— ${failure.reason}',
      );
    case HapticFailureMode.throwIt:
      throw failure;
  }
}
