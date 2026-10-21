import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

import '../app_haptics.dart';
import '../widgets.dart';

/// Intents — the only thing here that crosses platforms.
///
/// These are defined by this app in `app_haptics.dart`, not by the package.
/// Each press reports which route it actually took, so the difference between
/// the platform's own feedback and this package's recovery is visible rather
/// than guessed at.
class IntentsPage extends StatelessWidget {
  const IntentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Defined by this app',
          blurb: 'The package ships no intents. iOS names nine kinds of '
              'feedback, Android twenty, and almost none of the names match — '
              'so a universal set would be a third vocabulary papering over '
              'that. You name your own meanings and say how each platform '
              'serves them.',
          child: Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              for (final entry in AppHaptics.all.entries)
                RouteButton(
                  label: entry.key,
                  subtitle: _describe(entry.value),
                  explain: (route) => _explain(entry.value, route),
                  onPressed: () => FlutterHaptics.perform(entry.value),
                ),
            ],
          ),
        ),
        Section(
          title: 'Reading the result',
          blurb: 'system means the OS played its own feedback. pattern has '
              'two causes the caption tells apart: the arm chose the pattern, '
              'or it named a constant this device could not deliver. none '
              'means the arm is silent here — deliberate, not a failure.',
          child: const SizedBox.shrink(),
        ),
        Section(
          title: 'The recovery patterns',
          blurb: 'Played directly, bypassing the OS, so you can compare them '
              'against the native route on the same device.',
          child: Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              for (final entry in AppHaptics.all.entries)
                RouteButton(
                  label: '${entry.key} ↩',
                  onPressed: () => FlutterHaptics.play(entry.value.pattern),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _describe(HapticIntent intent) =>
      'iOS ${_arm(intent.ios)} · Android ${_arm(intent.android)}';

  static String _arm(HapticArm<SystemHaptic> arm) => switch (arm) {
        NativeArm(haptic: final haptic) => haptic.name,
        PatternArm() => 'pattern',
        SilentArm() => 'silent',
      };

  /// What happened, which is not always what the declaration suggests. On an
  /// actuator that accepts constants without rendering them, perform skips
  /// the native route entirely — so the arm named above was never attempted.
  static String _explain(HapticIntent intent, HapticRoute route) {
    final arm = intent.armFor(defaultTargetPlatform);

    return switch ((route, arm)) {
      // The arm named a constant and the device delivered it.
      (HapticRoute.system, NativeArm(haptic: final h)) => 'played ${h.name}',
      // The arm chose the pattern — nothing was attempted, nothing failed.
      (HapticRoute.pattern, PatternArm()) => 'pattern, by choice',
      // The arm named a constant the device could not deliver.
      (HapticRoute.pattern, NativeArm(haptic: final h)) =>
        '${h.name} not delivered → pattern',
      (HapticRoute.none, SilentArm()) =>
        'silent on ${defaultTargetPlatform.name}, by choice',
      (HapticRoute.none, _) => 'nothing played',
      _ => route.name,
    };
  }
}
