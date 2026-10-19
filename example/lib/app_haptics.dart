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
    ios: IOSHaptic.notificationSuccess,
    android: AndroidHaptic.confirm, // needs API 30
    pattern: HapticPatterns.success, // below that, or on a weak actuator
  );

  /// Something the user did was refused.
  static const refused = HapticIntent(
    ios: IOSHaptic.notificationError,
    android: AndroidHaptic.reject, // needs API 30
    pattern: HapticPatterns.error,
  );

  /// Caution — the one case where the platforms genuinely diverge.
  ///
  /// Android has no warning constant at all. Leaving [HapticIntent.android]
  /// null would mean silence there, so this app chooses to let the pattern
  /// carry it by naming the nearest real constant instead. That choice is
  /// visible here rather than hidden in the package.
  static const caution = HapticIntent(
    ios: IOSHaptic.notificationWarning,
    android: AndroidHaptic.gestureEnd, // the closest Android offers
    pattern: HapticPatterns.warning,
  );

  /// A picker moving by one step.
  static const stepped = HapticIntent(
    ios: IOSHaptic.selection,
    android: AndroidHaptic.clockTick, // needs API 21
    pattern: HapticPatterns.selection,
  );

  /// A button being pressed.
  static const pressed = HapticIntent(
    ios: IOSHaptic.impactMedium,
    android: AndroidHaptic.contextClick, // needs API 23
    pattern: HapticPatterns.mediumTap,
  );

  /// A firm, deliberate press.
  ///
  /// Android's `longPress` is its heaviest and longest constant, and on an
  /// actuator with no amplitude control it is the only one that can actually
  /// be felt — so this is the one intent that still takes the native route
  /// there while everything else recovers with a pattern.
  static const heldDown = HapticIntent(
    ios: IOSHaptic.impactHeavy,
    android: AndroidHaptic.longPress, // API 1, and perceptible everywhere
    pattern: HapticPatterns.heavyTap,
  );

  /// A switch turning on — **Android-only**, by nature.
  ///
  /// iOS has no toggle feedback, so [HapticIntent.ios] is null and iOS plays
  /// nothing. That null is a statement about iOS, not a gap in this app.
  static const toggledOn = HapticIntent(
    ios: null,
    android: AndroidHaptic.toggleOn, // needs API 34
    pattern: HapticPatterns.mediumTap,
  );

  /// A drag picking something up — **Android-only**, by nature.
  static const dragStarted = HapticIntent(
    ios: null,
    android: AndroidHaptic.dragStart, // needs API 34
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
