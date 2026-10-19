import 'package:flutter/foundation.dart';

/// What should happen when a haptic was asked for and could not be delivered.
///
/// Set [FlutterHaptics.onFailure] once; it applies to every verb.
///
/// Not every [HapticRoute.none] is a failure. Switching haptics off through
/// [FlutterHaptics.enabled], or performing an intent whose arm for this
/// platform is deliberately `null`, are both the app getting exactly what it
/// asked for. Those are never reported.
enum HapticFailureMode {
  /// Say nothing. The call still returns [HapticRoute.none].
  silent,

  /// Print one line to the console. The default while debugging, so a haptic
  /// that silently does nothing is visible while you are building rather than
  /// discovered on a user's device.
  log,

  /// Throw [HapticFailure]. For a build that should not ship a haptic it
  /// cannot play — a test suite, or an app where the feedback is essential.
  throwIt,
}

/// Thrown by any verb when [FlutterHaptics.onFailure] is
/// [HapticFailureMode.throwIt] and a haptic could not be delivered.
///
/// An `Exception` rather than an `Error`: it reports a device limitation the
/// caller may reasonably want to recover from, not a bug in the program.
class HapticFailure implements Exception {
  HapticFailure({required this.request, required this.reason});

  /// What was asked for — `playSystem(AndroidHaptic.toggleOn)`, `play(…)`.
  final String request;

  /// Why nothing played, in the platform's own terms where it knows:
  /// `requires API 34, device is 31`, `no vibrator on this device`.
  final String reason;

  @override
  String toString() => 'HapticFailure: $request played nothing — $reason';
}

/// Applies the configured policy. Internal.
void reportHapticFailure(
  HapticFailureMode mode, {
  required String request,
  required String reason,
}) {
  switch (mode) {
    case HapticFailureMode.silent:
      return;
    case HapticFailureMode.log:
      debugPrint('flutter_haptics: $request played nothing — $reason');
    case HapticFailureMode.throwIt:
      throw HapticFailure(request: request, reason: reason);
  }
}
