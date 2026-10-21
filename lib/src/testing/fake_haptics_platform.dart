import '../haptic_event.dart';
import '../haptic_intent.dart';
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
/// reach otherwise. [support] drives behaviour as well as the answer to
/// [FlutterHaptics.support]: a device reporting [HapticFidelity.none] plays
/// nothing at all, and one that cannot sustain a rumble refuses a pattern
/// made only of continuous events, exactly as iOS does.
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
  /// minimum, for instance — so a [HapticIntent] falls to its pattern and
  /// [FlutterHaptics.playSystem] reports that nothing played.
  ///
  /// [support] declines constants on its own where the real platforms would,
  /// so leave this `true` to test a weak actuator rather than a missing API.
  final bool playsSystemHaptics;

  /// Whether [FlutterHaptics.register] can prepare a pattern here.
  final bool canRegister;

  /// The reason returned when [playsSystemHaptics] is false.
  final String declineReason;

  /// Patterns sent through the synthesiser, in order.
  final List<HapticPattern> played = [];

  /// System constants requested, whether or not this fake played them.
  final List<SystemHaptic> systemHaptics = [];

  /// Intents handed to [FlutterHaptics.perform], in order.
  ///
  /// Recorded before the arm is resolved, so this is the meaning the app
  /// asked for rather than what the device made of it:
  ///
  /// ```dart
  /// expect(haptics.intents, [AppHaptics.saved]);   // it asked to confirm
  /// expect(haptics.lastPlayed, AppHaptics.saved.pattern);  // and recovered
  /// ```
  final List<HapticIntent> intents = [];

  /// Ids handed out by [register], in order.
  ///
  /// A record, not a ledger: [clear] empties it and [unregister] does not,
  /// so whether a replay succeeds is tracked separately.
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

  /// Ids the pretend platform is still holding a pattern for.
  ///
  /// Kept apart from [registrations] so that recording and behaviour cannot
  /// interfere: clearing the record must not make a live handle look lost,
  /// and releasing a handle must stop it replaying.
  final Set<int> _live = <int>{};

  /// The most recent pattern sent through the synthesiser, if any.
  ///
  /// Patterns compare by value, so an intent's recovery can be asserted by
  /// name: `expect(haptics.lastPlayed, AppHaptics.saved.pattern)`.
  HapticPattern? get lastPlayed => played.isEmpty ? null : played.last;

  /// The most recent constant requested, if any.
  SystemHaptic? get lastSystemHaptic =>
      systemHaptics.isEmpty ? null : systemHaptics.last;

  /// The most recent intent performed, if any.
  HapticIntent? get lastIntent => intents.isEmpty ? null : intents.last;

  /// Forgets everything recorded, keeping the configured behaviour — and
  /// leaving any live registrations alone, so a handle arranged before the
  /// call still replays after it.
  void clear() {
    played.clear();
    systemHaptics.clear();
    intents.clear();
    requiredPerceptible.clear();
    registrations.clear();
    replays.clear();
    releases.clear();
    prepareCount = 0;
    stopCount = 0;
  }

  /// Drops every live registration without telling the handles that hold
  /// them, which is what Android does when the plugin detaches from its
  /// engine. The next replay fails and the handle falls back to `play`.
  void debugLoseRegistrations() => _live.clear();

  @override
  Future<HapticSupport> querySupport() async => support;

  @override
  Future<NativeResult> play(HapticPattern pattern) async {
    played.add(pattern);

    // Recorded either way: `played` is what the app asked to render, and the
    // return value is what this pretend device made of it.
    if (!support.isSupported) {
      return const NativeResult.failed('this fake has no haptic hardware');
    }

    // What iOS reports on a device whose feedback generators play taps only:
    // a rumble has nothing to sustain it.
    if (!support.supportsContinuous &&
        !pattern.events.any((event) => event is TransientEvent)) {
      return const NativeResult.failed(
        'this device plays taps only, and the pattern has none',
      );
    }

    return const NativeResult.played();
  }

  /// Whether each recorded request asked the device to be second-guessed.
  /// `perform` sets it; `playSystem` does not.
  final List<bool> requiredPerceptible = [];

  @override
  void noteIntent(HapticIntent intent) => intents.add(intent);

  @override
  Future<NativeResult> playSystem(
    SystemHaptic haptic, {
    required bool requirePerceptible,
  }) async {
    systemHaptics.add(haptic);
    requiredPerceptible.add(requirePerceptible);

    if (!playsSystemHaptics) return NativeResult.failed(declineReason);

    // The same gate the real platforms apply: an actuator with no amplitude
    // control may accept a constant and render nothing, so `perform` — which
    // has a pattern to fall back on — is refused where `playSystem` is not.
    if (requirePerceptible && !support.supportsIntensity) {
      return NativeResult.failed(
        'a ${support.fidelity.name}-tier actuator may accept '
        '${haptic.name} without rendering it',
      );
    }

    return const NativeResult.played();
  }

  @override
  Future<int?> register(HapticPattern pattern) async {
    if (!canRegister) return null;
    final id = _nextId++;
    registrations.add(id);
    _live.add(id);
    return id;
  }

  @override
  Future<NativeResult> playRegistered(int id) async {
    replays.add(id);
    // An id this fake is not holding stands in for a lost registration —
    // one never issued, or one already released.
    return _live.contains(id)
        ? const NativeResult.played()
        : const NativeResult.failed('no such registration on this fake');
  }

  @override
  Future<void> unregister(int id) async {
    releases.add(id);
    _live.remove(id);
  }

  @override
  Future<void> prepare() async => prepareCount++;

  @override
  Future<void> stop() async => stopCount++;
}
