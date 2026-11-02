import 'package:flutter_haptics/flutter_haptics.dart';

/// The only file in this app that knows about platforms.
///
/// `flutter_haptics` ships no intents of its own, on purpose. iOS names nine
/// kinds of feedback, Android names twenty, and almost none of the names
/// correspond — so any "universal" set would be a third vocabulary invented to
/// hide that. Instead you name the meanings *your* app has and say how each
/// platform should serve them.
///
/// Every call site elsewhere stays platform-blind:
/// `FlutterHaptics.perform(AppHaptics.saved)`.
abstract final class AppHaptics {
  /// Something the user did was accepted.
  static const saved = HapticIntent(
    ios: HapticArm.native(IOSHaptic.notificationSuccess),
    android: HapticArm.native(AndroidHaptic.confirm), // needs API 30
    pattern: HapticPatterns.success, // below that, or on a weak actuator
  );

  /// Something the user did was refused.
  static const refused = HapticIntent(
    ios: HapticArm.native(IOSHaptic.notificationError),
    android: HapticArm.native(AndroidHaptic.reject), // needs API 30
    pattern: HapticPatterns.error,
  );

  /// Caution — the one case where the platforms genuinely diverge.
  ///
  /// Android has no warning constant at all. Rather than approximate it with
  /// the nearest unrelated one, this app says so: the pattern is the answer
  /// on Android, chosen rather than fallen back to.
  static const caution = HapticIntent(
    ios: HapticArm.native(IOSHaptic.notificationWarning),
    android: HapticArm.pattern(),
    pattern: HapticPatterns.warning,
  );

  /// A picker moving by one step.
  static const stepped = HapticIntent(
    ios: HapticArm.native(IOSHaptic.selection),
    android: HapticArm.native(AndroidHaptic.clockTick), // needs API 21
    pattern: HapticPatterns.selection,
  );

  /// A button being pressed.
  static const pressed = HapticIntent(
    ios: HapticArm.native(IOSHaptic.impactMedium),
    android: HapticArm.native(AndroidHaptic.contextClick), // needs API 23
    pattern: HapticPatterns.mediumTap,
  );

  /// A firm, deliberate press.
  ///
  /// `longPress` is Android's heaviest and longest constant. Note that
  /// `perform` still declines it on an actuator with no amplitude control —
  /// the package judges that hardware from what it reports, not from a list
  /// of constants — so this recovers with its pattern there like every other
  /// intent. On capable hardware it takes the native route.
  static const heldDown = HapticIntent(
    ios: HapticArm.native(IOSHaptic.impactHeavy),
    android: HapticArm.native(AndroidHaptic.longPress),
    pattern: HapticPatterns.heavyTap,
  );

  /// A switch turning on — **Android-only**, by nature.
  ///
  /// iOS has no toggle feedback, so this app says nothing should happen
  /// there. [HapticArm.silent] is a statement about iOS, not a gap here.
  static const toggledOn = HapticIntent(
    ios: HapticArm.silent(),
    android: HapticArm.native(AndroidHaptic.toggleOn), // needs API 34
    pattern: HapticPatterns.mediumTap,
  );

  /// A drag picking something up — **Android-only**, by nature.
  static const dragStarted = HapticIntent(
    ios: HapticArm.silent(),
    android: HapticArm.native(AndroidHaptic.dragStart), // needs API 34
    pattern: HapticPatterns.rigid,
  );

  static const all = <String, HapticIntent>{
    'saved': saved,
    'refused': refused,
    'caution': caution,
    'stepped': stepped,
    'pressed': pressed,
    'heldDown': heldDown,
    'toggledOn': toggledOn,
    'dragStarted': dragStarted,
  };
}
