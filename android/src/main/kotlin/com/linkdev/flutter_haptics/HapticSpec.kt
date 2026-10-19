package com.linkdev.flutter_haptics

/** A single haptic unit, parsed from the map sent by the Dart side. */
internal sealed interface EventSpec {
    /** Offset from the start of the pattern, in milliseconds. */
    val startMs: Long

    /** End of the event. Equal to [startMs] for transients, which have no width. */
    val endMs: Long
}

internal data class TransientSpec(
    override val startMs: Long,
    val intensity: Float,
    val sharpness: Float,
) : EventSpec {
    override val endMs get() = startMs
}

internal data class ContinuousSpec(
    override val startMs: Long,
    val durationMs: Long,
    /** (time 0..1, value 0..1) control points, sorted by time. */
    val intensity: List<Pair<Float, Float>>,
    val sharpness: List<Pair<Float, Float>>,
) : EventSpec {
    override val endMs get() = startMs + durationMs
}

/**
 * A parsed pattern, plus the facts each renderer needs to decide whether it
 * can play it. All times are milliseconds from the start of the pattern.
 */
internal class HapticSpec(val events: List<EventSpec>) {
    val transients: List<TransientSpec> =
        events.filterIsInstance<TransientSpec>().sortedBy { it.startMs }

    val continuous: List<ContinuousSpec> =
        events.filterIsInstance<ContinuousSpec>().sortedBy { it.startMs }

    val hasContinuous: Boolean get() = continuous.isNotEmpty()

    val isEmpty: Boolean get() = events.isEmpty()

    /** End of the last event, which is also the pattern's total length. */
    val durationMs: Long = events.maxOfOrNull { it.endMs } ?: 0L

    /**
     * Intensity and sharpness at [atMs].
     *
     * Android drives a single vibrator, so overlapping events have to be
     * flattened somewhere. The loudest event wins and sharpness follows it,
     * which keeps accents intact instead of averaging them away.
     *
     * A transient has no width of its own, so it is sampled as a spike
     * [transientWidthMs] milliseconds wide.
     */
    fun sampleAt(atMs: Long, transientWidthMs: Long): Pair<Float, Float> {
        var intensity = 0f
        var sharpness = 0.5f
        for (event in events) {
            when (event) {
                is ContinuousSpec -> {
                    if (atMs < event.startMs || atMs > event.endMs) continue
                    val fraction = if (event.durationMs <= 0) {
                        0f
                    } else {
                        ((atMs - event.startMs).toFloat() / event.durationMs).coerceIn(0f, 1f)
                    }
                    val value = interpolate(event.intensity, fraction)
                    if (value > intensity) {
                        intensity = value
                        sharpness = interpolate(event.sharpness, fraction)
                    }
                }

                is TransientSpec -> {
                    if (atMs < event.startMs || atMs >= event.startMs + transientWidthMs) continue
                    if (event.intensity > intensity) {
                        intensity = event.intensity
                        sharpness = event.sharpness
                    }
                }
            }
        }
        return intensity to sharpness
    }

    companion object {
        /** Parses the `events` list from a `play` call. Malformed entries are dropped. */
        fun parse(rawEvents: List<*>): HapticSpec {
            val events = rawEvents.mapNotNull { raw ->
                val map = raw as? Map<*, *> ?: return@mapNotNull null
                when (map["type"] as? String) {
                    "transient" -> parseTransient(map)
                    "continuous" -> parseContinuous(map)
                    else -> null
                }
            }
            return HapticSpec(events)
        }

        private fun parseTransient(map: Map<*, *>): TransientSpec? {
            val delayMs = (map["delayMs"] as? Number)?.toLong() ?: return null
            val intensity = (map["intensity"] as? Number)?.toFloat() ?: return null
            val sharpness = (map["sharpness"] as? Number)?.toFloat() ?: return null
            return TransientSpec(
                startMs = delayMs.coerceAtLeast(0L),
                intensity = intensity.coerceIn(0f, 1f),
                sharpness = sharpness.coerceIn(0f, 1f),
            )
        }

        private fun parseContinuous(map: Map<*, *>): ContinuousSpec? {
            val delayMs = (map["delayMs"] as? Number)?.toLong() ?: return null
            val durationMs = (map["durationMs"] as? Number)?.toLong() ?: return null
            if (durationMs <= 0) return null
            val intensity = parseCurve(map["intensityCurve"]) ?: return null
            val sharpness = parseCurve(map["sharpnessCurve"]) ?: return null
            return ContinuousSpec(
                startMs = delayMs.coerceAtLeast(0L),
                durationMs = durationMs,
                intensity = intensity,
                sharpness = sharpness,
            )
        }

        private fun parseCurve(raw: Any?): List<Pair<Float, Float>>? {
            val list = raw as? List<*> ?: return null
            return list
                .mapNotNull { entry ->
                    val map = entry as? Map<*, *> ?: return@mapNotNull null
                    val time = (map["time"] as? Number)?.toFloat() ?: return@mapNotNull null
                    val value = (map["value"] as? Number)?.toFloat() ?: return@mapNotNull null
                    time.coerceIn(0f, 1f) to value.coerceIn(0f, 1f)
                }
                .sortedBy { it.first }
                .ifEmpty { null }
        }
    }
}

/** Linear interpolation across (time, value) control points. */
internal fun interpolate(points: List<Pair<Float, Float>>, fraction: Float): Float {
    if (points.isEmpty()) return 0f
    if (fraction <= points.first().first) return points.first().second
    if (fraction >= points.last().first) return points.last().second
    for (index in 1 until points.size) {
        val (t1, v1) = points[index]
        if (fraction > t1) continue
        val (t0, v0) = points[index - 1]
        if (t1 <= t0) return v1
        return v0 + (v1 - v0) * ((fraction - t0) / (t1 - t0))
    }
    return points.last().second
}
