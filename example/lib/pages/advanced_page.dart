import 'package:flutter/material.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

import '../widgets.dart';

/// Registered handles and AHAP interop — the two things that matter once a
/// pattern is fired often, or authored somewhere other than Dart.
class AdvancedPage extends StatefulWidget {
  const AdvancedPage({super.key});

  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<AdvancedPage> {
  HapticHandle? _tick;
  int _step = 0;
  int _ticks = 0;

  HapticPattern? _boing;
  String? _boingError;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // Registered once, replayed on every step of the slider below.
    final tick = await FlutterHaptics.register(HapticPatterns.selection);
    if (mounted) setState(() => _tick = tick);
  }

  @override
  void dispose() {
    // Handles hold native resources.
    _tick?.dispose();
    super.dispose();
  }

  Future<void> _loadBoing() async {
    try {
      final pattern = await Ahap.loadAsset('assets/haptics/boing.ahap');
      if (mounted) setState(() => _boing = pattern);
      await FlutterHaptics.play(pattern);
    } on Exception catch (error) {
      if (mounted) setState(() => _boingError = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tick = _tick;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Section(
          title: 'Registered handle',
          blurb: 'FlutterHaptics.register hands the pattern to the platform '
              'once. Dragging fires a tick per step without re-serialising or '
              'rebuilding it — this is the shape of a picker or a scrub bar.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: _step.toDouble(),
                min: 0,
                max: 20,
                divisions: 20,
                label: '$_step',
                onChanged: tick == null
                    ? null
                    : (value) {
                        final next = value.round();
                        if (next == _step) return;
                        setState(() {
                          _step = next;
                          _ticks++;
                        });
                        tick.play();
                      },
              ),
              const SizedBox(height: 4),
              Text(
                tick == null
                    ? 'registering…'
                    : 'prepared: ${tick.isPrepared} · ticks played: $_ticks',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (tick != null && !tick.isPrepared)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'This platform could not hold a prepared copy, so the '
                    'handle is sending the pattern each time. It still plays.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        Section(
          title: 'Load an .ahap file',
          blurb: 'assets/haptics/boing.ahap was hand-authored the way a design '
              'tool would export it — a sharp hit, then a decaying wobble '
              'carried by an intensity curve. It plays through the same '
              'Android ladder as any other pattern.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ActionRow(actions: {'Load and play boing.ahap': _loadBoing}),
              if (_boingError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _boingError!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              if (_boing != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Decoded ${_boing!.events.length} events, '
                  '${_boing!.duration.inMilliseconds} ms total.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        Section(
          title: 'Write an .ahap file',
          blurb: 'Ahap.encode turns any pattern into a valid .ahap — which is '
              'also how you serialise a pattern to disk or over a network.',
          child: CodeBox(text: Ahap.encode(HapticPatterns.explosion)),
        ),
      ],
    );
  }
}
