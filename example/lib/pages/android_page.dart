import 'package:flutter/material.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

import '../widgets.dart';

/// Android's own vocabulary — all twenty `HapticFeedbackConstants`.
///
/// Nothing here plays on iOS. `playSystem` takes a value whose type names the
/// platform it belongs to, so on iOS every button reports `none` by design.
/// That is the asymmetry made visible rather than hidden behind a pattern.
class AndroidPage extends StatefulWidget {
  const AndroidPage({super.key});

  @override
  State<AndroidPage> createState() => _AndroidPageState();
}

class _AndroidPageState extends State<AndroidPage> {
  HapticSupport? _support;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final support = await FlutterHaptics.support;
    if (mounted) setState(() => _support = support);
  }

  /// Grouped by the SDK level each constant arrived in, because that is what
  /// decides whether a given handset can play it at all.
  static final _byVersion = <int, List<AndroidHaptic>>{
    for (final haptic in AndroidHaptic.values)
      haptic.minimumVersion: [
        ...?_collect(haptic.minimumVersion),
      ],
  };

  static List<AndroidHaptic>? _collect(int version) => AndroidHaptic.values
      .where((h) => h.minimumVersion == version)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final versions = _byVersion.keys.toList()..sort();
    final theme = Theme.of(context);
    final weakActuator = _support?.fidelity == HapticFidelity.rhythm;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (weakActuator)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This actuator has no amplitude control and no '
                        'composition primitives. Android still accepts these '
                        'constants on such hardware, but may not render them: '
                        'the chip reports what Android answered, which is not '
                        'the same as what you felt, and no API reports the '
                        'second. Press them and find out — that is what this '
                        'tab is for.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Section(
          title: 'Twenty constants, not nine',
          blurb: 'Android defines its own haptic vocabulary, and twelve of '
              'these have no iOS equivalent at all. Each needs the SDK level '
              'it is grouped under; below that the device cannot play it and '
              'the button reports none. On iOS every button here reports '
              'none, because these values belong to Android.\n\n'
              'These constants are implemented by the device vendor for this '
              'device, so playSystem hands the request straight over rather '
              'than judging whether the hardware can manage it. If a button '
              'reports system but you feel nothing, the vendor accepted a '
              'constant it does not render — or the phone\'s own touch '
              'feedback is switched off in system settings.',
          child: const SizedBox.shrink(),
        ),
        for (final version in versions)
          Section(
            title: 'API $version and up',
            blurb: _blurbFor(version),
            child: Wrap(
              spacing: 8,
              runSpacing: 12,
              children: [
                for (final haptic in _byVersion[version]!)
                  RouteButton(
                    label: haptic.name,
                    onPressed: () => FlutterHaptics.playSystem(haptic),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static String? _blurbFor(int version) => switch (version) {
        1 || 5 || 8 => 'Present on every device this package supports.',
        21 || 23 => 'The selection tick and the firm confirmation press.',
        27 => 'Key down and key up as separate events — iOS has no release '
            'event at all.',
        30 => 'Outcomes and gesture boundaries.',
        34 => 'The newest set: toggles, drags and segment ticks. A device on '
            'API 31 reports none for all of these.',
        _ => null,
      };
}
