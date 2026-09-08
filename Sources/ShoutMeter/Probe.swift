import AppKit
import AVFoundation
import Foundation

/// `ShoutMeter --probe [seconds]` prints one line per audio buffer instead of
/// showing the menu bar item. Used to check that the input device, the level
/// maths and the floor tracking behave on a given machine.
enum Probe {

    static func run(seconds: Double) -> Never {
        let detector = ShoutDetector()
        let monitor = AudioMonitor()
        var frames = 0
        var firstSampleTime: CFTimeInterval?

        setbuf(stdout, nil)
        print("listening for \(Int(seconds))s…")
        print("     t   input    floor   voice  excess  state")

        monitor.onSample = { sample in
            let result = detector.process(sample)
            frames += 1
            if firstSampleTime == nil { firstSampleTime = sample.time }
            // ~4 lines per second is enough to read by eye.
            guard frames % 6 == 0 else { return }
            let elapsed = sample.time - (firstSampleTime ?? sample.time)
            print(String(
                format: "%6.1f  %6.1f  %6.1f  %6.1f  %+6.1f  %@",
                elapsed,
                sample.rmsDb,
                result.reading.floorDb,
                result.reading.voiceDb,
                result.reading.excessDb,
                result.state.probeName
            ))
        }
        monitor.onError = { error in
            let message = Strings(.english).message(for: error)
            FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            monitor.start()
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    FileHandle.standardError.write(Data("error: microphone access refused\n".utf8))
                }
                semaphore.signal()
            }
            semaphore.wait()
            monitor.start()
        default:
            FileHandle.standardError.write(Data("error: microphone access has been denied\n".utf8))
            exit(2)
        }

        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        monitor.stop()

        if frames == 0 {
            print("no audio arrived — check the input device or the permission")
            exit(1)
        }
        print("\(frames) slices processed.")
        exit(0)
    }
}

private extension LoudnessState {
    var probeName: String {
        switch self {
        case .quiet: return "quiet"
        case .normal: return "normal"
        case .loud: return "loud"
        case .shouting: return "SHOUTING"
        }
    }
}
