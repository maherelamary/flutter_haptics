## 2.0.1

Curves behaved differently from everything else, on iOS and in exported
files alike. Found by building a pattern editor on 2.0.0.

### Fixed

- **On iOS, a rumble's curve no longer reaches the rest of the pattern.** A
  parameter curve is not tied to the event it was written for:
  `CHHapticParameter.h` says dynamic parameters "modify all haptic or audio
  events within a pattern" and are "not tied to specific events". Intensity
  control is a multiplier, so building one `CHHapticPattern` holding every
  event and every curve meant a tap during a fade played at a fraction of
  its strength, a tap after a fade-to-zero played not at all, two curved
  rumbles fought over one control, and a flat rumble after a sharpness curve
  inherited the leftover offset. Each curved rumble now gets a player of its
  own holding only its own curves, with everything uncurved sharing one and
  every player starting from the same instant; parameter state belongs to
  the player, so a curve can no longer reach past it. Registered handles
  keep the split patterns and behave the same. Taps overlapping a curved
  rumble now play at full strength on iOS, as they always did on Android.
  A play that can only start some of its players is taken back rather than
  left half-rendered, and reports the failure.
- **AHAP control-point times were written and read backwards.** The format
  measures a control point from its curve's own `Time`, the same as the
  `CHHapticParameterCurve` API — Apple's own authored files show it plainly,
  carrying points that start at `0.0` under a curve at `"Time": 1.207`. This
  package treated them as absolute from the start of the pattern, so any
  curve at a non-zero time was written double-offset and read collapsed. A
  curve starting at zero is identical under either reading, which is how the
  mistake survived; and because encoding and decoding shared it, round trips
  agreed with each other while both disagreed with Core Haptics. A curve
  with no `Time` now defaults to zero rather than to its first point, which
  was the absolute reading of it.
- **Encoded files no longer leak a rumble's curve onto later events.** A
  dynamic parameter is not tied to the event it was written for: it
  modulates everything in the pattern from the moment it arrives, so a curve
  fading to zero silenced whatever followed and a tap overlapping a rumble
  played at the curve's current value. Each curved rumble is now followed by
  a reset putting intensity back to 1.0 and sharpness to 0.0, skipped where
  another curve for that parameter is still running or starts at that
  instant. Decoding
  ignores all-neutral curves, so a reset written this way by another tool is
  not mistaken for an event's own shape.
- `playRegistered` reported success whenever the platform recognised the id,
  even when nothing played. It now reports the failure, and says whether the
  registration is *gone* or merely would not play: `NativeResult` gained
  `registrationLost` for that. A handle forgets its registration only on the
  first, so one bad moment from the engine no longer costs it the
  registration for the rest of the session. **If you implement
  `FlutterHapticsPlatform` yourself**, set `registrationLost: true` for ids
  you no longer hold: it defaults to `false`, so without it a handle never
  learns its registration is dead and pays a wasted round trip on every
  play.

### Added

- `FakeHapticsPlatform.refuseReplays` fails replays while keeping the
  registrations, standing in for an engine that will not play right now.
  Together with `debugLoseRegistrations()` it covers both halves of the
  distinction above: a handle should ride out the first and forget on the
  second.

### Known limits

- **AHAP cannot express a curve that belongs to one event**, because the
  format has only pattern-wide parameters. Encoding a tap that overlaps a
  curved rumble therefore writes a file where that tap is modulated by the
  rumble's curve; the resets above contain the leak after the rumble ends,
  not during it. `encode` does not refuse such a pattern — no encoder could
  do better, and refusing would make a legitimate pattern unencodable.
- **The same loss runs the other way.** Apple-authored files often use one
  curve to shape a run of taps, and this package can only attach a curve to
  a continuous event, so those taps decode at a flat strength.

### Docs

- A README section for AHAP files, carrying both limits above, and one for
  the showcase app.
- `pubspec.yaml` lists screenshots for pub.dev.

## 2.0.0

Four breaking changes, two in the API an app calls and two in the platform
interface. Most of them come from building an app on 1.0.0 and finding the
API answered a question with silence.

### `HapticIntent` arms are now `HapticArm`

In 1.0.0 an arm was a nullable constant, which made `null` carry two
unrelated meanings: *this platform has nothing for this* and *I have not
decided yet*. An arm is now one of three things, each a statement:

```dart
static const saved = HapticIntent(
  ios: HapticArm.native(IOSHaptic.notificationSuccess),
  android: HapticArm.native(AndroidHaptic.confirm),
  pattern: HapticPatterns.success,
);

static const caution = HapticIntent(
  ios: HapticArm.native(IOSHaptic.notificationWarning),
  android: HapticArm.pattern(),   // Android names no warning — chosen, not fallen back to
  pattern: HapticPatterns.warning,
);

static const toggledOn = HapticIntent(
  ios: HapticArm.silent(),        // iOS has no toggle feedback
  android: HapticArm.native(AndroidHaptic.toggleOn),
  pattern: HapticPatterns.mediumTap,
);
```

**Migrating:** wrap each constant in `HapticArm.native(…)`, replace `null`
with `HapticArm.silent()`, and supply both arms — they are required now, so
an intent that does not say what iOS does no longer compiles.

The arms stay typed, so `ios:` still takes only an `IOSHaptic` and
`android:` only an `AndroidHaptic`.

`HapticArm.pattern()` is new, and is the point of the change: a pattern
*chosen* because the platform names nothing for this meaning is a different
statement from a pattern *recovered* after a native route could not be
delivered. Both still play the same pattern and report `HapticRoute.pattern`;
the difference now lives in the intent, where it is readable.

`HapticIntent.routeFor(platform)` is replaced by `armFor(platform)`, which
returns the arm rather than the constant.

### `register` returns a handle synchronously, and paces it

```dart
final _tick = FlutterHaptics.register(HapticPatterns.selection);
```

`register` no longer returns a `Future`, so a handle can be a field
initialiser or built in `initState` without an `await` or a nullable field.
Registration still happens natively; it now runs in the background, and a
`play` that arrives before it finishes waits for it.

**Migrating:** drop the `await`. A `Future<HapticHandle>` field becomes a
plain `HapticHandle`.

A handle also will not replay faster than `minInterval`, which defaults to
the device's reported fidelity — 25 ms at `full`, 35 at `intensity`, 60 at
`rhythm`, 40 until the query resolves — never to which platform it is. Taps
closer together than the actuator can separate smear into a buzz rather than
reading as separate taps, and every one still crosses the channel. Paced-out
calls return `HapticRoute.none`. Pass `minInterval: Duration.zero` for the
1.0.0 behaviour.

Pacing reads the time through `package:clock`, which is a new dependency and
the one `testWidgets` advances when a test pumps. Measuring with
`DateTime.now()` would have paced out the second haptic in any widget test
that pumps between two plays, flakily, depending on the machine.

One consequence to know about: a bare `await tester.pump()` advances that
clock by *zero*, so two taps a bare pump apart are one tap as far as a
handle is concerned. Pump a realistic gap, or register with
`minInterval: Duration.zero` in tests that only care that a haptic was
asked for.

`HapticHandle.ready` completes once the platform has answered and
`minInterval` has settled. Nothing has to await it — `play` works from the
first frame — but a UI that *displays* what the handle resolved to needs it.

Declare a handle with a plain `final`, not `late final`: a lazy field does
not register until the first play, which is the round trip the handle exists
to avoid.

### Breaking for anything implementing `FlutterHapticsPlatform`

Both matter only if you wrap or substitute the seam — a tracer, a decorator,
a custom implementation. An app that only calls `FlutterHaptics` is
unaffected.

- `playRegistered` returns `Future<NativeResult>` instead of `Future<void>`.
  It has to report an id it no longer holds, or a handle whose registration
  was lost can never fall back.
- `noteIntent(HapticIntent)` is new, with a no-op default so existing
  implementations still compile. **A wrapper must forward it**, or
  `perform` stops being observable through that wrapper and nothing says so.

### Added

- `FlutterHaptics.onFailureReport` sends failures to a logger or crash
  reporter of your own. It replaces `onFailure` entirely while set, so a
  release build can record what is not being felt in the field.
- Failures are now reported **once per distinct `(request, reason)`**. A
  haptic firing on every frame of a drag used to bury the console in one
  repeated line that said nothing new. `HapticFailureMode.throwIt` is
  exempt and always throws.
- `FakeHapticsPlatform.intents` records every intent `perform` was given,
  before the arm is resolved, so a test can assert on the meaning an app
  asked for and not only on what the device made of it.
- `FakeHapticsPlatform` now applies its configured `support` the way the real
  platforms do, to patterns as well as constants: a `rhythm`-tier actuator
  declines a constant asked for through `perform`, which has a pattern to
  recover with, while `playSystem` still plays it; a device reporting
  `HapticFidelity.none` plays nothing at all; and one that cannot sustain a
  rumble refuses a pattern made only of continuous events, as iPhone 7 does.
  Until now `play` always succeeded, so a failing pattern was not testable
  at all.
- `FakeHapticsPlatform.debugLoseRegistrations()` drops every live
  registration without telling the handles holding them, which is what
  Android does when the plugin detaches from its engine.
- `HapticFailure` carries the thing that failed — `pattern` or `haptic` —
  as well as the sentence describing it. Patterns have no names, so two
  different ones can describe themselves identically; a crash reporter that
  needs to tell them apart no longer has to parse `request`.

### Fixed

- A handle whose native registration had been lost — Android clears them when
  the plugin detaches from its engine — fell silent instead of falling back to
  `play`. Both platforms returned success for an unknown id, which made the
  fallback unreachable; they now report it, and the handle forgets the dead id
  rather than paying a round trip to rediscover it on every later play.
- `HapticHandle.play` could outlive `dispose`: a play waiting on registration
  carried on afterwards and played the pattern. It returns
  `HapticRoute.none` now.
- `FakeHapticsPlatform.clear()` made every live handle look lost, because the
  `registrations` record also decided whether a replay succeeded, and
  `unregister` did not invalidate an id at all. Liveness is tracked
  separately now, so clearing the record leaves handles alone and releasing
  one stops it replaying.
- Failures were deduplicated by a request name that identified a pattern only
  by its event count, so `success` and `error` failing the same way reported
  once between them. Patterns are keyed by value now, and the message carries
  the duration as well.
- `HapticArm` equality was not symmetric: `a == b` and `b == a` could differ
  when one side's type argument was more general, and `hashCode` then
  disagreed with `==`.
- `Ahap.decode` threw `UnsupportedError` — again invisible to a caller
  catching `FormatException` — on a non-finite number. `"NaN"`, `"Infinity"`
  and the perfectly legal JSON literal `1e400` all parse to one, and a
  non-finite number of seconds throws out of the rounding that builds a
  `Duration`. Such a value is now read as absent, and the field's own default
  applies.
- `Ahap.decode` threw a `TypeError` on a file whose `"Time"` is written as a
  string, which callers catching `FormatException` never saw. Numbers written
  as strings are now parsed wherever the decoder reads one — event `Time` and
  `EventDuration`, `ParameterValue`, curve `Time` and control points — rather
  than being skipped. A curve whose `Time` cannot be read at all starts where
  its first control point does.
- `HapticPatterns.buzz` and `longBuzz` are `const`, like the other seventeen.

### Not in this release

- **Handles hold patterns only.** `register` does not take a `HapticIntent`
  or a system constant yet, so pacing covers `play` and not `perform` or
  `playSystem`. An app pacing those still needs its own throttle. Next.
- A `HapticRoute.pattern` still does not say on its own whether the pattern
  was chosen or recovered. The intent says, which covers reading the source;
  an observer hook that reports it at runtime is not here yet.

### Docs

- The tier table was wrong in three places: Android 7 is always `rhythm`
  whatever motor it has, since `VibrationEffect` only arrived in API 26;
  iPhone 7 *drops* rumbles and curves rather than approximating them; and
  below 0.15 intensity an on/off actuator plays nothing at all.
- Overlapping events flatten two different ways on Android, and the README
  only described one. On the envelope and waveform tiers the loudest wins; on
  the composition tier there is no timeline to sample, so overlapping taps
  are played back to back instead. Overlay rumbles freely; treat overlapping
  taps as a sequence.
- `HapticPatterns` holds nineteen patterns, not "20+".

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
  nineteen ready-made ones.
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
