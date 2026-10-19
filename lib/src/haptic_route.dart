/// What a haptic call actually did.
///
/// Every verb on [FlutterHaptics] returns one. Ignore it and nothing is lost;
/// read it and you know whether the device played its own feedback, fell back
/// to a pattern, or did nothing at all.
enum HapticRoute {
  /// The platform's own feedback played — a `UIFeedbackGenerator` on iOS, a
  /// `HapticFeedbackConstants` value on Android.
  system,

  /// A [HapticPattern] played through this package's renderer. Either a
  /// direct [FlutterHaptics.play], or a [HapticIntent] recovering from a
  /// native route it could not get.
  pattern,

  /// Nothing played. Haptics are switched off, the value belongs to another
  /// platform, no route was asked for, or the device cannot do it.
  none,
}
