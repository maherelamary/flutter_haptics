package com.linkdev.flutter_haptics

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.RequiresApi
import kotlin.math.max

/**
 * Tier 2 — composition primitives (Android 11+).
 *
 * Primitives are tuned by the device vendor, so a tap rendered this way feels
 * better than anything we could synthesise. They cannot sustain, though, so a
 * pattern containing a continuous event declines and drops to a waveform tier.
 */
internal object CompositionRenderer : HapticRenderer {
    /** Primitives are short by design; used when the device cannot report durations. */
    private const val ASSUMED_PRIMITIVE_MS = 15L

    /** Defensive cap — the platform rejects oversized compositions. */
    private const val MAX_PRIMITIVES = 32

    /** Scale 0.0 is "minimum perceivable", not silence, so never go below this. */
    private const val MIN_SCALE = 0.05f

    override fun render(vibrator: Vibrator, spec: HapticSpec): VibrationPlan? {
        if (Build.VERSION.SDK_INT < API_PRIMITIVES) return null
        // No primitive sustains, so a rumble would be silently dropped.
        if (spec.hasContinuous) return null
        if (spec.transients.isEmpty()) return null
        return buildComposition(vibrator, spec)?.let(VibrationPlan::Effect)
    }

    @RequiresApi(API_PRIMITIVES)
    private fun buildComposition(vibrator: Vibrator, spec: HapticSpec): VibrationEffect? {
        var composition = VibrationEffect.startComposition()
        var previousEnd = 0L
        var added = 0

        for (transient in spec.transients) {
            if (added >= MAX_PRIMITIVES) break
            val primitive = primitiveFor(vibrator, transient.sharpness) ?: continue
            // A composition delay is measured from the end of the previous
            // primitive, not from the start of the pattern.
            val delay = (transient.startMs - previousEnd).coerceAtLeast(0L).toInt()
            composition = composition.addPrimitive(
                primitive,
                transient.intensity.coerceIn(MIN_SCALE, 1f),
                delay,
            )
            previousEnd = transient.startMs + max(durationOf(vibrator, primitive), 1L)
            added++
        }

        return if (added > 0) composition.compose() else null
    }

    /** Picks the crispest supported primitive matching the requested sharpness. */
    @RequiresApi(API_PRIMITIVES)
    private fun primitiveFor(vibrator: Vibrator, sharpness: Float): Int? {
        // PRIMITIVE_LOW_TICK only exists from API 31.
        val lowTick = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibrationEffect.Composition.PRIMITIVE_LOW_TICK
        } else {
            null
        }
        val click = VibrationEffect.Composition.PRIMITIVE_CLICK
        val tick = VibrationEffect.Composition.PRIMITIVE_TICK

        val preferred = when {
            sharpness >= 0.65f -> listOfNotNull(click, tick, lowTick)
            sharpness >= 0.35f -> listOfNotNull(tick, click, lowTick)
            else -> listOfNotNull(lowTick, tick, click)
        }
        return preferred.firstOrNull { vibrator.arePrimitivesSupported(it)[0] }
    }

    @RequiresApi(API_PRIMITIVES)
    private fun durationOf(vibrator: Vibrator, primitive: Int): Long =
        // getPrimitiveDurations arrived in API 31.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            vibrator.getPrimitiveDurations(primitive)[0].toLong()
        } else {
            ASSUMED_PRIMITIVE_MS
        }
}
