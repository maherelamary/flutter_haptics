## 1.0.0

First release.

### Three verbs

- `play(HapticPattern)` — a waveform you compose, rendered as well as the
  device allows. Returns `HapticRoute.pattern` or `none`.
- `playSystem(SystemHaptic)` — one platform's own constant, on that platform
  only. The argument's type carries the platform, so there is no `ios:`/
  `android:` pair and no way to pass the wrong one. Never falls back.
- `perform(HapticIntent)` — a meaning: the native route you declared for this
  platform, with your pattern where it could not be delivered.

None of them throws. Each returns a `HapticRoute` — `system`, `pattern` or
`none` — which you are free to ignore.

### Both platform vocabularies, unflattened

`IOSHaptic` names the nine kinds UIKit defines. `AndroidHaptic` names the
twenty playable `HapticFeedbackConstants`, twelve of which iOS has no concept
for. Almost none of the names correspond, and this package does not invent a
third vocabulary to hide that. Every value carries the OS version its constant
arrived in, checked for you, so no caller writes a version check.

`HapticIntent` is how you pair them, in your own words:

```dart
static const saved = HapticIntent(
  ios: IOSHaptic.notificationSuccess,
  android: AndroidHaptic.confirm,    // needs API 30
  pattern: HapticPatterns.success,   // recovery below that
);
```

The pattern is a **recovery, not a substitute**: it covers a route you asked
for and did not get, and a `null` arm means that platform plays nothing on
purpose.

### Patterns

- `HapticPattern` from transient and continuous events, with intensity and
  sharpness that may follow curves over the life of an event.
- `HapticPatternBuilder` for building one fluently, and `HapticPatterns` for
  twenty ready-made ones.
- Composition with `then`, `overlay`, `repeat`, `scaled` and the `+` and `|`
  operators, plus `HapticPattern.forPlatform` for per-platform tuning.
- `Ahap.decode` / `encode` / `loadAsset` read and write Apple's `.ahap`
  format, so patterns can be authored in design tools — and `encode` doubles
  as pattern serialisation.
- `register(pattern)` returns a `HapticHandle` the platform holds ready, for
  anything replayed often: a picker tick, a scrub bar, a game loop.

### Knowing what happened

- `support` reports what the device can actually reproduce, in one vocabulary
  both platforms answer in: `HapticFidelity.full`, `intensity`, `rhythm` or
  `none`, plus `supportsContinuous`.
- `enabled` is an app-wide switch, so a "Haptics" setting needs no guard at
  any call site.
- `onFailure` decides what happens when a haptic could not be delivered:
  `silent`, `log` or `throwIt`. Defaults to logging while debugging and
  silence in release.
- `package:flutter_haptics/testing.dart` ships `FakeHapticsPlatform`, which
  plays nothing and records everything, so an app can assert on its own
  haptics without a method channel.

### Rendering

Android walks a capability ladder, picking the best rendering the hardware can
actually play: intensity/sharpness envelopes on API 36 hardware, vendor-tuned
composition primitives on API 30+, a sampled amplitude waveform on API 26+,
and an on/off waveform or the legacy call below that. Transients are widened
on the on/off path, where a rotating mass needs tens of milliseconds to spin
up at all.

iOS renders through Core Haptics, falling back to UIKit feedback generators on
devices without it. Intensity, sharpness and parameter curves all survive the
Core Haptics path.

### Requirements

iOS 15, Android 7 (API 24) — the floors Flutter itself uses, so depending on
this package raises neither.
