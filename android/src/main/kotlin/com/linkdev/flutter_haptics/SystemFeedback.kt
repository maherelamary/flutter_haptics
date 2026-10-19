package com.linkdev.flutter_haptics

import android.os.Build
import android.os.Vibrator
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * Android's own haptic vocabulary — the twenty playable
 * `HapticFeedbackConstants`.
 *
 * None of this is synthesised. These are the effects the device vendor tuned
 * and the rest of the system already uses, so one played here feels like one
 * played in the launcher.
 *
 * `NO_HAPTICS` is deliberately absent: it means "play nothing on purpose",
 * which is already what not calling anything does.
 *
 * Everything goes through `View.performHapticFeedback`. That is the canonical
 * route — vendor-tuned, and the platform applies the user's haptic settings
 * for us. It needs an Activity, which a visible Flutter app always has; where
 * one is not attached the call reports that rather than substituting a
 * different effect from a different vocabulary.
 */

/** Names match the Dart `AndroidHaptic` enum exactly; the wire sends the name. */
private val CONSTANTS: Map<String, Int> = mapOf(
    "longPress" to HapticFeedbackConstants.LONG_PRESS,
    "virtualKey" to HapticFeedbackConstants.VIRTUAL_KEY,
    "keyboardTap" to HapticFeedbackConstants.KEYBOARD_TAP,
    "clockTick" to HapticFeedbackConstants.CLOCK_TICK,
    "contextClick" to HapticFeedbackConstants.CONTEXT_CLICK,
    "keyboardPress" to HapticFeedbackConstants.KEYBOARD_PRESS,
    "keyboardRelease" to HapticFeedbackConstants.KEYBOARD_RELEASE,
    "virtualKeyRelease" to HapticFeedbackConstants.VIRTUAL_KEY_RELEASE,
    "textHandleMove" to HapticFeedbackConstants.TEXT_HANDLE_MOVE,
    "confirm" to HapticFeedbackConstants.CONFIRM,
    "reject" to HapticFeedbackConstants.REJECT,
    "gestureStart" to HapticFeedbackConstants.GESTURE_START,
    "gestureEnd" to HapticFeedbackConstants.GESTURE_END,
    "dragStart" to HapticFeedbackConstants.DRAG_START,
    "gestureThresholdActivate" to HapticFeedbackConstants.GESTURE_THRESHOLD_ACTIVATE,
    "gestureThresholdDeactivate" to HapticFeedbackConstants.GESTURE_THRESHOLD_DEACTIVATE,
    "segmentFrequentTick" to HapticFeedbackConstants.SEGMENT_FREQUENT_TICK,
    "segmentTick" to HapticFeedbackConstants.SEGMENT_TICK,
    "toggleOff" to HapticFeedbackConstants.TOGGLE_OFF,
    "toggleOn" to HapticFeedbackConstants.TOGGLE_ON,
)

/**
 * Plays [name], or says why it could not.
 *
 * The checks run in the order a caller would want to hear about them: too old
 * for the constant, no hardware, hardware that cannot render it, then the
 * system's own answer.
 *
 * [minimumVersion] arrives from Dart, where each `AndroidHaptic` value carries
 * the SDK level its constant was added in. Keeping it on the Dart side means
 * the two never drift apart.
 */
internal fun playSystemHaptic(
    view: View?,
    vibrator: Vibrator?,
    name: String,
    minimumVersion: Int,
    requirePerceptible: Boolean,
): NativeAnswer {
    if (Build.VERSION.SDK_INT < minimumVersion) {
        return NativeAnswer.failed(
            "$name requires API $minimumVersion, this device is ${Build.VERSION.SDK_INT}",
        )
    }

    val constant = CONSTANTS[name]
        ?: return NativeAnswer.failed("unknown Android haptic \"$name\"")

    vibrator ?: return NativeAnswer.failed("no vibrator on this device")

    // performHapticFeedback answers true for a constant it accepted, not one
    // the user felt, and a rotating-mass actuator may not render a short
    // effect at all. Whether to trust it depends on who is asking.
    //
    // `perform` asks for a *meaning* to be felt and carries a pattern this
    // package knows works, so where the answer is doubtful the pattern is the
    // safer route — that is [requirePerceptible]. The judgement is made from
    // what the device reports about itself, never from a list of constants:
    // Android documents no durations and exposes no API to ask, so any such
    // list would be one tester's handset generalised into everyone's
    // behaviour.
    //
    // `playSystem` asks for this exact constant and has no fallback. These
    // constants are implemented by the device vendor for this device's
    // hardware, which is the entire reason they exist; second-guessing them
    // with a heuristic would be overreach, and would hide whether they work.
    if (requirePerceptible && !rendersShortEffects(vibrator)) {
        return NativeAnswer.failed(
            "this actuator has no amplitude control and no primitives, so " +
                "$name may be accepted without being rendered",
        )
    }

    val target = view
        ?: return NativeAnswer.failed("no Activity attached, so there is no View to play through")

    // FLAG_IGNORE_VIEW_SETTING overrides the *view's* haptic flag, which the
    // Flutter decor view does not set. The user's system-wide setting is
    // applied by the platform either way.
    val played = target.performHapticFeedback(
        constant,
        HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING,
    )

    return if (played) {
        NativeAnswer.played()
    } else {
        NativeAnswer.failed("the system declined $name")
    }
}

/** What the Dart side reads back from `play` and `playSystem`. */
internal class NativeAnswer private constructor(
    private val played: Boolean,
    private val reason: String,
) {
    fun toMap(): Map<String, Any> = mapOf("played" to played, "reason" to reason)

    companion object {
        fun played() = NativeAnswer(true, "")

        fun failed(reason: String) = NativeAnswer(false, reason)
    }
}
