import UIKit

/// UIKit's own feedback vocabulary — the nine kinds iOS defines.
///
/// Deliberately separate from `FeedbackGeneratorRenderer`, which uses the same
/// UIKit classes to *approximate* a pattern on devices without Core Haptics.
/// Here the generators are the point, not a fallback: an iPhone 15 routes
/// `impactMedium` through UIKit even though Core Haptics is available, because
/// a tap should feel like every other tap on the device.
///
/// Generators are cached and re-prepared after each use — UIKit keeps the
/// Taptic Engine warm for a short window after `prepare()`, and a cold
/// generator adds noticeable latency to the first tap.
final class SystemFeedbackRenderer {
    private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private lazy var notificationGenerator = UINotificationFeedbackGenerator()
    private lazy var selectionGenerator = UISelectionFeedbackGenerator()

    /// Whether these generators are wired to real hardware.
    ///
    /// UIKit constructs them happily on every device and then does nothing on
    /// hardware without a Taptic Engine, so reporting `false` there keeps the
    /// plugin from claiming it played something it did not.
    static var isSupported: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    func prepare() {
        guard Self.isSupported else { return }
        impactGenerator(for: .medium).prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    /// Plays `name`, or says why it could not.
    ///
    /// Names match the Dart `IOSHaptic` enum exactly. The version check is
    /// skipped here because every one of these predates the package's iOS 15
    /// floor; the Dart side still carries the real minimum for honesty.
    func play(_ name: String) -> NativeAnswer {
        guard Self.isSupported else {
            return .failed("this device has no Taptic Engine, so \(name) cannot play")
        }

        if let style = Self.impactStyle(name) {
            let generator = impactGenerator(for: style)
            generator.impactOccurred()
            generator.prepare()
            return .played()
        }

        if let type = Self.notificationType(name) {
            notificationGenerator.notificationOccurred(type)
            notificationGenerator.prepare()
            return .played()
        }

        if name == "selection" {
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
            return .played()
        }

        return .failed("unknown iOS haptic \"\(name)\"")
    }

    // MARK: - Mapping

    private static func impactStyle(
        _ name: String
    ) -> UIImpactFeedbackGenerator.FeedbackStyle? {
        switch name {
        case "impactLight": return .light
        case "impactMedium": return .medium
        case "impactHeavy": return .heavy
        case "impactRigid": return .rigid
        case "impactSoft": return .soft
        default: return nil
        }
    }

    private static func notificationType(
        _ name: String
    ) -> UINotificationFeedbackGenerator.FeedbackType? {
        switch name {
        case "notificationSuccess": return .success
        case "notificationWarning": return .warning
        case "notificationError": return .error
        default: return nil
        }
    }

    private func impactGenerator(
        for style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> UIImpactFeedbackGenerator {
        if let existing = impactGenerators[style] { return existing }
        let generator = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator
        return generator
    }
}

/// What the Dart side reads back from `play` and `playSystem`.
struct NativeAnswer {
    let played: Bool
    let reason: String

    static func played() -> NativeAnswer { NativeAnswer(played: true, reason: "") }

    static func failed(_ reason: String) -> NativeAnswer {
        NativeAnswer(played: false, reason: reason)
    }

    var asDictionary: [String: Any] { ["played": played, "reason": reason] }
}
