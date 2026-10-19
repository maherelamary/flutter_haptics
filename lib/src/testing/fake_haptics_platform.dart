import '../haptic_pattern.dart';
import '../haptic_support.dart';
import '../platform.dart';
import '../system_haptic.dart';

/// A [FlutterHapticsPlatform] that plays nothing and records everything.
///
/// Install it and every haptic your widgets ask for becomes an assertion:
///
/// ```dart
/// import 'package:flutter_haptics/testing.dart';
///
/// late FakeHapticsPlatform haptics;
///
/// setUp(() {
///   haptics = FakeHapticsPlatform();
///   FlutterHapticsPlatform.instance = haptics;
/// });
/// tearDown(FlutterHapticsPlatform.reset);
///
/// testWidgets('saving confirms', (tester) async {
///   await tester.tap(find.byType(SaveButton));
///   await tester.pump();
///
///   expect(haptics.systemHaptics, [AndroidHaptic.confirm]);
///   expect(haptics.played, isEmpty);          // it did not need the pattern
/// });
/// ```
///
/// The constructor arguments stand in for a device less capable than the one
/// running the test, which is the case most worth covering and the hardest to
/// reach otherwise.
class FakeHapticsPlatform extends FlutterHapticsPlatform {
  FakeHapticsPlatform({
    this.support = const HapticSupport(
      fidelity: HapticFidelity.full,
      supportsContinuous: true,
    ),
    this.playsSystemHaptics = true,
    this.canRegister = true,
    this.declineReason = 'this fake declines system haptics',
  });

  /// What [FlutterHaptics.support] will report.
  final HapticSupport support;

  /// Whether this pretend platform can play its own constants.
  ///
  /// `false` stands in for a device that cannot — an OS below the constant's
  /// minimum, or a rhythm-tier actuator — so a [HapticIntent] falls to its
  /// pattern and [FlutterHaptics.playSystem] reports that nothing played.
  final bool playsSystemHaptics;

  /// Whether [FlutterHaptics.register] can prepare a pattern here.
  final bool canRegister;

  /// The reason returned when [playsSystemHaptics] is false.
  final String declineReason;

  /// Patterns sent through the synthesiser, in order.
  final List<HapticPattern> played = [];

  /// System constants requested, whether or not this fake played them.
  final List<SystemHaptic> systemHaptics = [];

  /// Ids handed out by [register], in order.
  final List<int> registrations = [];

  /// Registration ids replayed, in order. Repeats are expected.
  final List<int> replays = [];

  /// Registration ids released.
  final List<int> releases = [];

  /// How many times the engine was asked to warm up.
  int prepareCount = 0;

  /// How many times playback was stopped.
  int stopCount = 0;

  int _nextId = 1;

  /// The most recent pattern sent through the synthesiser, if any.
  ///
  /// Patterns compare by value, so an intent's recovery can be asserted by
  /// name: `expect(haptics.lastPlayed, AppHaptics.saved.pattern)`.
  HapticPattern? get lastPlayed => played.isEmpty ? null : played.last;

  /// The most recent constant requested, if any.
  SystemHaptic? get lastSystemHaptic =>
      systemHaptics.isEmpty ? null : systemHaptics.last;

  /// Forgets everything recorded, keeping the configured behaviour.
  void clear() {
    played.clear();
    systemHaptics.clear();
    requiredPerceptible.clear();
    registrations.clear();
    replays.clear();
    releases.clear();
    prepareCount = 0;
    stopCount = 0;
  }

  @override
  Future<HapticSupport> querySupport() async => support;

  @override
  Future<NativeResult> play(HapticPattern pattern) async {
    played.add(pattern);
    return const NativeResult.played();
  }

  /// Whether each recorded request asked the device to be second-guessed.
  /// `perform` sets it; `playSystem` does not.
  final List<bool> requiredPerceptible = [];

  @override
  Future<NativeResult> playSystem(
    SystemHaptic haptic, {
    required bool requirePerceptible,
  }) async {
    systemHaptics.add(haptic);
    requiredPerceptible.add(requirePerceptible);
    return playsSystemHaptics
        ? const NativeResult.played()
        : NativeResult.failed(declineReason);
  }

  @override
  Future<int?> register(HapticPattern pattern) async {
    if (!canRegister) return null;
    final id = _nextId++;
    registrations.add(id);
    return id;
  }

  @override
  Future<void> playRegistered(int id) async => replays.add(id);

  @override
  Future<void> unregister(int id) async => releases.add(id);

  @override
  Future<void> prepare() async => prepareCount++;

  @override
  Future<void> stop() async => stopCount++;
}
