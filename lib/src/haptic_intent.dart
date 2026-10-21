import 'package:flutter/foundation.dart';

import 'haptic_pattern.dart';
import 'system_haptic.dart';

/// What one platform should do for an intent.
///
/// Three states, each a deliberate statement rather than an absence:
///
/// - [HapticArm.native] — play this platform's own constant, falling back to
///   the intent's pattern only if the device cannot deliver it.
/// - [HapticArm.pattern] — use the intent's pattern here, on purpose. The
///   platform has no constant for this meaning, or none you want.
/// - [HapticArm.silent] — play nothing here, on purpose.
///
/// The type parameter keeps the arms honest: `ios:` only accepts an
/// [IOSHaptic] and `android:` only an [AndroidHaptic], so pairing the wrong
/// vocabulary with a platform is a compile error rather than a silent no-op.
///
/// Every factory is `const`, so intents can be `static const`.
sealed class HapticArm<T extends SystemHaptic> {
  const HapticArm();

  /// Play [haptic], recovering with the intent's pattern if the device
  /// cannot deliver it.
  const factory HapticArm.native(T haptic) = NativeArm<T>;

  /// Use the intent's pattern here, deliberately.
  ///
  /// This is the arm for a meaning the platform has no constant for —
  /// Android has nothing resembling iOS's `notificationWarning`, for
  /// instance — where you still want something felt.
  const factory HapticArm.pattern() = PatternArm<T>;

  /// Play nothing here, deliberately.
  ///
  /// For a meaning that belongs to one platform only: iOS has no concept of
  /// a toggle or a drag, so an intent for one says so rather than
  /// approximating it.
  const factory HapticArm.silent() = SilentArm<T>;
}

/// The platform's own constant. See [HapticArm.native].
final class NativeArm<T extends SystemHaptic> extends HapticArm<T> {
  const NativeArm(this.haptic);

  /// The constant to play on this platform.
  final T haptic;

  // Compared as a raw `NativeArm`, deliberately. `other is NativeArm<T>`
  // answers differently depending on which side the more general type is on
  // — a NativeArm<IOSHaptic> is a NativeArm<SystemHaptic> but not the
  // reverse — so equality would not be symmetric and would disagree with
  // hashCode. The haptic itself carries the platform anyway.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NativeArm && haptic == other.haptic;

  @override
  int get hashCode => Object.hash(NativeArm, haptic);

  @override
  String toString() => 'HapticArm.native(${haptic.name})';
}

/// The intent's pattern, chosen rather than fallen back to.
/// See [HapticArm.pattern].
final class PatternArm<T extends SystemHaptic> extends HapticArm<T> {
  const PatternArm();

  @override
  bool operator ==(Object other) => other is PatternArm;

  @override
  int get hashCode => (PatternArm).hashCode;

  @override
  String toString() => 'HapticArm.pattern()';
}

/// Nothing, deliberately. See [HapticArm.silent].
final class SilentArm<T extends SystemHaptic> extends HapticArm<T> {
  const SilentArm();

  @override
  bool operator ==(Object other) => other is SilentArm;

  @override
  int get hashCode => (SilentArm).hashCode;

  @override
  String toString() => 'HapticArm.silent()';
}

/// What each platform should do for one meaning in your app.
///
/// This package ships no intents. The two platform vocabularies barely
/// overlap — iOS names nine kinds of feedback, Android twenty, and almost
/// none of the names correspond — so any "universal" set would be a third
/// vocabulary invented to paper over that. You name the meanings your app
/// has, in your words, and state what each platform does:
///
/// ```dart
/// class AppHaptics {
///   static const saved = HapticIntent(
///     ios: HapticArm.native(IOSHaptic.notificationSuccess),
///     android: HapticArm.native(AndroidHaptic.confirm),  // needs API 30
///     pattern: HapticPatterns.success,                   // recovery below it
///   );
///
///   static const caution = HapticIntent(
///     ios: HapticArm.native(IOSHaptic.notificationWarning),
///     android: HapticArm.pattern(),   // Android has no warning constant
///     pattern: HapticPatterns.warning,
///   );
///
///   static const toggledOn = HapticIntent(
///     ios: HapticArm.silent(),        // iOS has no toggle feedback
///     android: HapticArm.native(AndroidHaptic.toggleOn),
///     pattern: HapticPatterns.mediumTap,
///   );
/// }
///
/// await FlutterHaptics.perform(AppHaptics.saved);
/// ```
///
/// Both arms are required on purpose. An intent that does not say what iOS
/// does is an intent nobody can read, and the three arms make the asymmetry
/// between the platforms a thing in the source rather than a surprise at
/// runtime.
///
/// ## What [pattern] is for
///
/// Two different things, which [HapticArm] now tells apart:
///
/// - **Chosen**, by a [HapticArm.pattern] arm: this platform has no constant
///   for this meaning and the pattern is the answer.
/// - **Recovered**, after a [HapticArm.native] arm the device could not
///   deliver: the OS is older than the constant needs, or the actuator
///   cannot render it.
///
/// Both play the same pattern and both report [HapticRoute.pattern]. The
/// difference is in the intent, which is where it belongs.
@immutable
class HapticIntent {
  const HapticIntent({
    required this.ios,
    required this.android,
    required this.pattern,
  });

  /// What iOS does for this meaning.
  final HapticArm<IOSHaptic> ios;

  /// What Android does for this meaning.
  final HapticArm<AndroidHaptic> android;

  /// Played where an arm chooses it, and where a native arm could not be
  /// delivered.
  final HapticPattern pattern;

  /// The arm for [platform], or null on a platform this package has no
  /// implementation for.
  HapticArm<SystemHaptic>? armFor(TargetPlatform platform) => switch (platform) {
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
  String toString() => 'HapticIntent(ios: $ios, android: $android)';
}
