import 'package:flutter/material.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

import '../widgets.dart';

/// The built-in library, composition operators, and the fluent builder.
class PatternsPage extends StatelessWidget {
  const PatternsPage({super.key});

  Map<String, VoidCallback> _play(Map<String, HapticPattern> patterns) => {
        for (final entry in patterns.entries)
          entry.key: () => FlutterHaptics.play(entry.value),
      };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Taps',
          child: ActionRow(
            actions: _play({
              'light': HapticPatterns.lightTap,
              'medium': HapticPatterns.mediumTap,
              'heavy': HapticPatterns.heavyTap,
              'soft': HapticPatterns.soft,
              'rigid': HapticPatterns.rigid,
            }),
          ),
        ),
        Section(
          title: 'UI feedback',
          child: ActionRow(
            actions: _play({
              'selection': HapticPatterns.selection,
              'double': HapticPatterns.doubleClick,
              'triple': HapticPatterns.tripleClick,
            }),
          ),
        ),
        Section(
          title: 'Notifications',
          blurb: 'Synthesised here, unlike the System tab — compare them.',
          child: ActionRow(
            actions: _play({
              'success': HapticPatterns.success,
              'warning': HapticPatterns.warning,
              'error': HapticPatterns.error,
            }),
          ),
        ),
        Section(
          title: 'Expressive',
          child: ActionRow(
            actions: _play({
              'heartbeat': HapticPatterns.heartbeat,
              'buzz': HapticPatterns.buzz,
              'long buzz': HapticPatterns.longBuzz,
            }),
          ),
        ),
        Section(
          title: 'Parameter curves',
          blurb: 'Intensity and sharpness moving over the life of one event. '
              'These are the patterns that need fidelity "full" to read the '
              'way they were designed.',
          child: ActionRow(
            actions: _play({
              'explosion': HapticPatterns.explosion,
              'engine rev': HapticPatterns.engineRev,
              'pulse wave': HapticPatterns.pulseWave,
              'impact decay': HapticPatterns.impactDecay,
              'charge up': HapticPatterns.chargeUp,
            }),
          ),
        ),
        Section(
          title: 'Composition',
          blurb: 'then / overlay / repeat / scaled, and the + and | operators. '
              'A closing tap counts 25 ms wide, so chained patterns never '
              'stack two events on the same instant.',
          child: ActionRow(
            actions: _play({
              'success → buzz': HapticPatterns.success.then(HapticPatterns.buzz),
              'heartbeat ×3': HapticPatterns.heartbeat
                  .repeat(3, gap: const Duration(milliseconds: 350)),
              'double @ 50%': HapticPatterns.doubleClick.scaled(0.5),
              'tap | rumble':
                  HapticPatterns.heavyTap | HapticPatterns.longBuzz,
              'error + success':
                  HapticPatterns.error + HapticPatterns.success,
            }),
          ),
        ),
        Section(
          title: 'Builder',
          blurb: 'HapticPatternBuilder, where wait() is a gap after the '
              'previous step rather than an absolute offset.',
          child: ActionRow(
            actions: _play({
              'staircase': HapticPatternBuilder()
                  .tap(intensity: 0.4)
                  .waitMs(60)
                  .tap(intensity: 0.7)
                  .waitMs(60)
                  .tap(intensity: 1.0)
                  .waitMs(80)
                  .rumble(
                    duration: const Duration(milliseconds: 200),
                    intensity: 0.5,
                  )
                  .build(),
              'swell': HapticPatternBuilder()
                  .fadeIn(duration: const Duration(milliseconds: 300))
                  .fadeOut(duration: const Duration(milliseconds: 300))
                  .build(),
              'triple tap': HapticPatternBuilder().tap().tap().tap().build(),
            }),
          ),
        ),
        Section(
          title: 'Per-platform tuning',
          blurb: 'HapticPattern.forPlatform, for the rare pattern that needs '
              'different shaping on Android hardware.',
          child: ActionRow(
            actions: _play({
              'tuned explosion': HapticPattern.forPlatform(
                ios: HapticPatterns.explosion,
                android: HapticPatternBuilder()
                    .rumbleCurved(
                      intensity: HapticParam.spike,
                      duration: const Duration(milliseconds: 400),
                    )
                    .build(),
              ),
            }),
          ),
        ),
      ],
    );
  }
}
