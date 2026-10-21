# FlutterHaptics

A powerful, type-safe haptic feedback library for Flutter. Create rich, customizable haptic patterns using Core Haptics on iOS and haptic envelopes on Android.

[![pub package](https://img.shields.io/pub/v/flutter_haptics.svg)](https://pub.dev/packages/flutter_haptics)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue.svg)](https://pub.dev/packages/flutter_haptics)

## Features

- **Pattern-based API** - Haptics are defined as composable, reusable patterns
- **Parameter curves** - Intensity and sharpness can change over time (fade in, fade out, pulse, etc.)
- **Built-in patterns** - 19 ready-to-use patterns for common use cases
- **Fluent builder** - Create complex patterns with an intuitive builder API
- **Type-safe** - Full compile-time type safety with sealed classes
- **Both vocabularies** - all 9 iOS kinds and all 20 Android constants, named
  honestly rather than flattened into one borrowed taxonomy
- **Intents you define** - pair the two platforms yourself, with a pattern to
  fall back on
- **Capability detection** - Ask the device what it can reproduce, in one
  vocabulary shared by both platforms
- **App-wide switch** - Honour a "Haptics" setting without guarding call sites
- **AHAP files** - Read and write Apple's pattern format, so designer tools and
  pattern serialisation both work
- **Registered handles** - Hand a pattern to the platform once, replay it
  cheaply, and never faster than the actuator can separate
- **Testable** - Swap the platform for a recorder; assert on haptics like any
  other behaviour
- **Silent fail** - Gracefully handles unsupported devices without throwing errors

## Platform Support

Every device with a vibrator plays something. What plays depends on what the
hardware can do — the plugin picks the best available rendering at runtime, so
you never write a platform check.

| Platform | What plays | Survives | `fidelity` |
|----------|------------|----------|------------|
| iOS 15+ (iPhone 8 and later) | Core Haptics | intensity, sharpness, curves | `full` |
| iOS 15+ (iPhone 7) | UIKit feedback generators | tap intensity; rumbles are **dropped** | `intensity` |
| Android 16+, envelope-capable hardware | Intensity/sharpness envelopes | intensity, sharpness, curves | `full` |
| Android 11+ with composition primitives | Composition primitives | tap intensity and feel | `intensity` |
| Android 8+ with amplitude control | Amplitude waveform | intensity, rhythm | `intensity` |
| Android 8+ without amplitude control | On/off waveform | rhythm | `rhythm` |
| Android 7 (API 24–25) | Legacy waveform | rhythm | `rhythm` |
| No vibrator, or haptics unsupported | Nothing | — | `none` |

Fidelity falls off down that list: sharpness is the first thing to go, then
intensity, leaving rhythm. Design your patterns on the tier you care about most
and they will still read as *something* everywhere else. Ask the device which
tier it reached with [`FlutterHaptics.support`](#capability-detection).

Three rows deserve reading twice:

- **The Android rows below `full` are about hardware, not version.** A device
  with a rotary (ERM) motor reports no amplitude control and no composition
  primitives at any API level, so a brand new handset can land on the on/off
  row. That is why the ladder keeps its lower tiers.
- **Android 7 is always `rhythm`,** whatever motor it has. `VibrationEffect`
  arrived in API 26, so below that there is no way to ask for an amplitude
  even on hardware that could produce one. Nothing is being conservative
  here; the API simply does not exist.
- **iPhone 7 drops what it cannot do rather than approximating it.** A
  continuous event has nothing to sustain it on a feedback generator, so a
  rumble or a curve is not played at a reduced fidelity — it is not played.
  Taps come through with intensity. `supportsContinuous` is `false` there, so
  you can ask before designing around one.

### Designing for the `rhythm` tier

A rotating mass needs tens of milliseconds to spin up, so this tier cannot
render a crisp tap at all. The plugin compensates by widening every transient
to 50 ms before it reaches the actuator — blunter than intended, but felt,
which a 20 ms click on this hardware is not. Two consequences worth designing
around:

- **Rhythm is the only channel left.** Intensity is gone, sharpness is gone,
  and every tap comes out the same width. `doubleClick` and `tripleClick`
  still read, because their *spacing* survives; `lightTap` and `heavyTap` feel
  identical.
- **Below 0.15 intensity, nothing plays at all.** An on/off actuator has one
  speed, so a quiet event can only be rendered at full strength or not at all,
  and rendering a 0.1 tap at full strength would be a lie about what you
  asked for. A pattern built entirely from soft events is silent on this tier
  — another reason to carry meaning in timing.
- **System feedback is declined here**, not forwarded. Android's
  `HapticFeedbackConstants` and predefined effects are short by design, which
  is exactly what this hardware cannot do — and `performHapticFeedback`
  reports success while the user feels nothing. `impact`, `notification` and
  `selection` therefore play their fallback patterns on this tier instead.

Check for it with `support.fidelity == HapticFidelity.rhythm` and prefer
patterns whose meaning is carried by timing.

Notes for Android:

- Tap-only patterns prefer composition primitives even on envelope-capable
  hardware — primitives are tuned by the device vendor and feel crisper than
  anything synthesised. Patterns containing a rumble use envelopes.
- Overlapping events (`overlay`, `|`) have to be flattened, since Android
  exposes one vibrator channel — but **how** they flatten depends on the tier,
  and the two answers are genuinely different:
  - On the **envelope and waveform** tiers the timeline is sampled, so where
    events overlap the loudest wins and carries its sharpness. This is the
    behaviour the rest of these docs describes.
  - On the **composition** tier there is no timeline to sample: the renderer
    emits vendor primitives with a delay between them, and a delay cannot be
    negative. Two taps that overlap are played **back to back** instead,
    which stretches the pattern by the width of the first tap.

  The practical rule: overlay rumbles freely, and treat overlapping *taps* as
  a sequence, because on some devices that is exactly what they become. Where
  you need two taps at one instant, one tap with a higher intensity says the
  same thing on every tier.
- The plugin declares `android.permission.VIBRATE` itself. It is a normal
  permission: granted at install, never prompts.
- Haptics can still be suppressed by the user's system vibration settings or
  by battery saver. The plugin succeeds silently in those cases.
- `minSdk` stays at 24, so depending on the plugin will not raise your app's
  minimum SDK.

Notes for iOS:

- Core Haptics needs an iPhone 8 or later. On iPhone 7 the plugin falls back
  to UIKit feedback generators, which play taps but cannot sustain a rumble,
  so continuous events are dropped there.
- iPads have no Taptic Engine, so nothing plays. Calls still succeed.
- Low Power Mode and Settings → Sounds & Haptics → System Haptics both
  suppress playback system-wide.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_haptics: ^2.0.0
```

## Quick Start

```dart
import 'package:flutter_haptics/flutter_haptics.dart';

// Play a built-in pattern
await FlutterHaptics.play(HapticPatterns.success);

// Prepare the engine for reduced latency (optional)
await FlutterHaptics.prepare();
```

## Usage

### Built-in Patterns

```dart
// Simple taps
await FlutterHaptics.play(HapticPatterns.lightTap);
await FlutterHaptics.play(HapticPatterns.mediumTap);
await FlutterHaptics.play(HapticPatterns.heavyTap);

// Notifications
await FlutterHaptics.play(HapticPatterns.success);
await FlutterHaptics.play(HapticPatterns.warning);
await FlutterHaptics.play(HapticPatterns.error);

// Expressive
await FlutterHaptics.play(HapticPatterns.heartbeat);
await FlutterHaptics.play(HapticPatterns.doubleClick);

// Curved patterns
await FlutterHaptics.play(HapticPatterns.explosion);
await FlutterHaptics.play(HapticPatterns.engineRev);
await FlutterHaptics.play(HapticPatterns.chargeUp);
```

### Custom Patterns

```dart
// Create a pattern with individual events
final pattern = HapticPattern([
  TransientEvent(intensity: 0.8, sharpness: 0.6),
  TransientEvent(
    intensity: 1.0,
    sharpness: 0.8,
    delay: Duration(milliseconds: 100),
  ),
]);

await FlutterHaptics.play(pattern);
```

### Pattern Builder

```dart
final pattern = HapticPatternBuilder()
  .tap(intensity: 0.6)
  .waitMs(50)
  .tap(intensity: 0.8)
  .waitMs(50)
  .tap(intensity: 1.0)
  .waitMs(100)
  .rumble(
    duration: Duration(milliseconds: 200),
    intensity: 0.5,
  )
  .build();

await FlutterHaptics.play(pattern);
```

### Parameter Curves

Continuous events support intensity and sharpness curves that change over time:

```dart
// Fade out explosion
final explosion = HapticPattern([
  ContinuousEvent.curved(
    intensity: HapticParam.fadeOut,
    duration: Duration(milliseconds: 400),
  ),
]);

// Engine revving up
final engineRev = HapticPattern([
  ContinuousEvent.curved(
    intensity: HapticParam.rampUp,
    sharpness: HapticParam.linear(from: 0.3, to: 0.8),
    duration: Duration(milliseconds: 600),
  ),
]);

// Custom curve with control points
final custom = HapticPattern([
  ContinuousEvent.curved(
    intensity: HapticParam.curve([
      (0.0, 0.1),   // start soft
      (0.3, 1.0),   // spike up
      (1.0, 0.0),   // fade out
    ]),
    duration: Duration(milliseconds: 500),
  ),
]);
```

Available curve presets:
- `HapticParam.fadeIn` - 0.0 to 1.0
- `HapticParam.fadeOut` - 1.0 to 0.0
- `HapticParam.rampUp` - 0.3 to 1.0
- `HapticParam.rampDown` - 1.0 to 0.3
- `HapticParam.pulse` - 0.0 to 1.0 to 0.0
- `HapticParam.spike` - quick rise, slow decay

### Pattern Composition

```dart
// Chain patterns sequentially
final combo = HapticPatterns.success.then(HapticPatterns.buzz);

// Repeat a pattern
final repeatedHeartbeat = HapticPatterns.heartbeat.repeat(
  3,
  gap: Duration(milliseconds: 400),
);

// Scale intensity
final gentleTap = HapticPatterns.heavyTap.scaled(0.5);

// Overlay patterns (play simultaneously)
final layered = pattern1.overlay(pattern2);

// Operators
final sequential = pattern1 + pattern2;  // same as .then()
final parallel = pattern1 | pattern2;    // same as .overlay()
```

`then` and `repeat` place the next event after the previous one has finished.
A closing tap counts as `HapticEvent.transientWidth` (25 ms) wide, so chained
and repeated patterns never stack two events on the same instant — use
`overlay` when you want simultaneity.

### Repeated Haptics

`play` serialises a pattern, ships it across the channel and has the platform
build it again on every call. For anything fired repeatedly — a picker tick,
a step counter, a drag, a game loop — register it once and play the handle:

```dart
class _PickerState extends State<Picker> {
  final _tick = FlutterHaptics.register(HapticPatterns.selection);

  void _onItemChanged() => _tick.play();

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }
}
```

`register` returns synchronously, so a handle can be a field initialiser or
built in `initState`. Registration runs in the background; a `play` that
arrives before it finishes waits for it rather than racing it.

Use a plain `final`, not `late final` — a lazy field would not register until
the first play, which is exactly the round trip the handle exists to avoid.
If you need to *display* what the handle resolved to, `await handle.ready`;
nothing else has to.

**A handle will not replay faster than `minInterval`.** Taps arriving closer
together than the actuator can separate do not read as separate taps — they
smear into a buzz — and every one still crosses the platform channel. A paced
handle drops the ones that would not have been felt as distinct, reporting
`HapticRoute.none` for them.

The default comes from what the device says it can do, never from which
platform it is:

| `support.fidelity` | Default |
|---|---|
| `full` | 25 ms — one transient width |
| `intensity` | 35 ms |
| `rhythm` | 60 ms — taps are widened to 50 ms here |
| not yet known | 40 ms, conservatively, until it resolves |

Pacing reads the time through `package:clock`, which `testWidgets` advances
when a test pumps. A widget test that pumps between two plays therefore sees
the gap it asked for, not the handful of real milliseconds the pumps took.

**Handles hold patterns only.** `register` does not yet take an intent or a
system constant, so a picker driven by `IOSHaptic.selection` has to call
`perform`/`playSystem` directly and pace itself. That is the next thing on
the list.

Pass `minInterval: Duration.zero` to opt out and fire every call, or your own
duration to set the floor yourself.

Always returns a usable handle. Where the platform cannot hold a prepared
pattern it falls back to `play` and reports `isPrepared == false`, so a caller
never needs to branch.

### System Feedback

Patterns are *yours*. System haptics are the *platform's* — the constants the
OS defines and the vendor tuned, so one played here feels like the rest of the
device rather than an app imitating it.

**The two vocabularies are not translations of each other.** iOS names nine
kinds; Android names twenty, twelve of which iOS has no concept for, and
almost none of the names correspond. This package does not paper over that.

```dart
await FlutterHaptics.playSystem(AndroidHaptic.toggleOn);   // Android only
await FlutterHaptics.playSystem(IOSHaptic.impactRigid);    // iOS only
```

The argument's type carries the platform, so there is no `ios:`/`android:`
pair and no way to pass the wrong one. On another platform, on an OS older
than the constant needs, or on hardware that cannot render it, this returns
`HapticRoute.none` and plays nothing. **`playSystem` never falls back** — use
an intent when you want a pattern to cover those cases.

| | iOS | Android |
|---|---|---|
| Values | 9 | 20 |
| Oldest | iOS 10 | API 1 |
| Newest | iOS 13 | API 34 |
| Has no counterpart | `notificationWarning` | `toggleOn/Off`, `dragStart`, `segmentTick`, `gestureThreshold*`, `keyboardRelease`, … |

Android's `NO_HAPTICS` is deliberately absent: it means "play nothing on
purpose", which is already what not calling anything does.

**`system` means accepted, not felt.** `performHapticFeedback` answers for a
constant Android took, not one the user noticed, and on an actuator with
neither amplitude control nor composition primitives the two can differ —
a short tick may be accepted and never render. No API anywhere reports the
difference.

The two verbs take opposite positions on that, on purpose:

- **`playSystem` never second-guesses the device.** You asked for one exact
  constant, and these constants are implemented by the vendor for this
  hardware. It hands the request over and reports what the platform said.
- **`perform` prefers its pattern** on hardware reporting no amplitude
  control, because a pattern is something this package can render with
  confidence and a doubtful native route is not.

That judgement is made entirely from what the device reports about itself.
There is deliberately **no list of constants believed to be perceptible**:
Android documents no durations and exposes no API to ask, so any such list
could only be one tester's handset generalised into everyone's behaviour.

### Intents

An intent pairs each platform's own feedback with a pattern to fall back on.
**This package ships none** — you name the meanings your app has, in your
words, and say how each platform serves them:

```dart
class AppHaptics {
  static const saved = HapticIntent(
    ios: HapticArm.native(IOSHaptic.notificationSuccess),
    android: HapticArm.native(AndroidHaptic.confirm),  // needs API 30
    pattern: HapticPatterns.success,                   // recovery below that
  );

  static const caution = HapticIntent(
    ios: HapticArm.native(IOSHaptic.notificationWarning),
    android: HapticArm.pattern(),      // Android names no warning
    pattern: HapticPatterns.warning,
  );

  static const toggledOn = HapticIntent(
    ios: HapticArm.silent(),           // iOS has no toggle feedback
    android: HapticArm.native(AndroidHaptic.toggleOn),  // needs API 34
    pattern: HapticPatterns.mediumTap,
  );
}

await FlutterHaptics.perform(AppHaptics.saved);
```

One file knows about platforms; every call site stays blind.

Each arm is one of three things, and each is a statement rather than an
absence:

| Arm | What `perform` does | Route |
|---|---|---|
| `HapticArm.native(…)` | asks the platform; recovers with `pattern` if it cannot | `system`, else `pattern` |
| `HapticArm.pattern()` | plays `pattern`, without asking | `pattern` |
| `HapticArm.silent()` | plays nothing, and does not consult `pattern` | `none` |

Both arms are required. An intent that does not say what iOS does is an
intent nobody can read, and writing `HapticArm.silent()` costs one line and
answers the question for good.

The arms are typed, so `ios:` takes only an `IOSHaptic` and `android:` only
an `AndroidHaptic`:

```dart
ios: HapticArm.native(AndroidHaptic.confirm)   // does not compile
```

**The pattern is a recovery, not a substitute.** After a `native` arm it
covers a route you *asked for* and did not get — the OS is too old for the
constant, the actuator cannot render it, or the call was declined. It never
fills in for a route you never asked for: `silent()` means this platform
plays nothing, on purpose, and the pattern is not consulted.

A chosen pattern and a recovered one both report `HapticRoute.pattern`.
Which it was is written in the intent, where it belongs — not discovered
at runtime.

### Knowing What Happened

Every verb returns a `HapticRoute`, free to ignore:

```dart
final route = await FlutterHaptics.perform(AppHaptics.saved);
// HapticRoute.system  — the OS played its own feedback
// HapticRoute.pattern — the recovery played
// HapticRoute.none    — nothing played
```

And when a haptic was asked for and could not be delivered, `onFailure`
decides what happens. It defaults to logging in debug and silence in release,
so a haptic that quietly does nothing shows up while you are building it:

```dart
FlutterHaptics.onFailure = HapticFailureMode.throwIt;   // or .log, .silent
```

```
flutter_haptics: playSystem(toggleOn) played nothing
  — toggleOn requires API 34, this device is 31
```

**Each distinct message is reported once.** A haptic firing on every frame of
a drag would otherwise bury the console in one repeated line, and the repeat
says nothing new — a device that cannot play something does not start being
able to halfway through a session. The same call failing for a *new* reason
is news, and is reported again. `throwIt` is the exception and always throws.

To send failures somewhere of your own, set `onFailureReport`. It replaces
the mode entirely — nothing is printed and nothing is thrown — so a release
build can record what is not being felt in the field:

```dart
FlutterHaptics.onFailureReport = (failure) {
  FirebaseCrashlytics.instance.log('$failure');
};
```

A `HapticFailure` carries the thing that failed as well as the sentence:
`failure.haptic` for a system constant, `failure.pattern` for a pattern.
Patterns have no names, so two different ones can describe themselves
identically — reach for `pattern` rather than parsing `request`.

Switching haptics off through `enabled`, and performing an intent whose arm
for this platform is `HapticArm.silent()`, are never reported: both are the
app getting exactly what it asked for.

### Capability Detection

Both platforms report into the same vocabulary, so you never branch on
`Platform.isAndroid` — you branch on what the hardware can actually do:

```dart
final support = await FlutterHaptics.support;

// Hide your app's haptics setting where nothing can play.
if (!support.isSupported) hideHapticsToggle();

// Pick a pattern the device can render.
await FlutterHaptics.play(
  support.supportsSharpness
      ? HapticPatterns.chargeUp   // curves survive
      : HapticPatterns.success,   // reads well as taps alone
);

// A rumble is dropped on iPhone 7 and on iPads.
if (support.supportsContinuous) {
  await FlutterHaptics.play(HapticPatterns.explosion);
}
```

| Member | Meaning |
|--------|---------|
| `fidelity` | `full`, `intensity`, `rhythm` or `none` — see the table above |
| `supportsContinuous` | Whether a `ContinuousEvent` can sustain here |
| `isSupported` | Whether anything at all will play |
| `supportsIntensity` | Whether per-event intensity reaches the actuator |
| `supportsSharpness` | Whether the dull-to-crisp axis reaches the actuator |

The result is queried once and cached — haptic hardware does not change while
the app runs. On platforms with no implementation (web, desktop) it reports
`HapticSupport.unsupported` rather than throwing.

### Turning Haptics Off

`FlutterHaptics.enabled` is an app-wide switch, so a "Haptics" setting in
your preferences does not need a guard at every call site:

```dart
// On startup, from your own persisted setting.
FlutterHaptics.enabled = prefs.getBool('haptics') ?? true;

await FlutterHaptics.play(HapticPatterns.success); // no-op while false
```

`stop()` keeps working while disabled, so switching haptics off mid-pattern
silences it. The value is not persisted — that is your app's job.

### Platform-Specific Patterns

Most patterns feel right on both platforms as-is. When one needs different
tuning on Android hardware, resolve it per platform at creation time:

```dart
final explosion = HapticPattern.forPlatform(
  ios: HapticPatterns.explosion,
  android: HapticPatternBuilder()
      .rumbleCurved(
        intensity: HapticParam.spike,
        duration: Duration(milliseconds: 400),
      )
      .build(),
);

await FlutterHaptics.play(explosion); // play() stays platform-agnostic
```

If `android` is omitted, the `ios` pattern is used everywhere.

## API Reference

### FlutterHaptics

| Member | Description |
|--------|-------------|
| `play(HapticPattern)` | Play a haptic pattern |
| `prepare()` | Warm up the haptic engine for reduced latency (no-op on Android) |
| `stop()` | Stop any currently playing pattern |
| `playSystem(SystemHaptic)` | Play one platform's own constant; never falls back |
| `perform(HapticIntent)` | Do what this platform's `HapticArm` says |
| `onFailure` | What happens when a haptic could not be delivered |
| `onFailureReport` | Send those failures to your own logger instead |
| `register(HapticPattern, {minInterval})` | A `HapticHandle` for cheap, paced replay — returns synchronously |

### HapticHandle

| Member | Description |
|--------|-------------|
| `play()` | Replay it, unless it falls inside `minInterval` |
| `minInterval` | The pacing floor in force; settles once the device answers |
| `ready` | Completes when the registration and `minInterval` have settled |
| `isPrepared` | Whether the platform is holding a prepared copy right now |
| `dispose()` | Release it. `play()` does nothing afterwards |
| `support` | `Future<HapticSupport>` — what this device can reproduce (cached) |
| `isSupported` | `Future<bool>` — whether anything at all will play |
| `enabled` | App-wide on/off switch for `play()`; defaults to `true` |

### Testing

| Member | Description |
|--------|-------------|
| `FlutterHapticsPlatform.instance` | The seam every call goes through; assign a substitute |
| `FlutterHapticsPlatform.reset()` | Restore the real implementation |
| `FakeHapticsPlatform` | Recorder, from `package:flutter_haptics/testing.dart` |

### HapticEvent Types

| Type | Description |
|------|-------------|
| `TransientEvent` | Sharp, instantaneous tap (intensity, sharpness, delay) |
| `ContinuousEvent` | Sustained rumble with constant values |
| `ContinuousEvent.curved` | Sustained rumble with parameter curves |

### HapticArm

| Value | Meaning |
|-------|---------|
| `HapticArm.native(haptic)` | Play this platform's constant; recover with the pattern |
| `HapticArm.pattern()` | Use the intent's pattern here, by choice |
| `HapticArm.silent()` | Play nothing here, by choice |

### HapticPatterns Library

**Simple taps:** `lightTap`, `mediumTap`, `heavyTap`, `soft`, `rigid`

**UI feedback:** `selection`, `doubleClick`, `tripleClick`

**Notifications:** `success`, `warning`, `error`

**Expressive:** `heartbeat`, `buzz`, `longBuzz`

**Curved:** `explosion`, `engineRev`, `pulseWave`, `impactDecay`, `chargeUp`

## Testing Your App

Haptics are invisible to a widget test, which usually means they go untested.
Swap the platform for a recorder and they become ordinary assertions — no
method channel, no mocks to write:

```dart
import 'package:flutter_haptics/flutter_haptics.dart';
import 'package:flutter_haptics/testing.dart';

late FakeHapticsPlatform haptics;

setUp(() {
  haptics = FakeHapticsPlatform();
  FlutterHapticsPlatform.instance = haptics;
});
tearDown(FlutterHapticsPlatform.reset);

testWidgets('submitting confirms', (tester) async {
  await tester.tap(find.byType(SubmitButton));
  await tester.pump();

  expect(haptics.systemHaptics, [AndroidHaptic.confirm]);
  expect(haptics.played, isEmpty);   // routed to the OS, not synthesised
});
```

`FakeHapticsPlatform` records `played`, `systemHaptics`, `intents`,
`registrations`, `replays`, `releases`, `prepareCount` and `stopCount`, and
`clear()` resets them.

`intents` is recorded before the arm is resolved — and before
`FlutterHaptics.enabled` is consulted, since it is what your app asked for
rather than what the device was asked to do:

```dart
expect(haptics.intents, [AppHaptics.saved]);          // it asked to confirm
expect(haptics.lastPlayed, AppHaptics.saved.pattern); // and had to recover
```

`clear()` empties the records without releasing anything, so a handle
arranged before the call still replays after it. To simulate the platform
losing its registrations — which Android does when the plugin detaches from
its engine — call `debugLoseRegistrations()`.

**Pacing and `pump()`.** A handle measures its interval with
`package:clock`, which `testWidgets` advances. A bare `await tester.pump()`
advances it by *zero*, so this drops the second haptic every time:

```dart
await tester.tap(nextItem);
await tester.pump();          // 0ms later
await tester.tap(nextItem);
await tester.pump();          // still 0ms later — paced out
```

Pump a realistic gap — `tester.pump(const Duration(milliseconds: 100))` —
or register with `minInterval: Duration.zero` in tests that only care that
each tap asked for a haptic. `pumpAndSettle` advances 100 ms per frame and
is fine as it is.

Its constructor stands in for a device less capable than the one running the
test, which is the case hardest to reach otherwise:

```dart
// A device that cannot play the constant — the intent must recover.
FlutterHapticsPlatform.instance =
    FakeHapticsPlatform(playsSystemHaptics: false);
await FlutterHaptics.perform(AppHaptics.saved);
expect(haptics.lastPlayed, AppHaptics.saved.pattern);

// A device that cannot prepare patterns — handles must still play.
FlutterHapticsPlatform.instance = FakeHapticsPlatform(canRegister: false);

// A single-speed actuator, so your UI can pick a simpler pattern.
FlutterHapticsPlatform.instance = FakeHapticsPlatform(
  support: HapticSupport(
    fidelity: HapticFidelity.rhythm,
    supportsContinuous: true,
  ),
);

// A device with no vibrator at all — every play fails.
FlutterHapticsPlatform.instance =
    FakeHapticsPlatform(support: HapticSupport.unsupported);
```

The fake applies that `support` the way the real platforms do, to patterns
as well as constants:

- A `rhythm` actuator declines a constant asked for through `perform` —
  which carries a pattern to recover with — while `playSystem`, which does
  not second-guess the device, still plays it.
- A device reporting `HapticFidelity.none` plays nothing at all.
- A device that cannot sustain a rumble refuses a pattern made only of
  continuous events, exactly as iPhone 7 does.

So a failing haptic is testable without pretending the whole platform is
broken — and `played` still records what was asked for either way.

`FlutterHaptics` is a thin facade over `FlutterHapticsPlatform.instance`: the
facade holds the policy (the app-wide switch, empty patterns, semantic
fallbacks) and the platform does the talking. This is deliberately *not* a
federated `plugin_platform_interface` — two platforms and one implementation
of each would make a package split a lockstep release for no gain the seam
does not already give.

## Requirements

- iOS 15.0 or later — the floor Flutter itself migrates projects to.
  Core Haptics needs an iPhone 8 or later; the UIKit fallback covers the
  iPhone 7 and 6s, both of which run iOS 15.
- Android 7.0 (API 24) or later — the same floor Flutter itself defaults to,
  so depending on this plugin never raises your app's `minSdk`
- Flutter 3.35.0 / Dart 3.9.2 or later

## Roadmap

- Audio-haptic synchronisation
- More built-in patterns

## License

MIT License - see [LICENSE](LICENSE) for details.
