package com.linkdev.flutter_haptics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Guards the one place this package second-guesses the device vendor, and the
 * line it will not cross.
 *
 * `performHapticFeedback` answers for a constant it accepted, not one the user
 * felt, and on an actuator with neither amplitude control nor primitives the
 * two can differ. `perform` therefore prefers its pattern on that hardware,
 * because it has one it knows works. `playSystem` is never second-guessed: it
 * was asked for one exact constant and has no fallback to prefer.
 *
 * The judgement is made entirely from what the device reports about itself.
 * There is deliberately no list of constants believed to be perceptible —
 * Android documents no durations and exposes no API to ask, so such a list
 * could only ever be one tester's handset generalised into everyone's
 * behaviour.
 */
internal class PerceptibleConstantsTest {
    private fun answerFor(name: String, requirePerceptible: Boolean) =
        playSystemHaptic(
            view = null,
            vibrator = null,
            name = name,
            minimumVersion = 0,
            requirePerceptible = requirePerceptible,
        ).toMap()

    @Test
    fun playSystem_isNeverSecondGuessed() {
        // Without a vibrator it still fails, but on the hardware check rather
        // than the perceptibility one — the vendor is trusted either way.
        val answer = answerFor("clockTick", requirePerceptible = false)

        assertEquals(false, answer["played"])
        assertTrue(
            (answer["reason"] as String).contains("no vibrator"),
            "playSystem refused before reaching the device: ${answer["reason"]}",
        )
    }

    @Test
    fun perform_isAlsoCheckedAgainstTheHardwareFirst() {
        // Same here: with no vibrator at all there is nothing to judge.
        val answer = answerFor("clockTick", requirePerceptible = true)

        assertEquals(false, answer["played"])
        assertTrue((answer["reason"] as String).contains("no vibrator"))
    }

    @Test
    fun noConstantIsTreatedAsSpecial() {
        // Every constant takes the same path. If this ever stops being true,
        // the reason had better come from the device and not from a tester.
        val reasons = listOf("longPress", "clockTick", "toggleOn", "confirm")
            .map { answerFor(it, requirePerceptible = true)["reason"] as String }
            .map { it.substringAfter("so ").substringAfter(" ") }

        assertEquals(1, reasons.toSet().size, "constants diverged: $reasons")
    }
}
