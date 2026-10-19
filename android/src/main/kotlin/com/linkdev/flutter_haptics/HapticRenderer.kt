package com.linkdev.flutter_haptics

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.RequiresApi

/**
 * What a renderer produces: a single thing to hand the vibrator.
 *
 * One plan per `play()` call is deliberate. Android has one vibrator channel
 * and every `vibrate()` call cancels the one before it, so a pattern split
 * across several calls would clip itself.
 */
internal sealed interface VibrationPlan {
    /** A modern effect. Requires API 26. */
    data class Effect(val effect: VibrationEffect) : VibrationPlan

    /** Alternating off/on durations for the pre-API-26 vibrate(long[], int). */
    data class Legacy(val timings: LongArray) : VibrationPlan {
        override fun equals(other: Any?) =
            this === other || (other is Legacy && timings.contentEquals(other.timings))

        override fun hashCode() = timings.contentHashCode()
    }
}

/**
 * Turns a parsed pattern into something a particular class of hardware can
 * play. Returns null when this renderer cannot represent the pattern, which
 * is the signal to try the next tier down.
 */
internal interface HapticRenderer {
    fun render(vibrator: Vibrator, spec: HapticSpec): VibrationPlan?
}

/**
 * Picks the best rendering of [spec] the device can actually play, walking
 * down the capability ladder Android documents:
 *
 * 1. Envelopes (API 36 + hardware support) — real intensity/sharpness curves.
 * 2. Composition primitives (API 30) — crisp, tuned taps, but no sustain.
 * 3. Amplitude waveform (API 26 + amplitude control) — sampled approximation.
 * 4. On/off waveform (API 26) — rhythm only.
 * 5. Legacy waveform (API 24) — rhythm only, deprecated call.
 *
 * Tiers 1 and 2 swap places for tap-only patterns: primitives are tuned by
 * the vendor and feel better than anything synthesised, but they cannot
 * express a sustained rumble, so a pattern containing one skips them.
 */
internal fun selectPlan(vibrator: Vibrator, spec: HapticSpec): VibrationPlan? {
    if (spec.isEmpty) return null

    val ladder = buildList {
        if (spec.hasContinuous) {
            add(EnvelopeRenderer)
            add(CompositionRenderer)
        } else {
            add(CompositionRenderer)
            add(EnvelopeRenderer)
        }
        add(AmplitudeWaveformRenderer)
        add(OnOffWaveformRenderer)
        add(LegacyWaveformRenderer)
    }

    return ladder.firstNotNullOfOrNull { renderer ->
        runCatching { renderer.render(vibrator, spec) }.getOrNull()
    }
}

/**
 * Describes what this device can reproduce, in the vocabulary the Dart side
 * shares with iOS.
 *
 * This mirrors the ladder in [selectPlan] and has to stay in step with it:
 * the tiers that keep sharpness report `full`, the ones that keep only an
 * amplitude report `intensity`, and the on/off tiers report `rhythm`.
 *
 * Note that `rhythm` is not an old-Android outcome. A device with a rotary
 * (ERM) motor reports no amplitude control and no primitives at any API
 * level, so a brand new handset can land here.
 */
internal fun describeSupport(vibrator: Vibrator?): Map<String, Any> {
    if (vibrator == null) return UNSUPPORTED

    val fidelity = when {
        Build.VERSION.SDK_INT >= API_ENVELOPES && supportsEnvelopes(vibrator) -> "full"
        rendersShortEffects(vibrator) -> "intensity"
        else -> "rhythm"
    }

    // Any vibrator can hold a sustained buzz, even one that only knows on and
    // off, so a continuous event always plays as something here.
    return mapOf("fidelity" to fidelity, "continuous" to true)
}

/**
 * Whether this device can render a short, crisp effect at all.
 *
 * Both of the things that make one possible — amplitude control and composition
 * primitives — are absent on a plain rotating-mass actuator, which needs tens
 * of milliseconds to spin up. On such a device the system's own
 * `HapticFeedbackConstants` and predefined effects are all below the
 * perception threshold: they are short by design, and short is exactly what
 * the hardware cannot do.
 *
 * This is the same condition as reporting `rhythm` fidelity, and the reason
 * [performSystemFeedback] declines there — a synthesised pattern with a wide
 * enough stroke is the only thing that gets felt.
 */
internal fun rendersShortEffects(vibrator: Vibrator): Boolean = when {
    Build.VERSION.SDK_INT >= API_EFFECTS && vibrator.hasAmplitudeControl() -> true
    Build.VERSION.SDK_INT >= API_PRIMITIVES && supportsAnyPrimitive(vibrator) -> true
    else -> false
}

/** Reported when there is no vibrator, or when the query itself fails. */
internal val UNSUPPORTED: Map<String, Any> = mapOf("fidelity" to "none", "continuous" to false)

@RequiresApi(API_ENVELOPES)
private fun supportsEnvelopes(vibrator: Vibrator): Boolean =
    vibrator.areEnvelopeEffectsSupported()

@RequiresApi(API_PRIMITIVES)
private fun supportsAnyPrimitive(vibrator: Vibrator): Boolean =
    vibrator
        .arePrimitivesSupported(
            VibrationEffect.Composition.PRIMITIVE_CLICK,
            VibrationEffect.Composition.PRIMITIVE_TICK,
        )
        .any { it }

/** Lowest API level that can play a [VibrationEffect] at all. */
internal const val API_EFFECTS = Build.VERSION_CODES.O

/** Composition primitives. `LOW_TICK`, `THUD` and `SPIN` need API 31. */
internal const val API_PRIMITIVES = Build.VERSION_CODES.R

/** `BasicEnvelopeBuilder` and `areEnvelopeEffectsSupported()`. */
internal const val API_ENVELOPES = Build.VERSION_CODES.BAKLAVA
