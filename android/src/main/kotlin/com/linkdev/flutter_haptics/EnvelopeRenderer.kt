package com.linkdev.flutter_haptics

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.RequiresApi

/**
 * Tier 1 — real intensity/sharpness envelopes (Android 16 on capable hardware).
 *
 * This is the only tier that reproduces a pattern faithfully: Android's
 * `BasicEnvelopeBuilder` speaks the same intensity/sharpness language as
 * Core Haptics, so curves survive the crossing more or less intact.
 *
 * The whole pattern becomes one envelope. Transients are folded in as spikes
 * one control point wide, and gaps between events become zero-intensity
 * points, which costs budget but keeps the timing honest.
 */
internal object EnvelopeRenderer : HapticRenderer {
    private const val DEFAULT_MIN_STEP_MS = 20L
    private const val DEFAULT_MAX_STEP_MS = 1_000L
    private const val DEFAULT_MAX_POINTS = 16
    private const val DEFAULT_MAX_TOTAL_MS = 5_000L

    override fun render(vibrator: Vibrator, spec: HapticSpec): VibrationPlan? {
        if (Build.VERSION.SDK_INT < API_ENVELOPES) return null
        if (!vibrator.areEnvelopeEffectsSupported()) return null
        return buildEnvelope(vibrator, spec)?.let(VibrationPlan::Effect)
    }

    @RequiresApi(API_ENVELOPES)
    private fun buildEnvelope(vibrator: Vibrator, spec: HapticSpec): VibrationEffect? {
        // The hardware advertises its own budgets; the fallbacks are the
        // minimums AOSP requires a compliant device to support.
        val info = vibrator.envelopeEffectInfo
        val minStep = info.minControlPointDurationMillis
            .takeIf { it > 0 }?.coerceAtLeast(1L) ?: DEFAULT_MIN_STEP_MS
        val maxStep = info.maxControlPointDurationMillis
            .takeIf { it > 0 } ?.coerceAtLeast(minStep) ?: DEFAULT_MAX_STEP_MS.coerceAtLeast(minStep)
        val maxPoints = info.maxSize.takeIf { it > 0 }?.coerceAtLeast(4) ?: DEFAULT_MAX_POINTS
        val maxTotal = info.maxDurationMillis
            .takeIf { it > 0 }?.coerceAtLeast(minStep * 2) ?: DEFAULT_MAX_TOTAL_MS

        // Reserve room for the initial attack ramp and the trailing zero point.
        val length = spec.durationMs
            .coerceAtLeast(minStep)
            .coerceAtMost(maxTotal - 2 * minStep)
        if (length <= 0) return null

        // Candidate timeline points, in milliseconds from the pattern start.
        val times = sortedSetOf(0L, length)
        for (event in spec.events) {
            when (event) {
                is ContinuousSpec -> {
                    times.add(event.startMs.coerceAtMost(length))
                    times.add(event.endMs.coerceAtMost(length))
                    for ((t, _) in event.intensity + event.sharpness) {
                        times.add((event.startMs + (t * event.durationMs).toLong()).coerceAtMost(length))
                    }
                }

                is TransientSpec -> {
                    times.add(event.startMs.coerceAtMost(length))
                    times.add((event.startMs + minStep).coerceAtMost(length))
                }
            }
        }

        // Enforce the device's minimum spacing between control points.
        val timeline = mutableListOf<Long>()
        for (t in times) {
            if (timeline.isEmpty() || t - timeline.last() >= minStep) timeline.add(t)
        }
        if (timeline.size < 2) return null

        var points = timeline.map { t ->
            val (intensity, sharpness) = spec.sampleAt(t, minStep)
            Triple(t, intensity, sharpness)
        }

        // Downsample uniformly if the device cannot take this many points,
        // always keeping the final one. A slot is reserved for the trailing
        // zero-intensity point every basic envelope has to end on.
        val budget = maxPoints - 1
        if (points.size > budget) {
            val step = points.size.toDouble() / budget
            var lastTime = -1L
            points = List(budget) { index ->
                if (index == budget - 1) points.last() else points[(index * step).toInt().coerceAtMost(points.size - 1)]
            }.filter { point ->
                (point.first > lastTime).also { keep -> if (keep) lastTime = point.first }
            }
        }
        if (points.isEmpty()) return null

        var builder = VibrationEffect.BasicEnvelopeBuilder()
            .setInitialSharpness(points.first().third.coerceIn(0f, 1f))
        var previousTime = 0L
        var previous: Triple<Long, Float, Float>? = null
        var pointsLeft = maxPoints - 1
        var durationLeft = maxTotal - minStep

        for (point in points) {
            if (pointsLeft <= 0 || durationLeft < minStep) break
            val segment = if (point.first == 0L) minStep else point.first - previousTime
            var remaining = segment.coerceAtMost(durationLeft)

            // Split segments longer than the device's maximum control point
            // duration, interpolating linearly so ramps stay ramps.
            while (remaining > maxStep && pointsLeft > 1) {
                val fraction = (segment - remaining + maxStep).toFloat() / segment.toFloat()
                val fromIntensity = previous?.second ?: 0f
                val fromSharpness = previous?.third ?: point.third
                builder = builder.addControlPoint(
                    (fromIntensity + (point.second - fromIntensity) * fraction).coerceIn(0f, 1f),
                    (fromSharpness + (point.third - fromSharpness) * fraction).coerceIn(0f, 1f),
                    maxStep,
                )
                remaining -= maxStep
                pointsLeft--
                durationLeft -= maxStep
            }

            val stepDuration = remaining.coerceIn(minStep, maxStep)
            builder = builder.addControlPoint(
                point.second.coerceIn(0f, 1f),
                point.third.coerceIn(0f, 1f),
                stepDuration,
            )
            pointsLeft--
            durationLeft -= stepDuration
            previousTime = point.first
            previous = point
        }

        val last = previous ?: return null

        // A basic envelope must end at zero intensity; the API throws otherwise.
        if (last.second > 0f) {
            builder = builder.addControlPoint(0f, last.third.coerceIn(0f, 1f), minStep)
        }
        return builder.build()
    }
}
