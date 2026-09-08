import AVFoundation
import Combine
import Foundation

enum MicPermission {
    case unknown
    case granted
    case denied
}

/// When the app should hold the microphone open.
enum ListeningMode: String, CaseIterable, Identifiable {
    /// Always, so the meter is live the moment you speak.
    case always
    /// Only while another app is capturing audio — in practice, during calls.
    /// Keeps the system recording indicator dark the rest of the day.
    case duringCalls

    var id: String { rawValue }
}

/// Owns the audio tap, the detector and the persisted settings. Everything here
/// runs on the main queue.
final class MeterModel: ObservableObject {

    @Published private(set) var state: LoudnessState = .quiet
    @Published private(set) var reading: Reading = .empty
    @Published private(set) var permission: MicPermission = .unknown
    @Published private(set) var error: AudioMonitorError?
    /// Whether the tap is actually open right now.
    @Published private(set) var isRunning = false
    /// Whether the user switched it off by hand.
    @Published private(set) var isPaused = false
    /// In `duringCalls` mode with nothing else using the microphone.
    @Published private(set) var isWaitingForCall = false
    /// Seconds left in the calibration countdown, 0 when idle.
    @Published private(set) var calibrationRemaining = 0
    @Published private(set) var calibrationResult: CalibrationOutcome?

    /// False until the thresholds have heard the user's own voice at least
    /// once. Until then they are a guess, and the panel says so.
    @Published private(set) var isCalibrated = false

    /// The app ships in English and can be switched at runtime; the choice is
    /// remembered.
    @Published var language: Language = .english {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var listeningMode: ListeningMode = .always {
        didSet {
            guard listeningMode != oldValue else { return }
            defaults.set(listeningMode.rawValue, forKey: Keys.listeningMode)
            applyListeningMode()
        }
    }

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
        static let language = "language"
        static let listeningMode = "listeningMode"
    }

    private let monitor = AudioMonitor()
    private let activity = MicrophoneActivityMonitor()
    private let detector: ShoutDetector
    private let defaults: UserDefaults
    private var calibrationTimer: Timer?
    private var callInProgress = false

    var strings: Strings { Strings(language) }
    var normalExcessDb: Float { detector.config.normalExcessDb }
    var isCalibrating: Bool { calibrationRemaining > 0 }
    /// False on systems that will not say which apps are using the microphone.
    var canDetectCalls: Bool { activity.isSupported }

    /// `defaults` is injectable so tests do not write into the real
    /// preferences of the installed app.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var config = ShoutDetector.Config()
        if let stored = defaults.object(forKey: Keys.normalExcess) as? Double {
            config.normalExcessDb = Float(stored)
            isCalibrated = true
        }
        let storedSensitivity = defaults.object(forKey: Keys.sensitivity) as? Double ?? 0
        config.sensitivityDb = Float(storedSensitivity)
        detector = ShoutDetector(config: config)
        sensitivity = storedSensitivity
        if let stored = defaults.string(forKey: Keys.language),
           let restored = Language(rawValue: stored) {
            language = restored
        }
        if let stored = defaults.string(forKey: Keys.listeningMode),
           let restored = ListeningMode(rawValue: stored) {
            listeningMode = restored
        }

        monitor.onSample = { [weak self] sample in
            guard let self else { return }
            let result = self.detector.process(sample)
            self.reading = result.reading
            if self.state != result.state { self.state = result.state }
        }
        monitor.onError = { [weak self] error in
            self?.error = error
            self?.isRunning = false
        }
        activity.onChange = { [weak self] recording in
            guard let self else { return }
            self.callInProgress = recording
            self.reconcile()
        }
    }

    // MARK: - Lifecycle

    /// The one place that decides whether the tap should be open. Pure, so the
    /// combinations can be checked without a microphone.
    static func shouldListen(
        permission: MicPermission,
        isPaused: Bool,
        mode: ListeningMode,
        callInProgress: Bool
    ) -> Bool {
        guard permission == .granted, !isPaused else { return false }
        switch mode {
        case .always: return true
        case .duringCalls: return callInProgress
        }
    }

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permission = .granted
            applyListeningMode()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permission = granted ? .granted : .denied
                    if granted { self.applyListeningMode() }
                }
            }
        default:
            permission = .denied
        }
    }

    /// The Pause button.
    func toggle() {
        isPaused.toggle()
        reconcile()
    }

    /// Shutdown.
    func stop() {
        cancelCalibration()
        activity.stop()
        monitor.stop()
        isRunning = false
        state = .quiet
        reading = .empty
    }

    private func applyListeningMode() {
        switch listeningMode {
        case .always:
            activity.stop()
            callInProgress = false
        case .duringCalls:
            if activity.isSupported {
                activity.start()
                callInProgress = activity.isOtherProcessRecording
            } else {
                // This system will not say who is using the microphone. Listen
                // rather than go quietly deaf.
                callInProgress = true
            }
        }
        reconcile()
    }

    /// Brings the tap in line with what the settings ask for.
    private func reconcile() {
        let wanted = Self.shouldListen(
            permission: permission,
            isPaused: isPaused,
            mode: listeningMode,
            callInProgress: callInProgress
        )

        if wanted && !isRunning {
            error = nil
            detector.reset()
            monitor.start()
            isRunning = monitor.isRunning
        } else if !wanted && isRunning {
            cancelCalibration()
            monitor.stop()
            isRunning = false
            state = .quiet
            reading = .empty
        }

        isWaitingForCall = permission == .granted
            && !isPaused
            && listeningMode == .duringCalls
            && !callInProgress
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
                self.isCalibrated = true
                self.calibrationResult = .learned(Int(value.rounded()))
            } else {
                self.calibrationResult = .notHeard
            }
        }
    }

    func cancelCalibration() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        calibrationRemaining = 0
        detector.cancelCalibration()
    }

    #if DEBUG
    /// Lets the tests exercise the permission-denied layout without touching
    /// the real microphone authorisation.
    func simulatePermissionDeniedForTesting() {
        permission = .denied
    }
    #endif

    func resetCalibration() {
        detector.config.normalExcessDb = ShoutDetector.Config().normalExcessDb
        defaults.removeObject(forKey: Keys.normalExcess)
        isCalibrated = false
        calibrationResult = .reset
    }
}
