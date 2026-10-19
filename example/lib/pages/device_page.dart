import 'package:flutter/material.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

import '../widgets.dart';

/// What this handset can actually do, and the app-wide switch.
///
/// Both platforms answer in the same vocabulary, so nothing on this page
/// branches on `Platform.isAndroid`.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  HapticSupport? _support;
  bool _enabled = FlutterHaptics.enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final support = await FlutterHaptics.support;
    if (mounted) setState(() => _support = support);
  }

  @override
  Widget build(BuildContext context) {
    final support = _support;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'What this device reports',
          blurb: 'FlutterHaptics.support — queried once, then cached.',
          child: support == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              : _SupportCard(support: support),
        ),
        Section(
          title: 'App-wide switch',
          blurb: 'FlutterHaptics.enabled — what your settings screen would '
              'drive. Turn it off and every trigger in this app goes quiet, '
              'with no guard at any call site.',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Haptics enabled'),
            value: _enabled,
            onChanged: (value) => setState(() {
              _enabled = value;
              FlutterHaptics.enabled = value;
            }),
          ),
        ),
        Section(
          title: 'Engine warm-up',
          blurb: 'FlutterHaptics.prepare() removes the start-up cost from the '
              'first play on iOS. No-op on Android, which has no engine.',
          child: ActionRow(actions: {'prepare()': FlutterHaptics.prepare}),
        ),
        Section(
          title: 'Stop',
          blurb: 'Cancels whatever is playing. Works even while the switch '
              'above is off, so turning haptics off can silence a pattern '
              'that is already running.',
          child: ActionRow(
            actions: {
              'Long pattern': () =>
                  FlutterHaptics.play(HapticPatterns.chargeUp),
              'stop()': FlutterHaptics.stop,
            },
          ),
        ),
      ],
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.support});

  final HapticSupport support;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  support.isSupported
                      ? Icons.vibration
                      : Icons.do_not_disturb_on_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  'fidelity: ${support.fidelity.name}',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Fact('Anything plays at all', support.isSupported),
            _Fact('Per-event intensity survives', support.supportsIntensity),
            _Fact('Sharpness survives', support.supportsSharpness),
            _Fact('A rumble can sustain', support.supportsContinuous),
            const SizedBox(height: 12),
            Text(
              _explain(support),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  static String _explain(HapticSupport support) => switch (support.fidelity) {
        HapticFidelity.full =>
          'Curves reproduce faithfully — Core Haptics, or Android 16 envelope '
              'hardware. Design for this tier.',
        HapticFidelity.intensity =>
          'Intensity survives but sharpness does not, so patterns read by '
              'their rhythm and strength rather than their texture.',
        HapticFidelity.rhythm =>
          'A single-speed actuator: only timing comes through. Usually a '
              'rotary (ERM) motor, which happens on new budget handsets too.',
        HapticFidelity.none =>
          'No haptic hardware. Every call still succeeds silently, so nothing '
              'here needs a platform check.',
      };
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_circle : Icons.remove_circle_outline,
            size: 18,
            color: value
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
