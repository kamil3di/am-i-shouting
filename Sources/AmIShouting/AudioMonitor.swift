import AVFoundation
import QuartzCore

enum AudioMonitorError: Equatable {
    case noInputDevice
    case engineFailed(String)
}

/// One analysed slice of audio, stamped with its position on the audio
/// timeline (the same time base as `CACurrentMediaTime()`).
struct LevelSample {
    let time: CFTimeInterval
    let rmsDb: Float
    let peakDb: Float
}

/// Taps the default input device and reports RMS / peak level in dBFS.
///
/// CoreAudio hands us fairly large buffers (~100 ms), which would make the
/// meter update only ten times a second. Each buffer is therefore split into
/// short slices so the bar moves smoothly. Callbacks are delivered on the main
/// queue, so the rest of the app can stay single-threaded.
final class AudioMonitor {

    var onSample: ((LevelSample) -> Void)?
    var onError: ((AudioMonitorError) -> Void)?

    /// Length of one reported slice. 40 ms ≈ 25 updates per second.
    private static let sliceSeconds = 0.04

    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private(set) var isRunning = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    func start() {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?(.noInputDevice)
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            guard let self else { return }
            let samples = AudioMonitor.analyse(buffer, when: when)
            guard !samples.isEmpty else { return }
            DispatchQueue.main.async {
                for sample in samples { self.onSample?(sample) }
            }
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            removeTap()
            onError?(.engineFailed(error.localizedDescription))
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        removeTap()
        isRunning = false
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    /// The default device changed (headset plugged in, AirPods connected, …).
    /// The tap format is stale, so rebuild it.
    @objc private func configurationChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.stop()
            self.start()
        }
    }

    private static func analyse(_ buffer: AVAudioPCMBuffer, when: AVAudioTime) -> [LevelSample] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        guard frameCount > 0, channelCount > 0, sampleRate > 0 else { return [] }

        let startTime = when.isHostTimeValid
            ? AVAudioTime.seconds(forHostTime: when.hostTime)
            : CACurrentMediaTime()
        let sliceFrames = max(1, Int(sampleRate * sliceSeconds))

        var samples: [LevelSample] = []
        var offset = 0
        while offset < frameCount {
            let length = min(sliceFrames, frameCount - offset)
            var sumOfSquares: Float = 0
            var peak: Float = 0
            for channel in 0..<channelCount {
                let values = channels[channel]
                for frame in offset..<(offset + length) {
                    let value = values[frame]
                    sumOfSquares += value * value
                    peak = max(peak, abs(value))
                }
            }
            let rms = (sumOfSquares / Float(length * channelCount)).squareRoot()
            samples.append(LevelSample(
                time: startTime + Double(offset) / sampleRate,
                rmsDb: dbfs(rms),
                peakDb: dbfs(peak)
            ))
            offset += length
        }
        return samples
    }

    /// Amplitude (0...1) to dBFS, floored at -100 so silence stays finite.
    private static func dbfs(_ amplitude: Float) -> Float {
        guard amplitude > 0.00001 else { return -100 }
        return max(-100, 20 * log10(amplitude))
    }
}
