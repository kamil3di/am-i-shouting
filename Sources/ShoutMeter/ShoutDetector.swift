import Foundation
import QuartzCore

enum LoudnessState: Int, Comparable {
    case quiet      // no speech detected, just the room
    case normal     // talking at your usual level
    case loud       // getting louder than usual
    case shouting   // you are shouting

    static func < (lhs: LoudnessState, rhs: LoudnessState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Everything the UI needs for one moment in time. All dB values are dBFS
/// except `excessDb` and the thresholds, which are relative to the room floor.
struct Reading {
    var inputDb: Float = -100
    var floorDb: Float = -100
    var voiceDb: Float = -100
    var excessDb: Float = 0
    var loudThresholdDb: Float = 0
    var shoutThresholdDb: Float = 0
    /// 0...1 bar fill.
    var fill: Double = 0
    /// 0...1 position of the shout threshold on the same bar.
    var thresholdMark: Double = 1
    /// False when the input is delivering silence: muted mic, a Bluetooth
    /// input that has not started yet, or no signal at all.
    var hasSignal: Bool = true

    static let empty = Reading()
}

/// A sliding window of timestamped values, used for percentile estimates.
private struct TimeWindow {
    private var times: [CFTimeInterval] = []
    private var values: [Float] = []
    let span: CFTimeInterval

    init(span: CFTimeInterval) {
        self.span = span
    }

    mutating func append(_ value: Float, at time: CFTimeInterval) {
        times.append(time)
        values.append(value)
        var drop = 0
        while drop < times.count, time - times[drop] > span { drop += 1 }
        if drop > 0 {
            times.removeFirst(drop)
            values.removeFirst(drop)
        }
    }

    var isEmpty: Bool { values.isEmpty }
    var duration: CFTimeInterval { (times.last ?? 0) - (times.first ?? 0) }

    /// `fraction` is 0...1 (0.1 = 10th percentile).
    func percentile(_ fraction: Float) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int((Float(sorted.count - 1) * fraction).rounded())
        return sorted[index]
    }

    mutating func reset() {
        times.removeAll()
        values.removeAll()
    }
}

/// Compares the current voice level against a continuously learned room noise
/// floor. A single microphone cannot separate the room from your voice, so the
/// floor is estimated from the quiet moments between words: a low percentile of
/// a long window. Speaking loudly for a few seconds cannot drag it up, because
/// the floor is only allowed to rise slowly.
final class ShoutDetector {

    struct Config {
        /// How far above the floor a sound has to be before it counts as speech.
        var voiceGateDb: Float = 8
        /// Learned: how far above the floor your normal speaking voice sits.
        var normalExcessDb: Float = 22
        /// Added to `normalExcessDb` for the "getting loud" threshold.
        var loudOffsetDb: Float = 5
        /// Added to `normalExcessDb` for the "shouting" threshold.
        var shoutOffsetDb: Float = 11
        /// Positive = triggers earlier (more sensitive). Range -8...8.
        var sensitivityDb: Float = 0
    }

    var config: Config

    /// Below this the input is not a quiet room, it is a dead stream: a muted
    /// microphone, or a device that has not started delivering audio yet.
    /// Believing it would peg the floor at digital silence and make the next
    /// ordinary sound look like a 40 dB scream.
    private static let deadStreamDb: Float = -90
    /// No real microphone in a real room sits below this, so refuse to
    /// believe a floor lower than it.
    private static let minimumFloorDb: Float = -80

    // 12 s is long enough that the pauses between words dominate the 10th
    // percentile (so your own voice can never become "ambient"), and short
    // enough to follow you into a noisier room within ~20 s.
    private var longWindow = TimeWindow(span: 12)   // room floor
    private var shortWindow = TimeWindow(span: 0.8) // current voice level
    private var floorDb: Float = -60
    private var floorInitialised = false
    private var lastTime: CFTimeInterval?

    private var state: LoudnessState = .quiet
    private var candidate: LoudnessState = .quiet
    private var candidateSince: CFTimeInterval = 0

    /// Escalating is fast so a shout is caught immediately; calming down is
    /// slow so the badge does not flicker between words.
    private let escalateDelay: CFTimeInterval = 0.15
    private let calmDelay: CFTimeInterval = 0.9

    private var calibrationSamples: [Float] = []
    private(set) var isCalibrating = false

    init(config: Config = Config()) {
        self.config = config
    }

    var loudThresholdDb: Float {
        config.normalExcessDb + config.loudOffsetDb - config.sensitivityDb
    }

    var shoutThresholdDb: Float {
        config.normalExcessDb + config.shoutOffsetDb - config.sensitivityDb
    }

    func reset() {
        longWindow.reset()
        shortWindow.reset()
        floorInitialised = false
        lastTime = nil
        state = .quiet
        candidate = .quiet
    }

    func beginCalibration() {
        calibrationSamples.removeAll()
        isCalibrating = true
    }

    /// Returns the learned normal excess, or nil if too little speech was heard.
    func finishCalibration() -> Float? {
        isCalibrating = false
        let speech = calibrationSamples.filter { $0 > config.voiceGateDb }
        guard speech.count >= 8 else { return nil }
        let sorted = speech.sorted()
        let value = sorted[Int((Float(sorted.count - 1) * 0.75).rounded())]
        config.normalExcessDb = min(max(value, 8), 55)
        return config.normalExcessDb
    }

    func cancelCalibration() {
        isCalibrating = false
        calibrationSamples.removeAll()
    }

    /// The verdict is driven by `sample.time` rather than by the wall clock, so
    /// the time-dependent behaviour (floor slew limits, hysteresis, window
    /// spans) stays correct for batched buffers and testable against a virtual
    /// clock.
    func process(_ sample: LevelSample) -> (state: LoudnessState, reading: Reading) {
        let now = sample.time
        let dt = min(max(now - (lastTime ?? now), 0), 1)
        lastTime = now

        // A dead stream teaches the floor nothing, so drop it on the ground
        // rather than letting it define what "ambient" means.
        guard sample.rmsDb > Self.deadStreamDb else {
            state = .quiet
            candidate = .quiet
            var reading = emptyReading(inputDb: sample.rmsDb)
            reading.hasSignal = false
            return (state, reading)
        }

        longWindow.append(sample.rmsDb, at: now)
        shortWindow.append(sample.rmsDb, at: now)

        // 10th percentile of the last 12 s: the room between your words.
        let target = max(longWindow.percentile(0.10) ?? sample.rmsDb, Self.minimumFloorDb)
        if floorInitialised {
            // Rise slowly so a long loud stretch cannot become "ambient";
            // drop quickly, because a room going quiet is real and immediate.
            let maxRise = Float(dt) * 3
            let maxFall = Float(dt) * 20
            floorDb += min(max(target - floorDb, -maxFall), maxRise)
        } else {
            floorDb = target
            floorInitialised = true
        }
        floorDb = max(floorDb, Self.minimumFloorDb)

        // 80th percentile of the last 0.8 s: the loud part of what you just
        // said. Not the peak — a single door slam or keyboard click occupies
        // too few slices to reach the 80th percentile, so it cannot raise the
        // alarm on its own, while real speech easily does.
        let voiceDb = shortWindow.percentile(0.80) ?? sample.rmsDb
        let excess = voiceDb - floorDb

        if isCalibrating { calibrationSamples.append(excess) }

        let raw = classify(excess)
        // Give the floor a moment to settle before trusting the verdict.
        let settled = longWindow.duration > 1.5
        if settled {
            applyHysteresis(raw, at: now)
        } else {
            state = .quiet
            candidate = .quiet
        }

        var reading = emptyReading(inputDb: sample.rmsDb)
        reading.floorDb = floorDb
        reading.voiceDb = voiceDb
        reading.excessDb = excess
        reading.fill = position(of: excess)
        return (state, reading)
    }

    /// A reading with the thresholds filled in but no verdict.
    private func emptyReading(inputDb: Float) -> Reading {
        var reading = Reading()
        reading.inputDb = inputDb
        reading.floorDb = floorInitialised ? floorDb : Self.minimumFloorDb
        reading.voiceDb = reading.floorDb
        reading.excessDb = 0
        reading.loudThresholdDb = loudThresholdDb
        reading.shoutThresholdDb = shoutThresholdDb
        reading.fill = 0
        reading.thresholdMark = position(of: shoutThresholdDb)
        return reading
    }

    /// Maps an excess in dB onto the 0...1 bar, where the shout threshold sits
    /// a little short of the right-hand end.
    private func position(of excessDb: Float) -> Double {
        let gate = config.voiceGateDb
        let span = max(shoutThresholdDb + 8 - gate, 1)
        return Double(min(max((excessDb - gate) / span, 0), 1))
    }

    private func classify(_ excess: Float) -> LoudnessState {
        if excess < config.voiceGateDb { return .quiet }
        if excess < loudThresholdDb { return .normal }
        if excess < shoutThresholdDb { return .loud }
        return .shouting
    }

    private func applyHysteresis(_ raw: LoudnessState, at now: CFTimeInterval) {
        if raw == state {
            candidate = state
            return
        }
        if raw != candidate {
            candidate = raw
            candidateSince = now
            return
        }
        let needed = raw > state ? escalateDelay : calmDelay
        if now - candidateSince >= needed { state = raw }
    }
}
