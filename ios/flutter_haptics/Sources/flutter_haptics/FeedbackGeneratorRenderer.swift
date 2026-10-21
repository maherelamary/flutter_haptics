import UIKit

/// Fallback for devices that report no Core Haptics support but still have a
/// Taptic Engine — iPhone 7 in practice.
///
/// Only transients survive. UIKit exposes discrete impacts with no way to
/// sustain one, so continuous events are dropped. That is the same trade the
/// Android composition-primitives tier makes.
///
/// iPads have no Taptic Engine at all, so this renderer is silently inert
/// there, which is the correct outcome rather than a bug.
final class FeedbackGeneratorRenderer {
    private var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private var pending: [UUID: DispatchWorkItem] = [:]
    private var registered: [Int: HapticSpec] = [:]
    private var nextRegistrationId = 1

    func prepare() {
        generator(for: .medium).prepare()
    }

    func play(_ spec: HapticSpec) {
        for transient in spec.transients {
            let generator = generator(for: Self.style(forSharpness: transient.sharpness))
            let intensity = CGFloat(transient.intensity)
            generator.prepare()

            if transient.startMs <= 0 {
                generator.impactOccurred(intensity: intensity)
                continue
            }

            let token = UUID()
            let work = DispatchWorkItem { [weak self] in
                generator.impactOccurred(intensity: intensity)
                self?.pending[token] = nil
            }
            pending[token] = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(transient.startMs) / 1000,
                execute: work
            )
        }
    }

    /// Registration here is only bookkeeping — there is no engine to prepare,
    /// so a registered pattern replays through the same impact calls. Handles
    /// still work on this device, they just save nothing.
    func register(_ spec: HapticSpec) -> Int? {
        guard !spec.transients.isEmpty else { return nil }
        let id = nextRegistrationId
        nextRegistrationId += 1
        registered[id] = spec
        return id
    }

    @discardableResult
    func playRegistered(_ id: Int) -> Bool {
        guard let spec = registered[id] else { return false }
        play(spec)
        return true
    }

    func unregister(_ id: Int) {
        registered[id] = nil
    }

    func stop() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }

    /// UIKit splits what Core Haptics calls one event into two knobs: the
    /// style says how sharp the tap feels, the intensity how hard it hits.
    private static func style(
        forSharpness sharpness: Float
    ) -> UIImpactFeedbackGenerator.FeedbackStyle {
        if sharpness >= 0.7 { return .rigid }
        if sharpness <= 0.3 { return .soft }
        return .medium
    }

    private func generator(
        for style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> UIImpactFeedbackGenerator {
        if let existing = generators[style] { return existing }
        let generator = UIImpactFeedbackGenerator(style: style)
        generators[style] = generator
        return generator
    }
}
