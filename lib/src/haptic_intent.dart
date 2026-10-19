import 'package:flutter/foundation.dart';

import 'haptic_pattern.dart';
import 'system_haptic.dart';

/// A pairing of each platform's own feedback with a pattern to fall back on.
///
/// This package ships no intents of its own. The two platform vocabularies
/// barely overlap — iOS names nine kinds, Android twenty, and almost none of
/// the names correspond — so any "universal" set would be a third vocabulary
/// invented to paper over that. You name the meanings your app has, in your
/// words, and say how each platform should serve them:
///
/// ```dart
/// class AppHaptics {
///   static const saved = HapticIntent(
///     ios: IOSHaptic.notificationSuccess,
///     android: AndroidHaptic.confirm,        // needs API 30
///     pattern: HapticPatterns.success,       // recovery below that
///   );
///
///   static const toggled = HapticIntent(
///     ios: null,                             // iOS has no toggle feedback
///     android: AndroidHaptic.toggleOn,       // needs API 34
///     pattern: HapticPatterns.mediumTap,
///   );
/// }
///
/// await FlutterHaptics.perform(AppHaptics.saved);
/// ```
///
/// ## What [pattern] is for
///
/// **A recovery, not a substitute.** It covers a native route you *asked for*
/// and did not get — the OS is older than the constant needs, the actuator
/// cannot render it, or the call was declined. It never fills in for a route
/// you never asked for: a `null` arm means this platform plays nothing, on
/// purpose, and the pattern is not consulted.
///
/// That is what makes the asymmetry readable. `ios: null` is a line of code
/// saying "iOS has no such concept", not a failure discovered at runtime.
@immutable
class HapticIntent {
  const HapticIntent({
    this.ios,
    this.android,
    required this.pattern,
  });

  /// iOS's own feedback for this meaning, or null if iOS has none.
  final IOSHaptic? ios;

  /// Android's own feedback for this meaning, or null if Android has none.
  final AndroidHaptic? android;

  /// Played when a native route was asked for and could not be delivered.
  final HapticPattern pattern;

  /// The arm for [platform], or null where this intent asks for nothing.
  SystemHaptic? routeFor(TargetPlatform platform) => switch (platform) {
        TargetPlatform.iOS => ios,
        TargetPlatform.android => android,
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HapticIntent &&
          ios == other.ios &&
          android == other.android &&
          pattern == other.pattern;

  @override
  int get hashCode => Object.hash(ios, android, pattern);

  @override
  String toString() =>
      'HapticIntent(ios: ${ios?.name}, android: ${android?.name})';
}
