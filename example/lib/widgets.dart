import 'package:flutter/material.dart';
import 'package:flutter_haptics/flutter_haptics.dart';

/// A titled block with an optional explanation, used by every page so the
/// demo reads as one document rather than a pile of buttons.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    this.blurb,
    required this.child,
  });

  final String title;
  final String? blurb;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (blurb != null) ...[
            const SizedBox(height: 4),
            Text(
              blurb!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A row of wrapped action chips. Every demo trigger in the app is one of
/// these, so the pages stay comparable.
class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.actions});

  final Map<String, VoidCallback> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in actions.entries)
          FilledButton.tonal(
            onPressed: entry.value,
            child: Text(entry.key),
          ),
      ],
    );
  }
}

/// Monospaced, scrollable text — for showing generated AHAP.
class CodeBox extends StatelessWidget {
  const CodeBox({super.key, required this.text, this.maxHeight = 260});

  final String text;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
        ),
      ),
    );
  }
}

/// A button that plays something and then shows which route it took.
///
/// The route is the point of these pages: the same press can reach the
/// platform's own feedback, this package's synthesiser, or nothing at all,
/// and only the returned [HapticRoute] tells you which.
class RouteButton extends StatefulWidget {
  const RouteButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.explain,
  });

  final String label;

  /// Shown before anything is pressed.
  final String? subtitle;

  /// Shown instead of [subtitle] once a route is known, so the label says
  /// what happened rather than what was declared.
  final String Function(HapticRoute route)? explain;

  final Future<HapticRoute> Function() onPressed;

  @override
  State<RouteButton> createState() => _RouteButtonState();
}

class _RouteButtonState extends State<RouteButton> {
  HapticRoute? _route;

  /// The declaration until something is pressed, then what actually happened.
  String? get _caption {
    final route = _route;
    if (route != null && widget.explain != null) return widget.explain!(route);
    return widget.subtitle;
  }

  static (Color, Color, String) _style(ColorScheme scheme, HapticRoute route) =>
      switch (route) {
        HapticRoute.system => (scheme.primaryContainer, scheme.onPrimaryContainer, 'system'),
        HapticRoute.pattern => (scheme.tertiaryContainer, scheme.onTertiaryContainer, 'pattern'),
        HapticRoute.none => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, 'none'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = _route;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.tonal(
          onPressed: () async {
            final result = await widget.onPressed();
            if (mounted) setState(() => _route = result);
          },
          child: Text(widget.label),
        ),
        if (_caption != null || route != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (route != null) ...[
                  Builder(
                    builder: (context) {
                      final (bg, fg, text) = _style(theme.colorScheme, route);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          text,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: fg,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                ],
                if (_caption != null)
                  Text(
                    _caption!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
