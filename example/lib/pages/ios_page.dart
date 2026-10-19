import 'package:flutter/material.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

import '../widgets.dart';

/// UIKit's own vocabulary — the nine kinds iOS defines.
///
/// Nothing here plays on Android, for the same reason the Android tab plays
/// nothing on iOS: `playSystem` is deliberately single-platform.
class IOSPage extends StatelessWidget {
  const IOSPage({super.key});

  @override
  Widget build(BuildContext context) {
    const impacts = [
      IOSHaptic.impactLight,
      IOSHaptic.impactMedium,
      IOSHaptic.impactHeavy,
      IOSHaptic.impactRigid,
      IOSHaptic.impactSoft,
    ];
    const notifications = [
      IOSHaptic.notificationSuccess,
      IOSHaptic.notificationWarning,
      IOSHaptic.notificationError,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Impact',
          blurb: 'UIImpactFeedbackGenerator. Collision weight, from light to '
              'heavy, plus two that change the texture instead of the force.',
          child: _row(impacts),
        ),
        Section(
          title: 'Notification',
          blurb: 'UINotificationFeedbackGenerator. Android has a constant for '
              'success and one for failure, but nothing at all for warning — '
              'that middle one has no counterpart anywhere.',
          child: _row(notifications),
        ),
        Section(
          title: 'Selection',
          blurb: 'UISelectionFeedbackGenerator — a picker moving one step.',
          child: _row(const [IOSHaptic.selection]),
        ),
        Section(
          title: 'On Android',
          blurb: 'Every button above reports none here. These are iOS values, '
              'and playSystem never substitutes anything. Use the Intents tab '
              'to see how the two vocabularies get paired.',
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _row(List<IOSHaptic> haptics) => Wrap(
        spacing: 8,
        runSpacing: 12,
        children: [
          for (final haptic in haptics)
            RouteButton(
              label: haptic.name,
              onPressed: () => FlutterHaptics.playSystem(haptic),
            ),
        ],
      );
}
