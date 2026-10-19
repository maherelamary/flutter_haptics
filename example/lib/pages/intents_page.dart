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
          blurb: 'system means the OS played its own feedback. pattern means '
              'the route was asked for and could not be delivered, so the '
              'intent recovered. none means this intent asks for nothing on '
              'this platform — a deliberate silence, not a failure.',
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

  static String _describe(HapticIntent intent) {
    final ios = intent.ios?.name ?? '—';
    final android = intent.android?.name ?? '—';
    return 'iOS $ios · Android $android';
  }

  /// What happened, which is not always what the declaration suggests. On an
  /// actuator that accepts constants without rendering them, perform skips
  /// the native route entirely — so the arm named above was never attempted.
  static String _explain(HapticIntent intent, HapticRoute route) {
    final arm = intent.routeFor(defaultTargetPlatform)?.name;

    return switch (route) {
      HapticRoute.system => 'played $arm',
      HapticRoute.pattern => arm == null
          ? 'pattern'
          : '$arm not delivered → pattern',
      HapticRoute.none => arm == null
          ? 'nothing declared for ${defaultTargetPlatform.name}'
          : 'nothing played',
    };
  }
}
