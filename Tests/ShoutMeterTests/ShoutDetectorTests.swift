import XCTest
@testable import ShoutMeter

/// The detector's behaviour is time-dependent (how fast the noise floor may
/// move, how long a verdict must hold), so every test drives it with a virtual
/// clock at a realistic 20 frames per second. No sleeping, no real audio.
final class ShoutDetectorTests: XCTestCase {

    private let frameRate: Double = 20

    private struct Feeder {
        let detector: ShoutDetector
        let frameRate: Double
        var now: CFTimeInterval = 1_000

        /// Steady level, e.g. an empty room.
        @discardableResult
        mutating func room(db: Float, seconds: Double, jitter: Float = 1)
            -> (state: LoudnessState, reading: Reading) {
            var last: (state: LoudnessState, reading: Reading) = (.quiet, .empty)
            for frame in 0..<Int(seconds * frameRate) {
                let wobble = frame % 2 == 0 ? jitter : -jitter
                last = step(db + wobble)
            }
            return last
        }

        /// Speech is not a constant tone: it has gaps between words, and those
        /// gaps are what let the floor tracker see the room. ~0.6 s of voice
        /// followed by ~0.2 s of silence.
        @discardableResult
        mutating func speech(voiceDb: Float, roomDb: Float, seconds: Double)
            -> (state: LoudnessState, reading: Reading) {
            var last: (state: LoudnessState, reading: Reading) = (.quiet, .empty)
            for frame in 0..<Int(seconds * frameRate) {
                last = step((frame % 16) < 12 ? voiceDb : roomDb)
            }
            return last
        }

        /// Room tone with a short loud spike dropped in the middle.
        @discardableResult
        mutating func click(db: Float, frames: Int, roomDb: Float, seconds: Double)
            -> (state: LoudnessState, reading: Reading) {
            let total = Int(seconds * frameRate)
            let spikeStart = total / 2
            var last: (state: LoudnessState, reading: Reading) = (.quiet, .empty)
            for frame in 0..<total {
                let inSpike = frame >= spikeStart && frame < spikeStart + frames
                last = step(inSpike ? db : roomDb)
            }
            return last
        }

        private mutating func step(_ db: Float) -> (state: LoudnessState, reading: Reading) {
            let result = detector.process(LevelSample(time: now, rmsDb: db, peakDb: db))
            now += 1 / frameRate
            return result
        }
    }

    private func feeder(_ config: ShoutDetector.Config = .init()) -> Feeder {
        Feeder(detector: ShoutDetector(config: config), frameRate: frameRate)
    }

    // MARK: - Baseline

    func testSilentRoomStaysQuiet() {
        var f = feeder()
        let result = f.room(db: -55, seconds: 4)
        XCTAssertEqual(result.state, .quiet)
        XCTAssertEqual(result.reading.fill, 0, accuracy: 0.001)
    }

    func testFloorLearnsTheRoomLevel() {
        var f = feeder()
        let result = f.room(db: -47, seconds: 5)
        XCTAssertEqual(result.reading.floorDb, -48, accuracy: 2)
    }

    func testNoVerdictBeforeTheFloorHasSettled() {
        var f = feeder()
        // Loud from the very first frame: with no idea what the room sounds
        // like yet, the meter must not accuse anyone of shouting.
        let result = f.speech(voiceDb: -20, roomDb: -60, seconds: 1)
        XCTAssertEqual(result.state, .quiet)
    }

    /// A muted mic (or a Bluetooth input that has not woken up) sends exact
    /// zeros. Treating that as "a very quiet room" pegged the floor at -100 dB
    /// and made the next ordinary word look like a 40 dB scream.
    func testDigitalSilenceIsNotTreatedAsAQuietRoom() {
        var f = feeder()
        f.room(db: -100, seconds: 5, jitter: 0)              // dead stream
        let result = f.speech(voiceDb: -38, roomDb: -60, seconds: 4)
        XCTAssertEqual(result.state, .normal, "must not open with a false accusation")
    }

    func testDeadStreamIsReportedAsNoSignal() {
        var f = feeder()
        let result = f.room(db: -100, seconds: 3, jitter: 0)
        XCTAssertFalse(result.reading.hasSignal)
        XCTAssertEqual(result.state, .quiet)
        XCTAssertEqual(result.reading.fill, 0, accuracy: 0.001)
    }

    func testRealAudioAfterSilenceHasSignalAgain() {
        var f = feeder()
        f.room(db: -100, seconds: 2, jitter: 0)
        let result = f.room(db: -55, seconds: 3)
        XCTAssertTrue(result.reading.hasSignal)
    }

    /// Even a genuinely near-silent input must not push the floor into a range
    /// no real room occupies.
    func testFloorIsClampedToARealisticMinimum() {
        var f = feeder()
        let result = f.room(db: -85, seconds: 5)
        XCTAssertEqual(result.reading.floorDb, -80, accuracy: 0.01)
    }

    // MARK: - Classification

    func testNormalSpeechReadsAsNormal() {
        var f = feeder()
        f.room(db: -60, seconds: 3)
        let result = f.speech(voiceDb: -38, roomDb: -60, seconds: 4)
        XCTAssertEqual(result.state, .normal, "22 dB over the floor is the default normal voice")
        XCTAssertEqual(result.reading.excessDb, 22, accuracy: 2)
    }

    func testInBetweenLevelReadsAsLoud() {
        var f = feeder()
        f.room(db: -60, seconds: 3)
        let result = f.speech(voiceDb: -32, roomDb: -60, seconds: 4)
        XCTAssertEqual(result.state, .loud, "28 dB over the floor sits between normal and shouting")
    }

    func testShoutingIsDetected() {
        var f = feeder()
        f.room(db: -60, seconds: 3)
        let result = f.speech(voiceDb: -25, roomDb: -60, seconds: 4)
        XCTAssertEqual(result.state, .shouting, "35 dB over the floor is past the shout threshold")
        XCTAssertGreaterThan(result.reading.fill, 0.8)
    }

    /// The whole point of tracking the room: the same absolute level that counts
    /// as shouting in a silent office is an ordinary voice in a loud café.
    func testLoudRoomRaisesTheBar() {
        var f = feeder()
        f.room(db: -47, seconds: 3)
        let result = f.speech(voiceDb: -25, roomDb: -47, seconds: 4)
        XCTAssertEqual(result.state, .normal)
    }

    // MARK: - Floor robustness

    /// If the floor chased the voice, sustained shouting would slowly be
    /// forgiven — the meter would go back to green while you keep yelling.
    func testSustainedShoutingDoesNotBecomeTheNewNormal() {
        var f = feeder()
        f.room(db: -60, seconds: 3)
        let result = f.speech(voiceDb: -25, roomDb: -60, seconds: 20)
        XCTAssertEqual(result.state, .shouting)
        XCTAssertLessThan(result.reading.floorDb, -50, "floor must not follow the voice up")
    }

    /// Carrying the laptop from a silent office into a noisy café has to be
    /// picked up, or every sentence in the café would look like shouting.
    func testFloorFollowsARealChangeInTheRoom() {
        var f = feeder()
        f.room(db: -60, seconds: 5)
        let result = f.room(db: -40, seconds: 30)
        XCTAssertEqual(result.reading.floorDb, -41, accuracy: 3)
    }

    /// A burst shorter than the window must not redefine "ambient" at all.
    func testShortLoudBurstDoesNotMoveTheFloor() {
        var f = feeder()
        f.room(db: -60, seconds: 5)
        let afterBurst = f.room(db: -20, seconds: 2)
        XCTAssertLessThan(afterBurst.reading.floorDb, -55)
    }

    /// Even a long, gapless loud stretch is only allowed to lift the floor at
    /// ~3 dB/s, so the meter cannot be worn down quickly.
    func testFloorRiseIsRateLimited() {
        var f = feeder()
        f.room(db: -60, seconds: 5)
        let midway = f.room(db: -20, seconds: 10)
        XCTAssertLessThan(midway.reading.floorDb, -35, "must not have caught up yet")
        let later = f.room(db: -20, seconds: 20)
        XCTAssertEqual(later.reading.floorDb, -21, accuracy: 3, "but it does get there")
    }

    /// A door slam, a cough into the desk, a keyboard click: loud, but far too
    /// short to be someone shouting.
    func testImpulsiveNoiseIsNotShouting() {
        var f = feeder()
        f.room(db: -60, seconds: 3)
        let result = f.click(db: -15, frames: 2, roomDb: -60, seconds: 2)
        XCTAssertNotEqual(result.state, .shouting)
    }

    // MARK: - Hysteresis

    func testShortBurstDoesNotFlipTheVerdictBackToNormal() {
        var f = feeder()
        f.room(db: -60, seconds: 3)
        f.speech(voiceDb: -25, roomDb: -60, seconds: 3)      // shouting
        // A 0.2 s gap between words must not immediately clear the warning.
        let result = f.room(db: -60, seconds: 0.2, jitter: 0)
        XCTAssertEqual(result.state, .shouting, "calming down is deliberately slow")
    }

    func testVerdictClearsAfterYouActuallyStop() {
        var f = feeder()
        f.room(db: -60, seconds: 3)
        f.speech(voiceDb: -25, roomDb: -60, seconds: 3)
        let result = f.room(db: -60, seconds: 2, jitter: 0)
        XCTAssertEqual(result.state, .quiet)
    }

    // MARK: - Settings

    func testHigherSensitivityTriggersEarlier() {
        var sensitiveConfig = ShoutDetector.Config()
        sensitiveConfig.sensitivityDb = 8
        var sensitive = feeder(sensitiveConfig)
        sensitive.room(db: -60, seconds: 3)
        let sensitiveResult = sensitive.speech(voiceDb: -32, roomDb: -60, seconds: 4)

        var tolerant = feeder()
        tolerant.room(db: -60, seconds: 3)
        let tolerantResult = tolerant.speech(voiceDb: -32, roomDb: -60, seconds: 4)

        XCTAssertEqual(sensitiveResult.state, .shouting)
        XCTAssertEqual(tolerantResult.state, .loud)
    }

    func testCalibrationLearnsTheSpeakingVoice() {
        var f = feeder()
        f.room(db: -60, seconds: 3)

        f.detector.beginCalibration()
        f.speech(voiceDb: -45, roomDb: -60, seconds: 5)      // a quiet talker
        let learned = f.detector.finishCalibration()

        XCTAssertNotNil(learned)
        XCTAssertEqual(learned ?? 0, 15, accuracy: 3)

        // That same quiet voice is now the reference…
        let normal = f.speech(voiceDb: -45, roomDb: -60, seconds: 4)
        XCTAssertEqual(normal.state, .normal)
        // …and a level that used to be an ordinary voice is now shouting.
        let louder = f.speech(voiceDb: -32, roomDb: -60, seconds: 4)
        XCTAssertEqual(louder.state, .shouting)
    }

    func testCalibrationRejectsSilence() {
        var f = feeder()
        f.room(db: -60, seconds: 3)
        f.detector.beginCalibration()
        f.room(db: -60, seconds: 3)
        XCTAssertNil(f.detector.finishCalibration(), "nothing was said, keep the old reference")
    }

    func testCalibrationIsClampedToASaneRange() {
        var f = feeder()
        f.room(db: -90, seconds: 3)
        f.detector.beginCalibration()
        f.speech(voiceDb: 0, roomDb: -90, seconds: 5)        // absurdly loud
        let learned = f.detector.finishCalibration()
        XCTAssertEqual(learned, 55, "clamped instead of making the meter useless")
    }

    // MARK: - UI contract

    func testFillAndThresholdMarkStayInRange() {
        var f = feeder()
        f.room(db: -60, seconds: 2)
        for db in stride(from: Float(-100), through: Float(0), by: 5) {
            let result = f.room(db: db, seconds: 0.5, jitter: 0)
            XCTAssertTrue((0...1).contains(result.reading.fill), "fill out of range at \(db) dB")
            XCTAssertTrue((0...1).contains(result.reading.thresholdMark), "mark out of range at \(db) dB")
        }
    }

    func testResetForgetsEverything() {
        var f = feeder()
        f.room(db: -40, seconds: 5)
        f.detector.reset()
        let result = f.room(db: -40, seconds: 1)
        XCTAssertEqual(result.state, .quiet, "after a device change the floor is relearned")
    }
}
