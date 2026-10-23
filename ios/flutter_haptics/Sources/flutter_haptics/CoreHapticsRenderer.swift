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
    private var registeredPatterns: [Int: [CHHapticPattern]] = [:]

    /// How far ahead a multi-player play is scheduled.
    ///
    /// The players of one pattern share a start time so they stay in step,
    /// and that time has to be far enough ahead that the last one is
    /// scheduled before the first is due. Twenty milliseconds is comfortably
    /// more than it takes to build a handful of players and under what a
    /// finger reads as delay. A single player skips the lead entirely and
    /// starts immediately, so the common case pays nothing for this.
    private static let scheduleLead: TimeInterval = 0.02
    private var nextRegistrationId = 1

    static var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Warms the engine so the first `play` does not pay the start-up cost.
    func prepare() {
        _ = try? startedEngine()
    }

    @discardableResult
    func play(_ spec: HapticSpec) -> Bool {
        guard !spec.isEmpty, let patterns = try? buildPatterns(spec) else { return false }
        return start(patterns)
    }

    /// Plays one pattern's players, all from the same instant.
    ///
    /// A fresh player every time, deliberately. Core Haptics does not define
    /// what `start` does to a player that is already playing, and reusing one
    /// for rapid replays — a picker tick, a drag — produced exactly the
    /// undefined behaviour you would expect: some taps silently dropped.
    /// Building the player is the cheap half anyway; the patterns are the
    /// part worth keeping, and registration keeps them.
    @discardableResult
    private func start(_ patterns: [CHHapticPattern]) -> Bool {
        guard !patterns.isEmpty else { return false }

        do {
            let engine = try startedEngine()
            let startAt = patterns.count == 1
                ? CHHapticTimeImmediate
                : engine.currentTime + Self.scheduleLead

            // Every player is built before any of them is started. Building
            // one can fail, and a failure discovered halfway through would
            // otherwise leave the earlier players already running — half a
            // pattern, which is the thing this is here to prevent.
            var built: [(token: UUID, player: CHHapticAdvancedPatternPlayer)] = []
            for pattern in patterns {
                let player = try engine.makeAdvancedPlayer(with: pattern)
                let token = UUID()
                player.completionHandler = { [weak self] _ in
                    DispatchQueue.main.async { self?.activePlayers[token] = nil }
                }
                built.append((token, player))
            }

            var started: [UUID] = []
            for one in built {
                // Registered before starting, so `stop` can reach a player
                // whichever side of its start time the call arrives on.
                activePlayers[one.token] = one.player
                started.append(one.token)

                do {
                    try one.player.start(atTime: startAt)
                } catch {
                    // The rumble without its tap, or the tap without its
                    // rumble, is not what the caller asked for. Take back
                    // whatever is already running and report the failure.
                    for token in started {
                        try? activePlayers[token]?.stop(atTime: CHHapticTimeImmediate)
                        activePlayers[token] = nil
                    }
                    return false
                }
            }
            return true
        } catch {
            // Nothing was started: the only throwing work above the start
            // loop is building the engine and the players.
            return false
        }
    }

    /// Builds [spec] now and keeps it, returning the id Dart replays it by.
    func register(_ spec: HapticSpec) -> Int? {
        guard !spec.isEmpty, let patterns = try? buildPatterns(spec), !patterns.isEmpty
        else { return nil }

        let id = nextRegistrationId
        nextRegistrationId += 1
        registeredPatterns[id] = patterns
        return id
    }

    /// Replays a registered pattern. Identical to [play] from here on, so a
    /// handle and a plain play feel the same — only cheaper to get to.
    ///
    /// Returns whether it actually played. False covers both an id this
    /// renderer no longer holds and one it holds but could not start; the
    /// plugin asks [hasRegistration] first to tell the caller which, because
    /// a handle should forget a lost registration and keep one that merely
    /// had a bad moment.
    @discardableResult
    func playRegistered(_ id: Int) -> Bool {
        guard let patterns = registeredPatterns[id] else { return false }
        return start(patterns)
    }

    /// Whether this renderer is still holding a pattern for [id].
    func hasRegistration(_ id: Int) -> Bool { registeredPatterns[id] != nil }

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

    /// Splits a spec into patterns that can be played together without
    /// interfering with each other.
    ///
    /// A parameter curve is **not tied to the event it was written for**.
    /// `CHHapticParameter.h` is explicit: dynamic parameters "modify all
    /// haptic or audio events within a pattern" and are "not tied to specific
    /// events". Intensity control is a multiplier, so one pattern holding
    /// every event and every curve meant a rumble's fade reached everything
    /// else in it — a tap during the fade played at a fraction of its
    /// intensity, a tap after a fade-to-zero played not at all, and two
    /// curved rumbles fought over one control.
    ///
    /// So each curved rumble gets a pattern of its own, holding that event
    /// and only its own curves, and everything uncurved shares one. Parameter
    /// state belongs to the player, so a curve can no longer reach past its
    /// own. The events keep their original times and every player starts from
    /// the same instant, which is what holds the pieces together.
    ///
    /// Android has never had this problem: it samples each event's own curve
    /// into one waveform, so nothing leaks in the first place.
    private func buildPatterns(_ spec: HapticSpec) throws -> [CHHapticPattern] {
        var plain: [CHHapticEvent] = []
        var curved: [(event: CHHapticEvent, curves: [CHHapticParameterCurve])] = []

        for event in spec.events {
            switch event {
            case .transient(let transient):
                plain.append(makeTransient(transient))
            case .continuous(let continuous):
                let (event, eventCurves) = makeContinuous(continuous)
                if eventCurves.isEmpty {
                    // Nothing to leak, so it can share the common pattern.
                    plain.append(event)
                } else {
                    curved.append((event, eventCurves))
                }
            }
        }

        var patterns: [CHHapticPattern] = []
        if !plain.isEmpty {
            patterns.append(try CHHapticPattern(events: plain, parameterCurves: []))
        }
        for one in curved {
            patterns.append(
                try CHHapticPattern(events: [one.event], parameterCurves: one.curves)
            )
        }
        return patterns
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
