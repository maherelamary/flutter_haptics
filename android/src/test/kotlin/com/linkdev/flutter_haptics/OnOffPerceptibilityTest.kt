package com.linkdev.flutter_haptics

import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Guards the bottom tier against going imperceptible again.
 *
 * A device with no amplitude control drives a rotating mass, which needs tens
 * of milliseconds to spin up. Before this was accounted for, every tap-only
 * pattern came out of [onOffTimings] as a single 20 ms pulse — long enough for
 * the API, far too short for the motor. On a Galaxy A11 none of them could be
 * felt, which is what prompted these tests.
 *
 * So the rule is about the *shape* reaching the actuator, not about the API
 * accepting it: every stretch of "on" has to be wide enough to move the mass.
 */
internal class OnOffPerceptibilityTest {
    /** Below roughly this, a rotating-mass actuator never leaves standstill. */
    private val minimumPerceptibleMs = 40L

    private fun transient(delayMs: Int, intensity: Double, sharpness: Double = 0.5) =
        mapOf(
            "type" to "transient",
            "delayMs" to delayMs,
            "intensity" to intensity,
            "sharpness" to sharpness,
        )

    /** Index 0 is an "off" duration, so the odd indices are the pulses. */
    private fun pulsesOf(vararg events: Map<String, Any>): List<Long> {
        val timings = onOffTimings(HapticSpec.parse(events.toList()))
        return timings!!.filterIndexed { index, _ -> index % 2 == 1 }
    }

    @Test
    fun aSingleTapIsWideEnoughToBeFelt() {
        val pulses = pulsesOf(transient(0, 0.4))

        assertTrue(
            pulses.single() >= minimumPerceptibleMs,
            "a lone tap rendered as ${pulses.single()}ms, below the $minimumPerceptibleMs" +
                "ms a rotating mass needs to spin up",
        )
    }

    @Test
    fun everyPulseOfAMultiTapPatternIsWideEnough() {
        // success: taps at 0, 80 and 160 ms.
        val pulses = pulsesOf(
            transient(0, 0.5),
            transient(80, 0.7, 0.6),
            transient(160, 1.0, 0.8),
        )

        assertTrue(pulses.size == 3, "expected three pulses, got $pulses")
        assertTrue(
            pulses.all { it >= minimumPerceptibleMs },
            "a pulse was too short to be felt: $pulses",
        )
    }

    @Test
    fun widenedTapsStillLeaveGapsSoRhythmSurvives() {
        // The widening must not smear separate taps into one long buzz —
        // rhythm is the only thing this tier has left to carry meaning.
        val timings = onOffTimings(
            HapticSpec.parse(
                listOf(
                    transient(0, 0.7, 0.6),
                    transient(100, 0.7, 0.6),
                ),
            ),
        )!!

        val gaps = timings.filterIndexed { index, _ -> index % 2 == 0 }.drop(1)
        assertTrue(gaps.isNotEmpty(), "the two taps merged into one pulse: ${timings.toList()}")
        assertTrue(gaps.all { it > 0 }, "a gap collapsed to zero: ${timings.toList()}")
    }

    @Test
    fun theAmplitudePathKeepsItsFinerTransient() {
        // Only the on/off path widens. A device with amplitude control can
        // render a crisp tap, and should keep doing so.
        val runs = sampleRuns(HapticSpec.parse(listOf(transient(0, 0.8))), binarize = false)

        assertTrue(
            runs.sumOf { it.durationMs } < minimumPerceptibleMs,
            "the amplitude path was widened too: $runs",
        )
    }

    @Test
    fun aContinuousEventIsUntouched() {
        // Rumbles were already long enough; widening applies to transients.
        val runs = sampleRuns(
            HapticSpec.parse(
                listOf(
                    mapOf(
                        "type" to "continuous",
                        "delayMs" to 0,
                        "durationMs" to 100,
                        "intensityCurve" to listOf(
                            mapOf("time" to 0.0, "value" to 0.6),
                            mapOf("time" to 1.0, "value" to 0.6),
                        ),
                        "sharpnessCurve" to listOf(
                            mapOf("time" to 0.0, "value" to 0.5),
                            mapOf("time" to 1.0, "value" to 0.5),
                        ),
                    ),
                ),
            ),
            binarize = true,
        )

        assertTrue(
            runs.sumOf { it.durationMs } == 100L,
            "a 100ms rumble became ${runs.sumOf { it.durationMs }}ms",
        )
    }
}
