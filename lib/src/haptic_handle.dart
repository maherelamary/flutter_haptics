import 'flutter_haptics.dart';
import 'haptic_pattern.dart';
import 'haptic_route.dart';
import 'platform.dart';

/// A pattern the platform has already built and is holding ready to replay.
///
/// [FlutterHaptics.play] serialises a pattern, ships it across the channel and
/// has the platform build it again on every call. That is fine for a button,
/// and wasteful for anything firing repeatedly — a scroll picker, a step
/// counter, a game loop. On iOS in particular it means constructing a
/// `CHHapticPattern` and a player each time.
///
/// A handle does that work once:
///
/// ```dart
/// final tick = await FlutterHaptics.register(HapticPatterns.selection);
///
/// void onItemChanged() => tick.play();   // no rebuild, no re-serialisation
///
/// @override
/// void dispose() {
///   tick.dispose();
///   super.dispose();
/// }
/// ```
///
/// A handle plays *exactly* what [FlutterHaptics.play] would — same pattern,
/// same layering when replays overlap. The only difference is how it gets
/// there: nothing is serialised, sent or rebuilt per call.
///
/// Handles hold native resources. Call [dispose] when the owning widget or
/// controller goes away.
final class HapticHandle {
  HapticHandle._(this._id, this.pattern);

  /// A handle for a platform that could not register the pattern.
  ///
  /// [play] still works — it falls back to [FlutterHaptics.play] — so a caller
  /// never has to check whether registration succeeded.
  HapticHandle._unregistered(this.pattern) : _id = null;

  final int? _id;

  /// The pattern this handle plays.
  final HapticPattern pattern;

  bool _disposed = false;

  /// Whether the platform is holding a prepared copy of [pattern].
  ///
  /// `false` means [play] falls back to sending the pattern each time, which
  /// still plays correctly, just without the saving.
  bool get isPrepared => _id != null && !_disposed;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Creates a handle. Internal — use [FlutterHaptics.register].
  static HapticHandle internal(int? id, HapticPattern pattern) =>
      id == null ? HapticHandle._unregistered(pattern) : HapticHandle._(id, pattern);

  /// Play the pattern.
  ///
  /// Obeys [FlutterHaptics.enabled] and fails silently, exactly like
  /// [FlutterHaptics.play]. Playing a disposed handle does nothing and
  /// returns [HapticRoute.none].
  Future<HapticRoute> play() async {
    if (_disposed || !FlutterHaptics.enabled) return HapticRoute.none;

    final id = _id;
    if (id == null) return FlutterHaptics.play(pattern);

    try {
      await FlutterHapticsPlatform.instance.playRegistered(id);
      return HapticRoute.pattern;
    } catch (_) {
      // The registration may have been lost — a rebuilt engine, a detached
      // plugin. Sending the pattern the long way still gets it played.
      return FlutterHaptics.play(pattern);
    }
  }

  /// Release the platform's copy of the pattern.
  ///
  /// Safe to call more than once. After this, [play] does nothing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final id = _id;
    if (id == null) return;

    await FlutterHapticsPlatform.instance.unregister(id);
  }

  @override
  String toString() =>
      'HapticHandle(${_disposed ? 'disposed' : isPrepared ? 'prepared' : 'unprepared'}, '
      '${pattern.events.length} events)';
}
