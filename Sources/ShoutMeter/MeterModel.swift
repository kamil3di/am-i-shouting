import AVFoundation
import Combine
import Foundation

enum MicPermission {
    case unknown
    case granted
    case denied
}

/// Owns the audio tap, the detector and the persisted settings. Everything here
/// runs on the main queue.
final class MeterModel: ObservableObject {

    @Published private(set) var state: LoudnessState = .quiet
    @Published private(set) var reading: Reading = .empty
    @Published private(set) var permission: MicPermission = .unknown
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    /// Seconds left in the calibration countdown, 0 when idle.
    @Published private(set) var calibrationRemaining = 0
    @Published private(set) var calibrationResult: String?

    /// -8...8 dB. Higher = flags shouting earlier.
    @Published var sensitivity: Double = 0 {
        didSet {
            detector.config.sensitivityDb = Float(sensitivity)
            defaults.set(sensitivity, forKey: Keys.sensitivity)
        }
    }

    private enum Keys {
        static let sensitivity = "sensitivity"
        static let normalExcess = "normalExcessDb"
    }

    private let monitor = AudioMonitor()
    private let detector: ShoutDetector
    private let defaults = UserDefaults.standard
    private var calibrationTimer: Timer?

    var normalExcessDb: Float { detector.config.normalExcessDb }
    var isCalibrating: Bool { calibrationRemaining > 0 }

    init() {
        var config = ShoutDetector.Config()
        if let stored = defaults.object(forKey: Keys.normalExcess) as? Double {
            config.normalExcessDb = Float(stored)
        }
        let storedSensitivity = defaults.object(forKey: Keys.sensitivity) as? Double ?? 0
        config.sensitivityDb = Float(storedSensitivity)
        detector = ShoutDetector(config: config)
        sensitivity = storedSensitivity

        monitor.onSample = { [weak self] sample in
            guard let self else { return }
            let result = self.detector.process(sample)
            self.reading = result.reading
            if self.state != result.state { self.state = result.state }
        }
        monitor.onError = { [weak self] message in
            self?.errorMessage = message
            self?.isRunning = false
        }
    }

    // MARK: - Lifecycle

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permission = .granted
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permission = granted ? .granted : .denied
                    if granted { self.start() }
                }
            }
        default:
            permission = .denied
        }
    }

    func start() {
        guard permission == .granted, !isRunning else { return }
        errorMessage = nil
        detector.reset()
        monitor.start()
        isRunning = monitor.isRunning
    }

    func stop() {
        cancelCalibration()
        monitor.stop()
        isRunning = false
        state = .quiet
        reading = .empty
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    // MARK: - Calibration

    /// Records the user's normal speaking voice for a few seconds and uses it
    /// as the reference the loud/shout thresholds sit above.
    func startCalibration(seconds: Int = 5) {
        guard isRunning, !isCalibrating else { return }
        calibrationResult = nil
        calibrationRemaining = seconds
        detector.beginCalibration()

        calibrationTimer?.invalidate()
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.calibrationRemaining -= 1
            guard self.calibrationRemaining <= 0 else { return }
            timer.invalidate()
            self.calibrationTimer = nil
            if let value = self.detector.finishCalibration() {
                self.defaults.set(Double(value), forKey: Keys.normalExcess)
                self.calibrationResult = "Normal sesin ortamın \(Int(value.rounded())) dB üstünde."
            } else {
                self.calibrationResult = "Yeterince konuşma duyulmadı, tekrar dene."
            }
        }
    }

    func cancelCalibration() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        calibrationRemaining = 0
        detector.cancelCalibration()
    }

    func resetCalibration() {
        detector.config.normalExcessDb = ShoutDetector.Config().normalExcessDb
        defaults.removeObject(forKey: Keys.normalExcess)
        calibrationResult = "Varsayılan eşiklere dönüldü."
    }
}
