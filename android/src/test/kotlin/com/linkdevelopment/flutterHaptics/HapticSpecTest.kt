package com.linkdevelopment.flutterHaptics

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

    @Test
    fun sampleRuns_keepsATapInAPatternLongerThanFiveSeconds() {
        // 8 s samples in 40 ms buckets. A 25 ms tap at 30 ms misses both
        // bucket midpoints (20 and 60), so it used to vanish.
        val spec = HapticSpec.parse(
            listOf(
                transient(delayMs = 30, intensity = 1.0),
                continuous(delayMs = 7_900, durationMs = 100, intensity = listOf(0.0 to 0.5, 1.0 to 0.5)),
            ),
        )

        val runs = sampleRuns(spec, binarize = false)

        assertTrue(runs.first().amplitude == 0 && runs[1].amplitude == 255, "tap survives: ${runs.take(3)}")
    }

    @Test
    fun sampleRuns_playsAPatternLongerThanTenSecondsToTheEnd() {
        // These used to stop at 10 s, dropping the closing tap while the
        // call still reported `played`.
        val spec = HapticSpec.parse(
            listOf(
                transient(delayMs = 0, intensity = 1.0),
                transient(delayMs = 14_000, intensity = 1.0),
            ),
        )

        for (binarize in listOf(false, true)) {
            val runs = sampleRuns(spec, binarize)
            assertTrue(runs.last().amplitude > 0, "closing tap survives: ${runs.takeLast(2)}")
            assertTrue(runs.sumOf { it.durationMs } > 14_000L, "plays to the end")
        }
    }

    // ── Envelope timeline ────────────────────────────────────────────────

    @Test
    fun envelopeTimeline_holdsSilenceBetweenTwoRumbles() {
        // Every envelope point is a ramp from the one before, so without a
        // zero either side of the gap it buzzed straight through it.
        val spec = HapticSpec.parse(
            listOf(
                continuous(delayMs = 0, durationMs = 100, intensity = listOf(0.0 to 0.8, 1.0 to 0.8)),
                continuous(delayMs = 300, durationMs = 100, intensity = listOf(0.0 to 0.8, 1.0 to 0.8)),
            ),
        )

        val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 400))

        val inGap = points.filter { it.first in 101L..299L }
        assertTrue(inGap.size >= 2, "the gap is bounded by points of its own: $points")
        assertTrue(inGap.all { it.second == 0f }, "and they are silent: $inGap")
    }

    @Test
    fun envelopeTimeline_risesToATapFromSilenceRightBeforeIt() {
        val spec = HapticSpec.parse(
            listOf(
                transient(delayMs = 0, intensity = 1.0),
                transient(delayMs = 500, intensity = 1.0),
            ),
        )

        val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 500))
        val tap = points.indexOfFirst { it.first == 500L }

        assertTrue(tap > 0, "the second tap has a point: $points")
        assertEquals(480L, points[tap - 1].first, "preceded one step earlier")
        assertEquals(0f, points[tap - 1].second, "by silence, not a 480 ms swell")
    }

    @Test
    fun envelopeTimeline_keepsATapShortlyAfterARumble() {
        // Gaps of 21–39 ms are under two steps: too short to show silence
        // in, but the tap after one must keep its point and its strength.
        for (gap in 21..39) {
            val spec = HapticSpec.parse(
                listOf(
                    continuous(delayMs = 0, durationMs = 100, intensity = listOf(0.0 to 0.8, 1.0 to 0.8)),
                    transient(delayMs = 100 + gap, intensity = 1.0),
                ),
            )

            val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 100L + gap))
            val tap = points.singleOrNull { it.first == 100L + gap }

            assertNotNull(tap, "gap $gap: the tap has a point: $points")
            assertEquals(1f, tap.second, "gap $gap: at full intensity")
        }
    }

    @Test
    fun envelopeTimeline_startsARumbleShortlyAfterAnotherOnItsOwnPoint() {
        val spec = HapticSpec.parse(
            listOf(
                continuous(delayMs = 0, durationMs = 100, intensity = listOf(0.0 to 0.8, 1.0 to 0.8)),
                continuous(delayMs = 130, durationMs = 100, intensity = listOf(0.0 to 0.6, 1.0 to 0.6)),
            ),
        )

        val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 230))
        val start = points.singleOrNull { it.first == 130L }

        assertNotNull(start, "the second rumble's start has a point: $points")
        assertEquals(0.6f, start.second, "at its own strength, not swelling from silence")
    }

    @Test
    fun envelopeTimeline_keepsTheSpacingAcrossEveryGapWidth() {
        // The silence points must respect the spacing too: two of them in a
        // 41 ms gap would sit 1 ms apart.
        for (gap in 0..100) {
            val spec = HapticSpec.parse(
                listOf(
                    continuous(delayMs = 0, durationMs = 100, intensity = listOf(0.0 to 0.8, 1.0 to 0.8)),
                    transient(delayMs = 100 + gap, intensity = 1.0),
                ),
            )

            val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 100L + gap))

            points.zipWithNext { a, b -> assertTrue(b.first - a.first >= 20, "gap $gap: $points") }
            // Even inside one step: the tap's start wins over the rumble's end.
            assertTrue(points.any { it.first == 100L + gap && it.second == 1f }, "gap $gap: tap kept: $points")
        }
    }

    @Test
    fun envelopeTimeline_keepsATapCrowdedByTheEdgeOfTheOneBefore() {
        // A tap's silent far edge sits one step after it, and used to crowd
        // out a second tap 20–39 ms later. Under 20 ms the two taps are
        // closer than the hardware can separate, and only one can stay.
        for (gap in 20..39) {
            val spec = HapticSpec.parse(
                listOf(
                    transient(delayMs = 0, intensity = 1.0),
                    transient(delayMs = gap, intensity = 1.0),
                ),
            )

            val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = gap.toLong()))

            assertTrue(points.any { it.first == gap.toLong() && it.second == 1f }, "gap $gap: $points")
            points.zipWithNext { a, b -> assertTrue(b.first - a.first >= 20, "gap $gap: $points") }
        }
    }

    @Test
    fun envelopeTimeline_addsNoSilenceAfterAnEdgeThatIsAlreadySilent() {
        // The first tap's far edge at 20 ms is already silent; a point at
        // 40 ms would say nothing and spend a point from the budget.
        val spec = HapticSpec.parse(
            listOf(
                transient(delayMs = 0, intensity = 1.0),
                transient(delayMs = 100, intensity = 1.0),
            ),
        )

        val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 100))

        assertEquals(listOf(0L, 20L, 80L, 100L), points.map { it.first })
    }

    @Test
    fun envelopeTimeline_holdsARumbleLevelUpToATapAtItsEnd() {
        for (gap in 0..19) {
            val spec = HapticSpec.parse(
                listOf(
                    continuous(delayMs = 0, durationMs = 1_000, intensity = listOf(0.0 to 0.3, 1.0 to 0.3)),
                    transient(delayMs = 1_000 + gap, intensity = 1.0),
                ),
            )

            val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 1_000L + gap))
            val tap = points.indexOfFirst { it.first == 1_000L + gap }

            assertEquals(980L + gap, points[tap - 1].first, "gap $gap: $points")
            assertEquals(0.3f, points[tap - 1].second, "gap $gap: holds its level, no 1 s swell")
        }
    }

    @Test
    fun envelopeTimeline_holdsARumbleLevelUpToATapInItsMiddle() {
        val spec = HapticSpec.parse(
            listOf(
                continuous(delayMs = 0, durationMs = 1_000, intensity = listOf(0.0 to 0.3, 1.0 to 0.3)),
                transient(delayMs = 500, intensity = 1.0),
            ),
        )

        val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 1_000))

        assertEquals(
            listOf(0L to 0.3f, 480L to 0.3f, 500L to 1f, 520L to 0.3f, 1_000L to 0.3f),
            points.map { it.first to it.second },
        )
    }

    @Test
    fun envelopeTimeline_keepsTheMinimumSpacing() {
        val spec = HapticSpec.parse(
            listOf(
                transient(delayMs = 0, intensity = 1.0),
                transient(delayMs = 30, intensity = 1.0),
                transient(delayMs = 45, intensity = 1.0),
            ),
        )

        val points = assertNotNull(envelopeTimeline(spec, minStep = 20, length = 45))

        points.zipWithNext { a, b -> assertTrue(b.first - a.first >= 20, "spacing: $points") }
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
