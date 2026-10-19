package com.linkdev.flutter_haptics

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.RequiresApi
import kotlin.math.ceil
import kotlin.math.roundToInt

/** One stretch of constant amplitude in a sampled pattern. */
internal data class Run(val durationMs: Long, val amplitude: Int)

/** A transient has no width, so give it a brief blip when sampling. */
private const val TRANSIENT_WIDTH_MS = 25L

/**
 * How wide a transient has to be before an on/off actuator can render it.
 *
 * A device with no amplitude control is driving a rotating mass, and a
 * rotating mass takes tens of milliseconds to spin up — datasheets put the
 * rated-voltage rise time around 40 ms. Asked for the 25 ms blip above, it
 * barely starts moving before being told to stop, and the user feels nothing.
 *
 * This was not theoretical: on a Galaxy A11, which reports no amplitude
 * control and no primitives, every tap pattern came out as a single 20 ms
 * pulse and none of them could be felt.
 *
 * Widening costs fidelity — a tap on this tier reads as a short buzz rather
 * than a click — but this tier never had the crispness to lose, and a blunt
 * pulse that is felt beats a crisp one that is not.
 */
private const val ON_OFF_TRANSIENT_WIDTH_MS = 50L

/** Finest sampling step. Below roughly this, the actuator cannot keep up anyway. */
private const val MIN_STEP_MS = 10L

/** Sampling resolution ceiling, to keep the arrays a sane size. */
private const val TARGET_STEPS = 200

/** Patterns longer than this are truncated rather than buzzing indefinitely. */
private const val MAX_TOTAL_MS = 10_000L

/** Below this intensity an on/off actuator is better off staying silent. */
private const val ON_OFF_THRESHOLD = 0.15f

/**
 * Samples [spec] into runs of constant amplitude.
 *
 * This is the lossy path: a single amplitude channel cannot express sharpness,
 * so only the intensity envelope survives. Rhythm and dynamics come through,
 * the texture does not.
 */
internal fun sampleRuns(spec: HapticSpec, binarize: Boolean): List<Run> {
    // An on/off actuator needs a wider stroke than one with amplitude control.
    val transientWidth =
        if (binarize) ON_OFF_TRANSIENT_WIDTH_MS else TRANSIENT_WIDTH_MS

    val transientTail = spec.transients.maxOfOrNull { it.startMs + transientWidth } ?: 0L
    val total = maxOf(spec.durationMs, transientTail).coerceAtMost(MAX_TOTAL_MS)
    if (total <= 0) return emptyList()

    val step = maxOf(MIN_STEP_MS, ceil(total.toDouble() / TARGET_STEPS).toLong())
    val steps = ceil(total.toDouble() / step).toInt()

    val runs = mutableListOf<Run>()
    for (index in 0 until steps) {
        // Sample the middle of the bucket rather than its leading edge, so a
        // short spike lands on the bucket it actually overlaps.
        val at = index * step + step / 2
        val intensity = spec.sampleAt(at, transientWidth).first
        val amplitude = if (binarize) {
            if (intensity >= ON_OFF_THRESHOLD) 255 else 0
        } else {
            // Amplitude 0 means "off", so anything audible has to reach 1.
            val scaled = (intensity * 255f).roundToInt().coerceIn(0, 255)
            if (scaled == 0 && intensity > 0f) 1 else scaled
        }

        val last = runs.lastOrNull()
        if (last != null && last.amplitude == amplitude) {
            runs[runs.lastIndex] = last.copy(durationMs = last.durationMs + step)
        } else {
            runs.add(Run(step, amplitude))
        }
    }

    // Trailing silence just delays the next vibration; drop it.
    while (runs.isNotEmpty() && runs.last().amplitude == 0) runs.removeAt(runs.lastIndex)
    return runs
}

/**
 * Tier 3 — amplitude waveform (Android 8+ with amplitude control).
 *
 * Intensity curves survive as a stepped approximation; sharpness is lost.
 */
internal object AmplitudeWaveformRenderer : HapticRenderer {
    override fun render(vibrator: Vibrator, spec: HapticSpec): VibrationPlan? {
        if (Build.VERSION.SDK_INT < API_EFFECTS) return null
        if (!vibrator.hasAmplitudeControl()) return null

        val runs = sampleRuns(spec, binarize = false)
        if (runs.isEmpty()) return null

        return VibrationPlan.Effect(
            createWaveform(
                runs.map { it.durationMs }.toLongArray(),
                runs.map { it.amplitude }.toIntArray(),
            ),
        )
    }

    @RequiresApi(API_EFFECTS)
    private fun createWaveform(timings: LongArray, amplitudes: IntArray): VibrationEffect =
        VibrationEffect.createWaveform(timings, amplitudes, -1)
}

/**
 * Tier 4 — on/off waveform (Android 8+).
 *
 * The actuator has one speed, so only the rhythm of the pattern comes through.
 */
internal object OnOffWaveformRenderer : HapticRenderer {
    override fun render(vibrator: Vibrator, spec: HapticSpec): VibrationPlan? {
        if (Build.VERSION.SDK_INT < API_EFFECTS) return null
        val timings = onOffTimings(spec) ?: return null
        return VibrationPlan.Effect(createWaveform(timings))
    }

    @RequiresApi(API_EFFECTS)
    private fun createWaveform(timings: LongArray): VibrationEffect =
        VibrationEffect.createWaveform(timings, -1)
}

/**
 * Tier 5 — the pre-Android-8 call. Same rhythm-only result as tier 4, but
 * expressed as the deprecated `vibrate(long[], int)` the old API understands.
 */
internal object LegacyWaveformRenderer : HapticRenderer {
    override fun render(vibrator: Vibrator, spec: HapticSpec): VibrationPlan? =
        onOffTimings(spec)?.let(VibrationPlan::Legacy)
}

/**
 * Builds the alternating off/on duration array both on/off tiers use.
 * Android reads index 0 as an "off" duration, so a pattern that starts
 * vibrating needs a zero-length silence in front of it.
 */
internal fun onOffTimings(spec: HapticSpec): LongArray? {
    val runs = sampleRuns(spec, binarize = true)
    if (runs.isEmpty()) return null

    val timings = mutableListOf<Long>()
    if (runs.first().amplitude != 0) timings.add(0L)
    runs.forEach { timings.add(it.durationMs) }

    return if (timings.size >= 2) timings.toLongArray() else null
}
