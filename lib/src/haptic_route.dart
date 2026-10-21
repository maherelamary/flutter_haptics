/// What a haptic call actually did.
///
/// Every verb on [FlutterHaptics] returns one. Ignore it and nothing is lost;
/// read it and you know whether the device played its own feedback, fell back
/// to a pattern, or did nothing at all.
enum HapticRoute {
  /// The platform's own feedback played — a `UIFeedbackGenerator` on iOS, a
  /// `HapticFeedbackConstants` value on Android.
  system,

  /// A [HapticPattern] played through this package's renderer.
  ///
  /// Three things arrive here: a direct [FlutterHaptics.play], an intent
  /// whose arm is [HapticArm.pattern] — the pattern chosen, because the
  /// platform names nothing for that meaning — and an intent recovering from
  /// a [HapticArm.native] route it could not get. The last two are told
  /// apart by the intent, not by this value.
  pattern,

  /// Nothing played. Haptics are switched off, the arm for this platform is
  /// [HapticArm.silent], the value belongs to another platform, a handle's
  /// pacing dropped the call, or the device cannot do it.
  none,
}
