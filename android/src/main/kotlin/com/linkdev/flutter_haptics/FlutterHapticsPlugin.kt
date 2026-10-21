package com.linkdev.flutter_haptics

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.Vibrator
import android.os.VibratorManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android implementation of FlutterHaptics.
 *
 * A pattern is parsed once into a [HapticSpec], then handed to the best
 * renderer the device can actually play — see [selectPlan] for the ladder,
 * which runs from true intensity/sharpness envelopes on Android 16 hardware
 * down to a plain on/off buzz on Android 7.
 *
 * Fidelity degrades down that ladder, but something plays on every device
 * with a vibrator. Where nothing can play — no vibrator, or an error anywhere
 * along the way — the call succeeds silently, mirroring the iOS contract.
 */
class FlutterHapticsPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    private lateinit var channel: MethodChannel
    private var context: Context? = null

    /**
     * Held only to reach a `View` for `performHapticFeedback`, which is the
     * best-feeling route for semantic feedback. Everything else works without
     * an Activity, so a null one degrades rather than fails.
     */
    private var activity: Activity? = null

    /**
     * Patterns already parsed and matched to a renderer, kept so a repeated
     * pattern does not walk the ladder again on every play.
     */
    private val registered = mutableMapOf<Int, VibrationPlan>()
    private var nextRegistrationId = 1

    /** Marks this vibration as touch feedback so the system routes it correctly. */
    private val touchAudioAttributes: AudioAttributes by lazy {
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_haptics")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
        registered.clear()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            // Every method answers rather than failing silently: the Dart
            // side turns a reason into a log, a throw or nothing, per the
            // app's configured policy.
            "play" -> {
                result.success(
                    runCatching { handlePlay(call) }
                        .getOrElse { NativeAnswer.failed("$it") }
                        .toMap(),
                )
            }

            // Returns the registration id, or null when nothing could be
            // prepared — the Dart handle then falls back to plain `play`.
            "register" -> {
                result.success(runCatching { handleRegister(call) }.getOrNull())
            }

            // Reports an unknown id rather than swallowing it, so a handle
            // whose registration was lost can fall back to sending the
            // pattern. Silently succeeding made that fallback unreachable.
            "playRegistered" -> {
                result.success(
                    runCatching { handlePlayRegistered(call) }
                        .getOrElse { NativeAnswer.failed("$it") }
                        .toMap(),
                )
            }

            "unregister" -> {
                runCatching { registered.remove(call.idArgument()) }
                result.success(null)
            }

            "playSystem" -> {
                result.success(
                    runCatching { handlePlaySystem(call) }
                        .getOrElse { NativeAnswer.failed("$it") }
                        .toMap(),
                )
            }

            "support" -> {
                result.success(
                    runCatching { describeSupport(vibrator()) }.getOrDefault(UNSUPPORTED),
                )
            }

            "prepare" -> {
                // No engine to warm up on Android.
                result.success(null)
            }

            "stop" -> {
                runCatching { vibrator()?.cancel() }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun handlePlay(call: MethodCall): NativeAnswer {
        val vibrator = vibrator()
            ?: return NativeAnswer.failed("no vibrator on this device")
        val args = call.arguments as? Map<*, *>
            ?: return NativeAnswer.failed("malformed arguments")
        val rawEvents = args["events"] as? List<*>
            ?: return NativeAnswer.failed("no events in the pattern")

        val spec = HapticSpec.parse(rawEvents)
        val plan = selectPlan(vibrator, spec)
            ?: return NativeAnswer.failed("nothing on this device can render that pattern")

        dispatch(vibrator, plan)
        return NativeAnswer.played()
    }

    /** Parses and plans a pattern once, keyed by an id the Dart side holds. */
    private fun handleRegister(call: MethodCall): Int? {
        val vibrator = vibrator() ?: return null
        val args = call.arguments as? Map<*, *> ?: return null
        val rawEvents = args["events"] as? List<*> ?: return null

        val plan = selectPlan(vibrator, HapticSpec.parse(rawEvents)) ?: return null
        val id = nextRegistrationId++
        registered[id] = plan
        return id
    }

    private fun handlePlayRegistered(call: MethodCall): NativeAnswer {
        val id = call.idArgument()
            ?: return NativeAnswer.failed("no registration id given")
        val plan = registered[id]
            ?: return NativeAnswer.failed("no registration $id on this plugin")
        val vibrator = vibrator()
            ?: return NativeAnswer.failed("no vibrator on this device")

        dispatch(vibrator, plan)
        return NativeAnswer.played()
    }

    private fun MethodCall.idArgument(): Int? =
        ((arguments as? Map<*, *>)?.get("id") as? Number)?.toInt()

    /** Plays one of Android's own constants, or says why it could not. */
    private fun handlePlaySystem(call: MethodCall): NativeAnswer {
        val args = call.arguments as? Map<*, *>
            ?: return NativeAnswer.failed("malformed arguments")
        val name = args["name"] as? String
            ?: return NativeAnswer.failed("no haptic name given")
        val minimumVersion = (args["minimumVersion"] as? Number)?.toInt() ?: 1

        return playSystemHaptic(
            view = activity?.window?.decorView,
            vibrator = vibrator(),
            name = name,
            minimumVersion = minimumVersion,
            requirePerceptible = args["requirePerceptible"] == true,
        )
    }

    /**
     * A single `vibrate()` per pattern. Each call cancels the one before it,
     * so the whole pattern has to arrive as one plan.
     */
    private fun dispatch(vibrator: Vibrator, plan: VibrationPlan) {
        when (plan) {
            is VibrationPlan.Effect ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    vibrator.vibrate(plan.effect, touchVibrationAttributes())
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(plan.effect, touchAudioAttributes)
                }

            is VibrationPlan.Legacy -> {
                @Suppress("DEPRECATION")
                vibrator.vibrate(plan.timings, -1, touchAudioAttributes)
            }
        }
    }

    /** VibrationAttributes.createForUsage arrived in API 33, later than the class itself. */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun touchVibrationAttributes(): VibrationAttributes =
        VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH)

    /** VibratorManager is API 31; older releases go through the system service directly. */
    private fun vibrator(): Vibrator? {
        val context = context ?: return null
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        return vibrator?.takeIf { it.hasVibrator() }
    }
}
