import 'package:flutter/foundation.dart';

import 'haptic_event.dart';

/// An immutable sequence of haptic events.
///
/// Patterns are composable using [then], [overlay], and [repeat].
@immutable
class HapticPattern {
  /// The events that make up this pattern.
  final List<HapticEvent> events;

  /// Creates a pattern from a list of events.
  ///
  /// The list is kept as given, not copied — a copy would rule out `const`.
  /// Changing it afterwards changes this pattern, its equality and its
  /// hash, so pass a list nothing else will change: a literal, or
  /// `List.unmodifiable(events)`. Every pattern this package builds for you,
  /// including the ones [then], [overlay], [repeat] and [scaled] return,
  /// already holds one.
  const HapticPattern(this.events);

  /// Creates a pattern with a single event.
  HapticPattern.single(HapticEvent event) : events = List.unmodifiable([event]);

  /// Creates a pattern that resolves per platform at creation time.
  ///
  /// Use this when a pattern needs different tuning on Android hardware:
  ///
  /// ```dart
  /// final explosion = HapticPattern.forPlatform(
  ///   ios: HapticPatterns.explosion,
  ///   android: myAndroidTunedExplosion,
  /// );
  /// await FlutterHaptics.play(explosion);
  /// ```
  ///
  /// If [android] is omitted, the [ios] pattern is used on all platforms.
  factory HapticPattern.forPlatform({
    required HapticPattern ios,
    HapticPattern? android,
  }) => switch (defaultTargetPlatform) {
    TargetPlatform.android => android ?? ios,
    _ => ios,
  };

  /// Empty pattern (no-op).
  static const empty = HapticPattern([]);

  /// Total duration of the pattern, from its start to the end of its last
  /// event.
  ///
  /// A closing transient counts as [HapticEvent.transientWidth] wide, so
  /// [then] and [repeat] place the next event after it rather than on top
  /// of it.
  Duration get duration {
    if (events.isEmpty) return Duration.zero;

    Duration maxEnd = Duration.zero;
    for (final event in events) {
      if (event.end > maxEnd) maxEnd = event.end;
    }
    return maxEnd;
  }

  /// Chain patterns sequentially (this pattern, then other).
  HapticPattern then(HapticPattern other) {
    if (events.isEmpty) return other;
    if (other.events.isEmpty) return this;

    final totalDuration = duration;
    final shiftedEvents = other.events.map((e) => e.delayed(totalDuration));

    return HapticPattern(List.unmodifiable([...events, ...shiftedEvents]));
  }

  /// Overlay patterns (play simultaneously).
  HapticPattern overlay(HapticPattern other) {
    return HapticPattern(List.unmodifiable([...events, ...other.events]));
  }

  /// Repeat this pattern n times with optional gap between repetitions.
  HapticPattern repeat(int times, {Duration gap = Duration.zero}) {
    if (times <= 0) return empty;
    if (times == 1) return this;

    final patternDuration = duration;
    final repeatOffset = patternDuration + gap;

    final allEvents = <HapticEvent>[];
    for (var i = 0; i < times; i++) {
      final offset = repeatOffset * i;
      for (final event in events) {
        allEvents.add(event.delayed(offset));
      }
    }

    return HapticPattern(List.unmodifiable(allEvents));
  }

  /// Scale intensity of all events.
  HapticPattern scaled(double factor) {
    return HapticPattern(
      List.unmodifiable(events.map((e) => e.scaled(factor))),
    );
  }

  /// Operator for sequential composition.
  HapticPattern operator +(HapticPattern other) => then(other);

  /// Operator for parallel composition (overlay).
  HapticPattern operator |(HapticPattern other) => overlay(other);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HapticPattern && listEquals(events, other.events);

  @override
  int get hashCode => Object.hashAll(events);
}
