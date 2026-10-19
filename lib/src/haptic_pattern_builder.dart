import 'haptic_event.dart';
import 'haptic_param.dart';
import 'haptic_pattern.dart';

/// A builder for creating haptic patterns fluently.
///
/// Example:
/// ```dart
/// final pattern = HapticPatternBuilder()
///   .tap(intensity: 0.6)
///   .wait(Duration(milliseconds: 50))
///   .tap(intensity: 1.0)
///   .build();
/// ```
class HapticPatternBuilder {
  final List<HapticEvent> _events = [];
  Duration _cursor = Duration.zero;

  /// Add a transient tap/click.
  ///
  /// Advances the cursor by [HapticEvent.transientWidth], the same way
  /// [rumble] advances it by its duration, so consecutive `tap()` calls
  /// produce separate taps rather than landing on one instant. A [wait] adds
  /// to that gap rather than replacing it.
  HapticPatternBuilder tap({
    double intensity = 0.7,
    double sharpness = 0.5,
  }) {
    _events.add(TransientEvent(
      intensity: intensity,
      sharpness: sharpness,
      delay: _cursor,
    ));
    _cursor += HapticEvent.transientWidth;
    return this;
  }

  /// Add a continuous rumble with constant intensity.
  HapticPatternBuilder rumble({
    required Duration duration,
    double intensity = 0.7,
    double sharpness = 0.5,
  }) {
    _events.add(ContinuousEvent(
      intensity: intensity,
      sharpness: sharpness,
      duration: duration,
      delay: _cursor,
    ));
    _cursor += duration;
    return this;
  }

  /// Add a continuous rumble with curved intensity.
  HapticPatternBuilder rumbleCurved({
    required Duration duration,
    required HapticParam intensity,
    HapticParam sharpness = const ConstantParam(0.5),
  }) {
    _events.add(ContinuousEvent.curved(
      intensity: intensity,
      sharpness: sharpness,
      duration: duration,
      delay: _cursor,
    ));
    _cursor += duration;
    return this;
  }

  /// Wait before the next event.
  HapticPatternBuilder wait(Duration duration) {
    _cursor += duration;
    return this;
  }

  /// Wait in milliseconds (convenience).
  HapticPatternBuilder waitMs(int milliseconds) {
    _cursor += Duration(milliseconds: milliseconds);
    return this;
  }

  /// Add a fade-in rumble.
  HapticPatternBuilder fadeIn({
    required Duration duration,
    double sharpness = 0.5,
  }) {
    return rumbleCurved(
      duration: duration,
      intensity: HapticParam.fadeIn,
      sharpness: ConstantParam(sharpness),
    );
  }

  /// Add a fade-out rumble.
  HapticPatternBuilder fadeOut({
    required Duration duration,
    double sharpness = 0.5,
  }) {
    return rumbleCurved(
      duration: duration,
      intensity: HapticParam.fadeOut,
      sharpness: ConstantParam(sharpness),
    );
  }

  /// Add a pulse rumble.
  HapticPatternBuilder pulse({
    required Duration duration,
    double sharpness = 0.5,
  }) {
    return rumbleCurved(
      duration: duration,
      intensity: HapticParam.pulse,
      sharpness: ConstantParam(sharpness),
    );
  }

  /// Build the pattern.
  HapticPattern build() => HapticPattern(List.unmodifiable(_events));
}
