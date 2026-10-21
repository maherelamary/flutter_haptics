import 'package:clock/clock.dart';

import 'flutter_haptics.dart';
import 'haptic_pattern.dart';
import 'haptic_route.dart';
import 'haptic_support.dart';
import 'platform.dart';

/// A pattern the platform holds ready to replay, with a floor on how often
/// it will actually fire.
///
/// [FlutterHaptics.play] serialises a pattern, ships it across the channel and
/// has the platform build it again on every call. That is fine for a button,
/// and wasteful for anything firing repeatedly — a scroll picker, a step
/// counter, a game loop. On iOS it means constructing a `CHHapticPattern` and
/// a player each time.
///
/// ```dart
/// final tick = FlutterHaptics.register(HapticPatterns.selection);
///
/// void onItemChanged() => tick.play();
///
/// @override
/// void dispose() {
///   tick.dispose();
///   super.dispose();
/// }
/// ```
///
/// Created synchronously so it can be built in `initState` or a field
/// initialiser without an `await`. Registration happens in the background;
/// a [play] that arrives first simply waits for it. Use a plain `final`
/// rather than `late final`, which would defer the registration to the first
/// play and so give up the round trip this exists to save.
///
/// ## Pacing
///
/// A handle will not replay faster than [minInterval]. Taps arriving closer
/// together than the actuator can separate do not read as separate taps —
/// they smear into a buzz — and every one still crosses the platform
/// channel. A paced handle drops the ones that would not have been felt as
/// distinct, reporting [HapticRoute.none] for them.
///
/// The default comes from what the device says it can do, never from which
/// platform it is:
///
/// | `support.fidelity` | Default |
/// |---|---|
/// | [HapticFidelity.full] | 25 ms — one [HapticEvent.transientWidth] |
/// | [HapticFidelity.intensity] | 35 ms |
/// | [HapticFidelity.rhythm] | 60 ms — taps are widened to 50 ms here |
/// | not yet known | 40 ms, conservatively, until it resolves |
///
/// Pass `minInterval: Duration.zero` to opt out and fire every call.
///
/// Pacing is measured with `package:clock`, which `testWidgets` advances when
/// a test pumps. A widget test that pumps between two plays therefore sees
/// the gap it asked for rather than the handful of real milliseconds the
/// pumps actually took.
final class HapticHandle {
  HapticHandle._(this.pattern, this._minInterval) {
    _ready = _resolve();
  }

  /// The pattern this handle plays.
  final HapticPattern pattern;

  /// Explicit pacing floor, or null to take it from the device's fidelity.
  final Duration? _minInterval;

  /// Until [support] resolves, pace conservatively rather than guessing fast.
  static const _unknownDeviceInterval = Duration(milliseconds: 40);

  late final Future<void> _ready;
  Future<int?>? _registration;
  int? _id;
  Duration? _resolvedInterval;
  DateTime? _lastPlayed;
  bool _disposed = false;

  /// Creates a handle. Internal — use [FlutterHaptics.register].
  static HapticHandle internal(HapticPattern pattern, Duration? minInterval) =>
      HapticHandle._(pattern, minInterval);

  /// Completes once the platform has answered and [minInterval] has settled.
  ///
  /// Nothing has to await this — [play] works from the first frame, waiting
  /// on the registration itself if it beats it. It is here for a UI that
  /// *displays* what the handle resolved to, such as the example app, which
  /// would otherwise show the conservative defaults until the first play:
  ///
  /// ```dart
  /// _tick.ready.then((_) => setState(() {}));
  /// ```
  ///
  /// Never completes with an error.
  Future<void> get ready => _ready;

  /// Starts registration and the capability query without blocking the
  /// caller. The work before the first `await` runs synchronously, so
  /// [_registration] is set by the time the constructor returns.
  Future<void> _resolve() async {
    final registration = pattern.events.isEmpty
        ? null
        : FlutterHapticsPlatform.instance.register(pattern);

    // Guarded, not raw. [play] and [dispose] await this future, so a platform
    // that breaks the seam's no-throw contract would otherwise make every
    // later call rethrow rather than fall back to sending the pattern.
    final guarded = registration?.catchError((Object _) => null);
    _registration = guarded;

    try {
      await Future.wait<void>([
        if (guarded != null) guarded.then<void>((id) => _id = id),
        if (_minInterval == null)
          FlutterHaptics.support
              .then<void>((s) => _resolvedInterval = _intervalFor(s)),
      ]);
    } on Object {
      // Only reachable through a broken custom platform, and only for the
      // capability query now. Swallowed so that a [ready] nobody awaited
      // cannot surface as an unhandled error; the handle stays unprepared
      // and conservatively paced, which is usable.
    }
  }

  /// The floor currently in force.
  ///
  /// Settles once [FlutterHaptics.support] resolves, unless an explicit
  /// interval was given, in which case it never moves.
  Duration get minInterval =>
      _minInterval ?? _resolvedInterval ?? _unknownDeviceInterval;

  static Duration _intervalFor(HapticSupport support) => switch (support.fidelity) {
        // One tap width: anything closer is one tap as far as the actuator
        // is concerned.
        HapticFidelity.full => const Duration(milliseconds: 25),
        HapticFidelity.intensity => const Duration(milliseconds: 35),
        // Transients are widened to 50 ms on this tier, so they need a gap.
        HapticFidelity.rhythm => const Duration(milliseconds: 60),
        HapticFidelity.none => const Duration(milliseconds: 40),
      };

  /// Whether the platform is holding a prepared copy of [pattern].
  ///
  /// `false` while registration is still in flight, permanently on a platform
  /// that cannot hold one, and again if the platform loses it — where [play]
  /// still works, just without the saving.
  bool get isPrepared => _id != null && !_disposed;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Play the pattern, unless it would arrive within [minInterval] of the
  /// last one.
  ///
  /// Obeys [FlutterHaptics.enabled]. A disposed handle, a paced-out call and
  /// a device that cannot play all report [HapticRoute.none].
  Future<HapticRoute> play() async {
    if (_disposed || !FlutterHaptics.enabled) return HapticRoute.none;

    final now = clock.now();
    final last = _lastPlayed;
    if (last != null) {
      final since = now.difference(last);
      // A negative gap means the clock moved backwards — an NTP correction,
      // a manual time change. Play rather than muting the handle until the
      // clock catches up with where it used to be.
      if (!since.isNegative && since < minInterval) return HapticRoute.none;
    }
    _lastPlayed = now;

    // A play that beats registration waits for it rather than racing it.
    final id = _id ?? await _registration;
    if (_disposed) return HapticRoute.none;
    if (id == null) return FlutterHaptics.play(pattern);

    final result = await FlutterHapticsPlatform.instance.playRegistered(id);
    if (result.played) return HapticRoute.pattern;

    // The registration is gone — Android clears them when the plugin detaches
    // from its engine. Forget it, so later plays do not pay a round trip to
    // rediscover the same thing and `isPrepared` stops claiming otherwise.
    _id = null;
    _registration = null;

    // Sending the pattern the long way still gets it played.
    if (_disposed) return HapticRoute.none;
    return FlutterHaptics.play(pattern);
  }

  /// Release the platform's copy of the pattern.
  ///
  /// Safe to call more than once. After this, [play] does nothing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final id = _id ?? await _registration;
    if (id == null) return;
    _id = null;
    _registration = null;

    await FlutterHapticsPlatform.instance.unregister(id);
  }

  @override
  String toString() => 'HapticHandle('
      '${_disposed ? 'disposed' : isPrepared ? 'prepared' : 'preparing'}, '
      '${pattern.events.length} events, every ${minInterval.inMilliseconds}ms)';
}
