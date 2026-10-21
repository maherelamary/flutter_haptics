import CoreHaptics
import Foundation

/// Plays patterns through Core Haptics, which is the only renderer that
/// reproduces a pattern faithfully: intensity, sharpness and parameter curves
/// all survive.
///
/// Requires an iPhone 8 or later. Everything runs on the main thread — method
/// channel calls arrive there, and the engine's own callbacks are bounced back
/// onto it so the engine state below is only ever touched from one thread.
final class CoreHapticsRenderer {
    private var engine: CHHapticEngine?
    private var engineNeedsStart = true

    /// Players are held here for the length of their playback.
    ///
    /// A `CHHapticPatternPlayer` that falls out of scope can stop mid-pattern,
    /// which showed up as longer patterns being cut short.
    private var activePlayers: [UUID: CHHapticAdvancedPatternPlayer] = [:]

    /// Patterns built once and kept for replay, keyed by the id Dart holds.
    ///
    /// Only the pattern is kept, never a player. A pattern is plain data that
    /// survives an engine reset; a player belongs to one engine and does not.
    /// Holding only the durable half is what makes a registration outlive a
    /// reset without any bookkeeping.
    private var registeredPatterns: [Int: CHHapticPattern] = [:]
    private var nextRegistrationId = 1

    static var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Warms the engine so the first `play` does not pay the start-up cost.
    func prepare() {
        _ = try? startedEngine()
    }

    func play(_ spec: HapticSpec) {
        guard !spec.isEmpty, let pattern = try? buildPattern(spec) else { return }
        start(pattern)
    }

    /// Plays [pattern] on a player of its own.
    ///
    /// A fresh player every time, deliberately. Core Haptics does not define
    /// what `start` does to a player that is already playing, and reusing one
    /// for rapid replays — a picker tick, a drag — produced exactly the
    /// undefined behaviour you would expect: some taps silently dropped.
    /// Building the player is the cheap half anyway; the pattern is the part
    /// worth keeping, and registration keeps it.
    private func start(_ pattern: CHHapticPattern) {
        do {
            let engine = try startedEngine()
            let player = try engine.makeAdvancedPlayer(with: pattern)

            let token = UUID()
            player.completionHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.activePlayers[token] = nil }
            }
            activePlayers[token] = player

            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silent fail, matching the plugin's contract.
        }
    }

    /// Builds [spec] now and keeps it, returning the id Dart replays it by.
    func register(_ spec: HapticSpec) -> Int? {
        guard !spec.isEmpty, let pattern = try? buildPattern(spec) else { return nil }

        let id = nextRegistrationId
        nextRegistrationId += 1
        registeredPatterns[id] = pattern
        return id
    }

    /// Replays a registered pattern. Identical to [play] from here on, so a
    /// handle and a plain play feel the same — only cheaper to get to.
    /// Returns whether the id was known, so a handle whose registration was
    /// lost can fall back to sending the pattern.
    @discardableResult
    func playRegistered(_ id: Int) -> Bool {
        guard let pattern = registeredPatterns[id] else { return false }
        start(pattern)
        return true
    }

    func unregister(_ id: Int) {
        registeredPatterns[id] = nil
    }

    /// Stops playback without tearing the engine down, so the next `play`
    /// does not have to start it again.
    func stop() {
        for player in activePlayers.values {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        activePlayers.removeAll()
    }

    // MARK: - Engine lifecycle

    private func startedEngine() throws -> CHHapticEngine {
        if let engine, !engineNeedsStart { return engine }

        let engine = try self.engine ?? makeEngine()
        if engineNeedsStart {
            try engine.start()
            engineNeedsStart = false
        }
        return engine
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()

        // This plugin never sends audio events, so keep the engine away from
        // the app's audio session entirely.
        engine.playsHapticsOnly = true

        // Let the system park the engine while it is idle and bring it back on
        // demand. This is also what stops backgrounding from leaving it wedged.
        engine.isAutoShutdownEnabled = true

        engine.resetHandler = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                // Players do not survive a reset. Registered patterns do, and
                // the next play builds a player from one as usual.
                self.activePlayers.removeAll()
                self.engineNeedsStart = true
                do {
                    try self.engine?.start()
                    self.engineNeedsStart = false
                } catch {
                    // Leave the flag set so the next play() retries the start.
                }
            }
        }

        engine.stoppedHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.engineNeedsStart = true
                self?.activePlayers.removeAll()
            }
        }

        self.engine = engine
        return engine
    }

    // MARK: - Pattern building

    private func buildPattern(_ spec: HapticSpec) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []

        for event in spec.events {
            switch event {
            case .transient(let transient):
                events.append(makeTransient(transient))
            case .continuous(let continuous):
                let (event, eventCurves) = makeContinuous(continuous)
                events.append(event)
                curves.append(contentsOf: eventCurves)
            }
        }

        return try CHHapticPattern(events: events, parameterCurves: curves)
    }

    private func makeTransient(_ spec: TransientSpec) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: spec.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: spec.sharpness),
            ],
            relativeTime: TimeInterval(spec.startMs) / 1000
        )
    }

    private func makeContinuous(
        _ spec: ContinuousSpec
    ) -> (CHHapticEvent, [CHHapticParameterCurve]) {
        let relativeTime = TimeInterval(spec.startMs) / 1000
        let duration = TimeInterval(spec.durationMs) / 1000

        let intensityCurve = makeCurve(
            spec.intensity,
            parameterID: .hapticIntensityControl,
            relativeTime: relativeTime,
            duration: duration
        )
        let sharpnessCurve = makeCurve(
            spec.sharpness,
            parameterID: .hapticSharpnessControl,
            relativeTime: relativeTime,
            duration: duration
        )

        // Dynamic parameters MODULATE the event parameter rather than replacing
        // it (CHHapticParameter.h): intensity control is a multiplier whose
        // neutral value is 1.0, sharpness control is an offset whose neutral
        // value is 0.0. So where a curve carries the shape, the event parameter
        // has to be neutral or the two compound.
        //
        // Setting it to the curve's first value instead — which is what this
        // did before — squared the intensity and doubled the sharpness, and
        // silenced any curve starting at zero (`HapticParam.pulse`, `spike`)
        // because 0.0 × anything is 0.0.
        //
        // With no curve the event parameter is the only thing carrying the
        // value, so it holds the constant directly.
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(
                    parameterID: .hapticIntensity,
                    value: intensityCurve == nil ? (spec.intensity.first?.value ?? 0.5) : 1
                ),
                CHHapticEventParameter(
                    parameterID: .hapticSharpness,
                    value: sharpnessCurve == nil ? (spec.sharpness.first?.value ?? 0.5) : 0
                ),
            ],
            relativeTime: relativeTime,
            duration: duration
        )

        return (event, [intensityCurve, sharpnessCurve].compactMap { $0 })
    }

    private func makeCurve(
        _ points: [ControlPoint],
        parameterID: CHHapticDynamicParameter.ID,
        relativeTime: TimeInterval,
        duration: TimeInterval
    ) -> CHHapticParameterCurve? {
        guard points.count >= 2 else { return nil }
        // A flat curve is redundant — the event parameter already holds the value.
        if points.allSatisfy({ $0.value == points[0].value }) { return nil }

        let controlPoints = points.map { point in
            // `point.time` is 0...1 across the event. A ControlPoint's
            // relativeTime is measured from the curve's own relativeTime, so it
            // must NOT include relativeTime again — doing so double-offsets
            // delayed continuous events.
            CHHapticParameterCurve.ControlPoint(
                relativeTime: TimeInterval(point.time) * duration,
                value: point.value
            )
        }

        return CHHapticParameterCurve(
            parameterID: parameterID,
            controlPoints: controlPoints,
            relativeTime: relativeTime
        )
    }
}
