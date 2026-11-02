package com.linkdevelopment.flutterHaptics

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
        // A pattern longer than the device allows declines rather than being
        // cut short: the waveform tiers play all of it.
        if (spec.durationMs > maxTotal - 2 * minStep) return null
        val length = spec.durationMs.coerceAtLeast(minStep)

        var points = envelopeTimeline(spec, minStep, length) ?: return null

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

/**
 * The (time, intensity, sharpness) points an envelope passes through, in
 * milliseconds from the pattern start, at least [minStep] apart.
 *
 * Built in two passes. The first takes the points the events themselves
 * define — their edges and curve points — and enforces the spacing on those
 * alone, so an event's start is never crowded out by anything added for it.
 * Where two of them still crowd each other, an event's start wins over
 * whatever came before it: a rumble running a few milliseconds long into a
 * tap is a blur, while a tap that vanishes is a lost haptic. Each start
 * also gets a point one step ahead of it wherever something is already
 * playing there, holding that level until the event rises.
 *
 * The second writes the silence down. Every control point is a *ramp* from
 * the one before it, so two neighbouring points with nothing between them
 * would leave the vibrator gliding from the end of one event to the start of
 * the next, buzzing through the gap. Where two points are at least two steps
 * apart, a point one step inside each loud end is added wherever that spot
 * is silent, so the gap holds at zero and each edge rises or falls as fast
 * as the hardware allows. An end that is already silent needs no such point,
 * and on hardware with a small point budget one wasted is one more chance
 * for downsampling to drop a real one. A narrower gap is too short for the
 * hardware to show silence in, and is left to ramp across.
 *
 * Returns null when fewer than two points survive the spacing.
 */
internal fun envelopeTimeline(
    spec: HapticSpec,
    minStep: Long,
    length: Long,
): List<Triple<Long, Float, Float>>? {
    val times = sortedSetOf(0L, length)
    fun add(t: Long) {
        times.add(t.coerceIn(0L, length))
    }

    val starts = spec.events.map { it.startMs.coerceIn(0L, length) }.toSet()
    for (event in spec.events) {
        add(event.startMs)
        // Hold whatever is already playing until one step before an event
        // starts, so the event rises in one step rather than the run-up
        // ramping toward it — a rumble under a tap would otherwise climb
        // from its last point to the tap's strength over its whole length.
        val before = event.startMs - minStep
        if (before > 0 && spec.sampleAt(before, minStep).first > 0f) add(before)
        when (event) {
            is ContinuousSpec -> {
                add(event.endMs)
                for ((t, _) in event.intensity + event.sharpness) {
                    add(event.startMs + (t * event.durationMs).toLong())
                }
            }

            // A transient is sampled as a spike minStep wide, so its far edge
            // is where it has already fallen silent.
            is TransientSpec -> add(event.startMs + minStep)
        }
    }

    // Enforce the device's minimum spacing between control points.
    val edges = mutableListOf<Long>()
    for (t in times) {
        val last = edges.lastOrNull()
        when {
            last == null || t - last >= minStep -> edges.add(t)
            // Replacing the last point keeps the spacing: t is later than it,
            // so t is further still from the point before.
            t in starts && last !in starts -> edges[edges.lastIndex] = t
        }
    }
    if (edges.size < 2) return null

    val timeline = mutableListOf(edges.first())
    for ((from, to) in edges.zipWithNext()) {
        val gap = to - from
        if (gap >= 2 * minStep) {
            var fall = spec.sampleAt(from, minStep).first > 0f
            val rise = spec.sampleAt(to, minStep).first > 0f
            // Room for both only from three steps up, or the two would sit
            // closer than the hardware allows. With room for one, it goes
            // before the next event, keeping its onset crisp at the cost of a
            // slower fall from the one before.
            if (fall && rise && gap < 3 * minStep) fall = false
            for ((t, wanted) in listOf(from + minStep to fall, to - minStep to rise)) {
                if (wanted && spec.sampleAt(t, minStep).first == 0f) timeline.add(t)
            }
        }
        timeline.add(to)
    }

    return timeline.map { t ->
        val (intensity, sharpness) = spec.sampleAt(t, minStep)
        Triple(t, intensity, sharpness)
    }
}
