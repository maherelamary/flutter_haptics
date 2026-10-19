# flutter_haptics example

A working demonstration of every part of the package, built so the behaviour
is visible as well as felt: each control reports the `HapticRoute` it took,
which is the only way to tell the platform's own feedback from this package's
synthesiser.

**Run it on a physical device.** Simulators and emulators have no vibration
hardware — everything succeeds and you feel nothing, and the Device tab will
correctly report `fidelity: none`.

```bash
flutter run
```

## The tabs

| Tab | What it shows |
|-----|---------------|
| **Device** | What this handset reports it can do, the app-wide haptics switch, engine warm-up and stop |
| **Android** | All 20 `HapticFeedbackConstants`, grouped by the API level each needs. Silent on iOS by design |
| **iOS** | All 9 UIKit feedback kinds. Silent on Android by design |
| **Intents** | Cross-platform meanings, defined by this app in `lib/app_haptics.dart` — the file to copy |
| **Patterns** | The built-in library, parameter curves, composition and the fluent builder |
| **Advanced** | A registered handle driving a slider, and loading an `.ahap` file |

## Worth trying on a budget Android

On a device with no amplitude control the Android tab reports `system` for
most constants while you feel almost none of them: the platform accepts a
constant it cannot render, and no API reports the difference. The Intents tab
then shows the same meanings recovering with patterns. That contrast is the
clearest demonstration of why the package has both verbs.
