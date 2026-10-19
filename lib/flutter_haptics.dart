/// Haptic feedback for iOS and Android, in three verbs.
///
/// ```dart
/// import 'package:flutter_haptics/flutter_haptics.dart';
///
/// // Your own waveform, on every platform.
/// await FlutterHaptics.play(HapticPatterns.success);
///
/// // One platform's own constant. The type says which platform.
/// await FlutterHaptics.playSystem(AndroidHaptic.toggleOn);
///
/// // A meaning: the native route where you declared one, your pattern where
/// // it could not be delivered.
/// await FlutterHaptics.perform(AppHaptics.saved);
/// ```
///
/// Nothing throws by default, and each verb returns a [HapticRoute] saying
/// what actually happened.
///
/// ## The two vocabularies
///
/// iOS names nine kinds of feedback; Android names twenty, twelve of which
/// iOS has no concept for, and almost none of the names correspond. This
/// package does not flatten them into a third, invented taxonomy — it gives
/// you both, and [HapticIntent] is how you pair them for your own app.
///
/// ## Key types
///
/// - [FlutterHaptics] — the three verbs, plus [FlutterHaptics.support] and
///   the app-wide [FlutterHaptics.enabled] switch
/// - [HapticPattern], [HapticEvent], [HapticParam] — a waveform you compose,
///   with intensity and sharpness that may vary over time
/// - [HapticPatterns] — a library of ready-made patterns
/// - [HapticPatternBuilder] — a fluent way to build one
/// - [IOSHaptic], [AndroidHaptic], [SystemHaptic] — each platform's own
///   constants, carrying the OS version they need
/// - [HapticIntent] — a native route per platform with a pattern to recover
/// - [HapticRoute] — what a call did: `system`, `pattern` or `none`
/// - [HapticSupport] — what this device can actually reproduce
/// - [HapticFailureMode] — log, throw or ignore a haptic that could not play
/// - [HapticHandle] — a pattern the platform holds ready for cheap replay
/// - [Ahap] — read and write Apple's `.ahap` pattern files
/// - [FlutterHapticsPlatform] — the seam to swap in tests; see
///   `package:flutter_haptics/testing.dart`
library;

export 'src/ahap.dart';
export 'src/haptic_event.dart';
export 'src/haptic_failure.dart';
export 'src/haptic_intent.dart';
export 'src/haptic_route.dart';
export 'src/haptic_handle.dart';
export 'src/haptic_param.dart';
export 'src/haptic_pattern.dart';
export 'src/haptic_pattern_builder.dart';
export 'src/haptic_support.dart';
export 'src/patterns.dart';
export 'src/platform.dart';
export 'src/system_haptic.dart';
export 'src/flutter_haptics.dart';
