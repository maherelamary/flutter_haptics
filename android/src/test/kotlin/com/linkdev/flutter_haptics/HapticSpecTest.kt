package com.linkdev.flutter_haptics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Covers the platform-independent half of the Android implementation: parsing
 * the map from Dart, flattening overlapping events onto one timeline, and
 * sampling that timeline into waveform runs. None of this touches android.os,
 * so it runs as a plain JVM test.
 */
internal class HapticSpecTest {
    private fun transient(delayMs: Int, intensity: Double, sharpness: Double = 0.5) =
        mapOf(
            "type" to "transient",
            "delayMs" to delayMs,
            "intensity" to intensity,
            "sharpness" to sharpness,
        )

    private fun continuous(
        delayMs: Int,
        durationMs: Int,
        intensity: List<Pair<Double, Double>>,
        sharpness: List<Pair<Double, Double>> = listOf(0.0 to 0.5, 1.0 to 0.5),
    ) = mapOf(
        "type" to "continuous",
        "delayMs" to delayMs,
        "durationMs" to durationMs,
        "intensityCurve" to intensity.map { mapOf("time" to it.first, "value" to it.second) },
        "sharpnessCurve" to sharpness.map { mapOf("time" to it.first, "value" to it.second) },
    )

    // ── Parsing ──────────────────────────────────────────────────────────

    @Test
    fun parse_readsTransientsAndContinuous() {
        val spec = HapticSpec.parse(
            listOf(
                transient(delayMs = 0, intensity = 0.8),
                continuous(delayMs = 100, durationMs = 200, intensity = listOf(0.0 to 1.0, 1.0 to 0.0)),
            ),
        )

        assertEquals(1, spec.transients.size)
        assertEquals(1, spec.continuous.size)
        assertTrue(spec.hasContinuous)
        assertEquals(300L, spec.durationMs)
    }

    @Test
    fun parse_dropsMalformedEntriesInsteadOfFailing() {
        val spec = HapticSpec.parse(
            listOf(
                transient(delayMs = 0, intensity = 0.8),
                mapOf("type" to "transient"), // missing fields
                mapOf("type" to "nonsense"),
                "not a map",
                continuous(delayMs = 0, durationMs = 0, intensity = listOf(0.0 to 1.0)), // zero length
            ),
        )

        assertEquals(1, spec.transients.size)
        assertEquals(0, spec.continuous.size)
    }

    @Test
    fun parse_clampsValuesOutOfRange() {
        val spec = HapticSpec.parse(listOf(transient(delayMs = 0, intensity = 5.0, sharpness = -2.0)))

        assertEquals(1f, spec.transients[0].intensity)
        assertEquals(0f, spec.transients[0].sharpness)
    }

    // ── Sampling ─────────────────────────────────────────────────────────

    @Test
    fun sampleAt_followsAContinuousCurve() {
        val spec = HapticSpec.parse(
            listOf(continuous(delayMs = 0, durationMs = 100, intensity = listOf(0.0 to 0.0, 1.0 to 1.0))),
        )

        assertEquals(0f, spec.sampleAt(0, 20).first)
        assertEquals(0.5f, spec.sampleAt(50, 20).first, absoluteTolerance = 0.01f)
        assertEquals(1f, spec.sampleAt(100, 20).first)
    }

    @Test
    fun sampleAt_isSilentOutsideTheEvent() {
        val spec = HapticSpec.parse(
            listOf(continuous(delayMs = 50, durationMs = 50, intensity = listOf(0.0 to 1.0, 1.0 to 1.0))),
        )

        assertEquals(0f, spec.sampleAt(0, 20).first)
        assertEquals(1f, spec.sampleAt(75, 20).first)
        assertEquals(0f, spec.sampleAt(200, 20).first)
    }

    @Test
    fun sampleAt_loudestOverlappingEventWinsAndCarriesItsSharpness() {
        // A soft rumble with a hard tap on top of it.
        val spec = HapticSpec.parse(
            listOf(
                continuous(
                    delayMs = 0,
                    durationMs = 100,
                    intensity = listOf(0.0 to 0.3, 1.0 to 0.3),
                    sharpness = listOf(0.0 to 0.1, 1.0 to 0.1),
                ),
                transient(delayMs = 50, intensity = 0.9, sharpness = 0.9),
            ),
        )

        val (duringRumble, rumbleSharpness) = spec.sampleAt(10, 20)
        assertEquals(0.3f, duringRumble, absoluteTolerance = 0.01f)
        assertEquals(0.1f, rumbleSharpness, absoluteTolerance = 0.01f)

        val (duringTap, tapSharpness) = spec.sampleAt(55, 20)
        assertEquals(0.9f, duringTap, absoluteTolerance = 0.01f)
        assertEquals(0.9f, tapSharpness, absoluteTolerance = 0.01f)
    }

    @Test
    fun sampleAt_treatsATransientAsASpikeOfTheGivenWidth() {
        val spec = HapticSpec.parse(listOf(transient(delayMs = 100, intensity = 1.0)))

        assertEquals(0f, spec.sampleAt(99, 20).first)
        assertEquals(1f, spec.sampleAt(100, 20).first)
        assertEquals(1f, spec.sampleAt(119, 20).first)
        assertEquals(0f, spec.sampleAt(120, 20).first)
    }

    // ── Waveform sampling ────────────────────────────────────────────────

    @Test
    fun sampleRuns_producesADescendingRampForAFadeOut() {
        val spec = HapticSpec.parse(
            listOf(continuous(delayMs = 0, durationMs = 200, intensity = listOf(0.0 to 1.0, 1.0 to 0.0))),
        )

        val runs = sampleRuns(spec, binarize = false)

        assertTrue(runs.isNotEmpty())
        assertTrue(runs.first().amplitude > 200, "starts near full: ${runs.first().amplitude}")
        assertTrue(runs.last().amplitude < runs.first().amplitude, "amplitude falls over time")
        val amplitudes = runs.map { it.amplitude }
        assertEquals(amplitudes.sortedDescending(), amplitudes, "ramp is monotonically decreasing")
    }

    @Test
    fun sampleRuns_totalDurationTracksThePattern() {
        val spec = HapticSpec.parse(
            listOf(continuous(delayMs = 0, durationMs = 300, intensity = listOf(0.0 to 1.0, 1.0 to 1.0))),
        )

        val total = sampleRuns(spec, binarize = false).sumOf { it.durationMs }

        assertTrue(total in 280L..320L, "expected roughly 300ms, got $total")
    }

    @Test
    fun sampleRuns_mergesConstantStretchesIntoOneRun() {
        val spec = HapticSpec.parse(
            listOf(continuous(delayMs = 0, durationMs = 200, intensity = listOf(0.0 to 0.6, 1.0 to 0.6))),
        )

        val runs = sampleRuns(spec, binarize = false)

        assertEquals(1, runs.size, "a flat rumble should collapse to a single run")
    }

    @Test
    fun sampleRuns_trimsTrailingSilence() {
        // Rumble for 100ms inside a pattern that runs to 500ms.
        val spec = HapticSpec.parse(
            listOf(
                continuous(delayMs = 0, durationMs = 100, intensity = listOf(0.0 to 1.0, 1.0 to 1.0)),
                continuous(delayMs = 400, durationMs = 100, intensity = listOf(0.0 to 0.0, 1.0 to 0.0)),
            ),
        )

        val runs = sampleRuns(spec, binarize = false)

        assertTrue(runs.last().amplitude > 0, "no trailing silent run")
        assertTrue(runs.sumOf { it.durationMs } < 200L, "silence at the end is dropped")
    }

    @Test
    fun sampleRuns_binarizedGivesAlternatingOnAndOff() {
        val spec = HapticSpec.parse(
            listOf(
                transient(delayMs = 0, intensity = 1.0),
                transient(delayMs = 200, intensity = 1.0),
            ),
        )

        val runs = sampleRuns(spec, binarize = true)

        assertTrue(runs.size >= 3, "two taps separated by a gap: $runs")
        assertTrue(runs.all { it.amplitude == 0 || it.amplitude == 255 }, "binarized")
        runs.zipWithNext { a, b -> assertTrue(a.amplitude != b.amplitude, "runs alternate") }
    }

    // ── On/off timings ───────────────────────────────────────────────────

    @Test
    fun onOffTimings_startsWithAnOffDuration() {
        // Android reads index 0 as silence, so a pattern that starts buzzing
        // needs a zero-length gap in front of it.
        val spec = HapticSpec.parse(listOf(transient(delayMs = 0, intensity = 1.0)))

        val timings = assertNotNull(onOffTimings(spec))

        assertEquals(0L, timings[0], "leading off slot")
        assertTrue(timings.size >= 2)
        assertTrue(timings[1] > 0, "then an audible on slot")
    }

    @Test
    fun onOffTimings_keepsTheLeadingDelayOfADelayedTap() {
        val spec = HapticSpec.parse(listOf(transient(delayMs = 200, intensity = 1.0)))

        val timings = assertNotNull(onOffTimings(spec))

        assertTrue(timings[0] in 180L..220L, "leading silence preserved, got ${timings[0]}")
    }

    @Test
    fun onOffTimings_returnsNullForASilentPattern() {
        val spec = HapticSpec.parse(
            listOf(continuous(delayMs = 0, durationMs = 100, intensity = listOf(0.0 to 0.0, 1.0 to 0.0))),
        )

        assertNull(onOffTimings(spec))
    }

    @Test
    fun onOffTimings_returnsNullForAnEmptyPattern() {
        assertNull(onOffTimings(HapticSpec.parse(emptyList<Any>())))
    }
}
