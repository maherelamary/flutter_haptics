import CoreHaptics
import Flutter
import UIKit

/// iOS implementation of FlutterHaptics.
///
/// A pattern is parsed once into a `HapticSpec`, then handed to whichever
/// renderer this device can use:
///
/// - Core Haptics (iPhone 8 and later) — intensity, sharpness and curves.
/// - UIKit feedback generators (iPhone 7) — taps only.
/// - Neither (iPad, and anything with no haptic hardware) — silent no-op.
///
/// Every method succeeds regardless, so callers never need a platform check.
public class FlutterHapticsPlugin: NSObject, FlutterPlugin {
    private let coreHaptics: CoreHapticsRenderer?
    private let feedbackGenerators: FeedbackGeneratorRenderer?

    /// Always present. Semantic feedback goes to UIKit on every device, even
    /// one with Core Haptics, because the system's own taps are the point.
    private let systemFeedback = SystemFeedbackRenderer()

    override init() {
        // Decided once: the hardware's capabilities do not change at runtime.
        if CoreHapticsRenderer.isSupported {
            coreHaptics = CoreHapticsRenderer()
            feedbackGenerators = nil
        } else {
            coreHaptics = nil
            feedbackGenerators = FeedbackGeneratorRenderer()
        }
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_haptics",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(FlutterHapticsPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "play":
            result(playPattern(call).asDictionary)

        case "register":
            // Returns the id, or nil when nothing could be prepared — the Dart
            // handle then falls back to sending the pattern on every play.
            if let args = call.arguments as? [String: Any],
               let rawEvents = args["events"] as? [[String: Any]] {
                let spec = HapticSpec.parse(rawEvents)
                result(coreHaptics?.register(spec) ?? feedbackGenerators?.register(spec))
            } else {
                result(nil)
            }

        case "playRegistered":
            if let id = registrationId(call) {
                coreHaptics?.playRegistered(id)
                feedbackGenerators?.playRegistered(id)
            }
            result(nil)

        case "unregister":
            if let id = registrationId(call) {
                coreHaptics?.unregister(id)
                feedbackGenerators?.unregister(id)
            }
            result(nil)

        case "playSystem":
            result(playSystemHaptic(call).asDictionary)

        case "support":
            result(describeSupport())

        case "prepare":
            coreHaptics?.prepare()
            feedbackGenerators?.prepare()
            systemFeedback.prepare()
            result(nil)

        case "stop":
            coreHaptics?.stop()
            feedbackGenerators?.stop()
            result(nil)

        default:
            // Reported honestly even on devices without haptics, so a genuine
            // API mismatch is not mistaken for unsupported hardware.
            result(FlutterMethodNotImplemented)
        }
    }

    private func registrationId(_ call: FlutterMethodCall) -> Int? {
        (call.arguments as? [String: Any])?["id"] as? Int
    }

    /// Renders a pattern, or says why it could not.
    private func playPattern(_ call: FlutterMethodCall) -> NativeAnswer {
        guard let args = call.arguments as? [String: Any],
              let rawEvents = args["events"] as? [[String: Any]]
        else { return .failed("malformed arguments") }

        let spec = HapticSpec.parse(rawEvents)
        if spec.isEmpty { return .failed("no events in the pattern") }

        if let coreHaptics {
            coreHaptics.play(spec)
            return .played()
        }
        if let feedbackGenerators, SystemFeedbackRenderer.isSupported {
            // Taps only on this device; a rumble has nothing to sustain it.
            if spec.transients.isEmpty {
                return .failed("this device plays taps only, and the pattern has none")
            }
            feedbackGenerators.play(spec)
            return .played()
        }
        return .failed("this device has no haptic hardware")
    }

    /// Plays one of iOS's own constants, or says why it could not.
    private func playSystemHaptic(_ call: FlutterMethodCall) -> NativeAnswer {
        guard let args = call.arguments as? [String: Any],
              let name = args["name"] as? String
        else { return .failed("malformed arguments") }

        return systemFeedback.play(name)
    }

    /// Describes what this device can reproduce, in the vocabulary the Dart
    /// side shares with Android.
    ///
    /// Mirrors the renderer choice made in `init`, with one addition: UIKit's
    /// feedback generators are only wired to a Taptic Engine on iPhone. On
    /// iPad they construct happily and then do nothing, so the idiom check is
    /// the closest a public API gets to asking whether the hardware exists.
    private func describeSupport() -> [String: Any] {
        if coreHaptics != nil {
            return ["fidelity": "full", "continuous": true]
        }

        if feedbackGenerators != nil, UIDevice.current.userInterfaceIdiom == .phone {
            // Taps carry intensity and a coarse sharpness through the
            // generator style, but nothing here can sustain a rumble.
            return ["fidelity": "intensity", "continuous": false]
        }

        return ["fidelity": "none", "continuous": false]
    }
}
