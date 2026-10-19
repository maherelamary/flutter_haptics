import 'package:flutter/foundation.dart';

/// One platform's own haptic vocabulary.
///
/// These are not this package's inventions. Each value names a constant the
/// operating system already defines and the device vendor has already tuned,
/// so playing one feels like the rest of that platform rather than like an
/// app imitating it.
///
/// The two vocabularies are **not** translations of each other. iOS defines
/// nine; Android defines twenty, twelve of which iOS has no concept for, and
/// almost none of the names line up. That asymmetry is real, and this package
/// does not paper over it — [FlutterHaptics.playSystem] plays a value only on
/// the platform it belongs to, and [HapticIntent] is how you pair one with
/// the other when you want cross-platform behaviour.
/// Implementations are always enums, which is what gives every value a
/// `name` — the identifier sent over the channel and shown in diagnostics.
abstract interface class SystemHaptic implements Enum {
  /// The only platform this value plays on. Anywhere else it does nothing.
  TargetPlatform get platform;

  /// The OS version this constant arrived in — Android SDK int, iOS major
  /// release. Checked for you, so no caller writes a version check.
  int get minimumVersion;
}

/// UIKit's feedback vocabulary — the nine kinds iOS defines.
///
/// All of them predate this package's iOS 15 floor, so [minimumVersion] never
/// actually gates one. It is recorded for honesty rather than for branching.
enum IOSHaptic implements SystemHaptic {
  /// `UIImpactFeedbackGenerator(.light)` — a light collision.
  impactLight(10),

  /// `UIImpactFeedbackGenerator(.medium)` — a moderate collision.
  impactMedium(10),

  /// `UIImpactFeedbackGenerator(.heavy)` — a forceful collision.
  impactHeavy(10),

  /// `UIImpactFeedbackGenerator(.rigid)` — crisp and mechanical.
  impactRigid(13),

  /// `UIImpactFeedbackGenerator(.soft)` — dull and cushioned.
  impactSoft(13),

  /// `UINotificationFeedbackGenerator(.success)` — an action succeeded.
  notificationSuccess(10),

  /// `UINotificationFeedbackGenerator(.warning)` — caution.
  ///
  /// Android defines nothing like this. There is no constant to pair it with.
  notificationWarning(10),

  /// `UINotificationFeedbackGenerator(.error)` — an action failed.
  notificationError(10),

  /// `UISelectionFeedbackGenerator` — a picker stepping by one.
  selection(10);

  const IOSHaptic(this.minimumVersion);

  @override
  final int minimumVersion;

  @override
  TargetPlatform get platform => TargetPlatform.iOS;
}

/// Android's `HapticFeedbackConstants` — the twenty playable kinds.
///
/// `NO_HAPTICS` is deliberately absent: it means "play nothing on purpose",
/// which is already what not calling anything does.
///
/// [minimumVersion] is the SDK level the constant arrived in, read from the
/// platform's own `api-versions.xml`. A device below it cannot play the
/// constant at all, so [HapticIntent] falls to its pattern there and
/// [FlutterHaptics.playSystem] reports that nothing played.
enum AndroidHaptic implements SystemHaptic {
  /// `LONG_PRESS` — a long press completing. The heaviest tap Android defines.
  longPress(1),

  /// `VIRTUAL_KEY` — an on-screen key going down.
  virtualKey(5),

  /// `KEYBOARD_TAP` — a keyboard key.
  ///
  /// Shares its underlying value with [keyboardPress]; Android gives one
  /// effect two names, and both are kept here because they read differently
  /// at a call site.
  keyboardTap(8),

  /// `CLOCK_TICK` — a picker stepping by one. Android's selection tick.
  clockTick(21),

  /// `CONTEXT_CLICK` — a firm confirmation press.
  contextClick(23),

  /// `KEYBOARD_PRESS` — a key going down, as distinct from coming up.
  keyboardPress(27),

  /// `KEYBOARD_RELEASE` — a key coming up. iOS has no release event at all.
  keyboardRelease(27),

  /// `VIRTUAL_KEY_RELEASE` — an on-screen key coming up.
  virtualKeyRelease(27),

  /// `TEXT_HANDLE_MOVE` — dragging a text selection handle.
  textHandleMove(27),

  /// `CONFIRM` — an action succeeded.
  confirm(30),

  /// `REJECT` — an action was refused.
  reject(30),

  /// `GESTURE_START` — a gesture beginning.
  gestureStart(30),

  /// `GESTURE_END` — a gesture completing.
  gestureEnd(30),

  /// `DRAG_START` — a drag picking something up.
  dragStart(34),

  /// `GESTURE_THRESHOLD_ACTIVATE` — a gesture passing the point of commitment.
  gestureThresholdActivate(34),

  /// `GESTURE_THRESHOLD_DEACTIVATE` — a gesture falling back below it.
  gestureThresholdDeactivate(34),

  /// `SEGMENT_FREQUENT_TICK` — a segment boundary, lighter, for close spacing.
  segmentFrequentTick(34),

  /// `SEGMENT_TICK` — crossing a segment boundary, such as a slider notch.
  segmentTick(34),

  /// `TOGGLE_OFF` — a switch moving to off.
  toggleOff(34),

  /// `TOGGLE_ON` — a switch moving to on.
  toggleOn(34);

  const AndroidHaptic(this.minimumVersion);

  @override
  final int minimumVersion;

  @override
  TargetPlatform get platform => TargetPlatform.android;
}
