import Foundation

/// A point on an intensity or sharpness curve.
/// `time` is 0...1 as a fraction of the event's duration.
struct ControlPoint {
    let time: Float
    let value: Float
}

/// A sharp, instantaneous haptic.
struct TransientSpec {
    let startMs: Int
    let intensity: Float
    let sharpness: Float
}

/// A sustained haptic whose parameters may move over time.
struct ContinuousSpec {
    let startMs: Int
    let durationMs: Int
    let intensity: [ControlPoint]
    let sharpness: [ControlPoint]
}

enum HapticEventSpec {
    case transient(TransientSpec)
    case continuous(ContinuousSpec)
}

/// A pattern decoded from the method channel.
///
/// Parsing lives here rather than in the renderers so that the wire format is
/// read in exactly one place, and so each renderer receives typed values it
/// does not have to re-validate.
struct HapticSpec {
    let events: [HapticEventSpec]

    var isEmpty: Bool { events.isEmpty }

    var transients: [TransientSpec] {
        events
            .compactMap { if case .transient(let t) = $0 { return t } else { return nil } }
            .sorted { $0.startMs < $1.startMs }
    }

    var hasContinuous: Bool {
        events.contains { if case .continuous = $0 { return true } else { return false } }
    }

    /// Decodes the `events` list of a `play` call. Malformed entries are
    /// dropped rather than failing the whole pattern.
    static func parse(_ raw: [[String: Any]]) -> HapticSpec {
        HapticSpec(events: raw.compactMap(parseEvent))
    }

    private static func parseEvent(_ dict: [String: Any]) -> HapticEventSpec? {
        guard let type = dict["type"] as? String,
              let delayMs = (dict["delayMs"] as? NSNumber)?.intValue
        else { return nil }

        switch type {
        case "transient":
            guard let intensity = (dict["intensity"] as? NSNumber)?.floatValue,
                  let sharpness = (dict["sharpness"] as? NSNumber)?.floatValue
            else { return nil }
            return .transient(
                TransientSpec(
                    startMs: max(0, delayMs),
                    intensity: intensity.clamped(),
                    sharpness: sharpness.clamped()
                )
            )

        case "continuous":
            guard let durationMs = (dict["durationMs"] as? NSNumber)?.intValue, durationMs > 0,
                  let intensity = parseCurve(dict["intensityCurve"]),
                  let sharpness = parseCurve(dict["sharpnessCurve"])
            else { return nil }
            return .continuous(
                ContinuousSpec(
                    startMs: max(0, delayMs),
                    durationMs: durationMs,
                    intensity: intensity,
                    sharpness: sharpness
                )
            )

        default:
            return nil
        }
    }

    private static func parseCurve(_ raw: Any?) -> [ControlPoint]? {
        guard let list = raw as? [[String: Any]] else { return nil }
        let points = list.compactMap { entry -> ControlPoint? in
            guard let time = (entry["time"] as? NSNumber)?.floatValue,
                  let value = (entry["value"] as? NSNumber)?.floatValue
            else { return nil }
            return ControlPoint(time: time.clamped(), value: value.clamped())
        }
        .sorted { $0.time < $1.time }

        return points.isEmpty ? nil : points
    }
}

extension Float {
    /// Every parameter Core Haptics accepts is normalised to 0...1.
    func clamped() -> Float { Swift.min(1, Swift.max(0, self)) }
}
