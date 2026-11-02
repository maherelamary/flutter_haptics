package com.linkdevelopment.flutterHaptics

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/*
 * Unit tests for the method channel contract. In a plain JVM test
 * Build.VERSION.SDK_INT is 0, so all haptic calls take the silent no-op
 * path — which is exactly the contract on unsupported devices.
 *
 * Run with `./gradlew testDebugUnitTest` in the `example/android/` directory.
 */

internal class FlutterHapticsPluginTest {
    private val plugin = FlutterHapticsPlugin()

    @Test
    fun onMethodCall_prepare_succeeds() {
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("prepare", null), mockResult)

        Mockito.verify(mockResult).success(null)
    }

    @Test
    fun onMethodCall_stop_succeeds() {
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("stop", null), mockResult)

        Mockito.verify(mockResult).success(null)
    }

    @Test
    fun onMethodCall_support_reportsUnsupportedWithoutAVibrator() {
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("support", null), mockResult)

        Mockito.verify(mockResult).success(UNSUPPORTED)
    }

    @Test
    fun playSystemHaptic_tooOldForTheConstant_saysSo() {
        // Build.VERSION.SDK_INT is 0 in a plain JVM test, which stands in for
        // a device older than every constant.
        val answer = playSystemHaptic(null, null, "toggleOn", 34, false).toMap()

        assertEquals(false, answer["played"])
        assertTrue((answer["reason"] as String).contains("requires API 34"))
    }

    @Test
    fun playSystemHaptic_unknownName_saysSo() {
        // minimumVersion 0 so the version gate passes — SDK_INT is 0 here.
        val answer = playSystemHaptic(null, null, "nonsense", 0, false).toMap()

        assertEquals(false, answer["played"])
        assertTrue((answer["reason"] as String).contains("unknown Android haptic"))
    }

    @Test
    fun playSystemHaptic_withoutAVibrator_saysSo() {
        val answer = playSystemHaptic(null, null, "longPress", 0, false).toMap()

        assertEquals(false, answer["played"])
        assertTrue((answer["reason"] as String).contains("no vibrator"))
    }

    @Test
    fun playSystemHaptic_touchFeedbackOff_isSilencedRatherThanDeclined() {
        // A decline would send `perform` to its pattern, which plays straight
        // through the setting on Android 12 and older. Silenced does not.
        val vibrator = Mockito.mock(android.os.Vibrator::class.java)
        val answer = playSystemHaptic(
            view = null,
            vibrator = vibrator,
            name = "longPress",
            minimumVersion = 0,
            requirePerceptible = true,
            touchFeedbackOff = true,
        ).toMap()

        assertEquals(false, answer["played"])
        assertEquals(true, answer["silenced"])
    }

    @Test
    fun onMethodCall_playSystem_answersWithAReason() {
        val call = MethodCall("playSystem", mapOf("name" to "confirm", "minimumVersion" to 30))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(
            mapOf(
                "played" to false,
                "reason" to "confirm requires API 30, this device is 0",
                "registrationLost" to false,
                "silenced" to false,
            ),
        )
    }

    @Test
    fun onMethodCall_playRegistered_unknownId_saysTheRegistrationIsLost() {
        val call = MethodCall("playRegistered", mapOf("id" to 99))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        // The flag is what tells a handle to forget the id rather than keep
        // paying a round trip to rediscover that it is gone.
        Mockito.verify(mockResult).success(
            mapOf(
                "played" to false,
                "reason" to "no registration 99 on this plugin",
                "registrationLost" to true,
                "silenced" to false,
            ),
        )
    }

    @Test
    fun onMethodCall_play_answersWithAReasonWhenUnsupported() {
        val call = MethodCall(
            "play",
            mapOf(
                "events" to listOf(
                    mapOf("type" to "transient", "intensity" to 0.8, "sharpness" to 0.5, "delayMs" to 0),
                ),
            ),
        )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(
            mapOf(
                "played" to false,
                "reason" to "no vibrator on this device",
                "registrationLost" to false,
                "silenced" to false,
            ),
        )
    }

    @Test
    fun describeSupport_withoutAVibrator_reportsNothingPlays() {
        val support = describeSupport(null)

        assertEquals("none", support["fidelity"])
        assertEquals(false, support["continuous"])
    }

    @Test
    fun onMethodCall_unknownMethod_isNotImplemented() {
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("getPlatformVersion", null), mockResult)

        Mockito.verify(mockResult).notImplemented()
    }
}
