import Foundation

/// The user-visible name, kept in one place so the menu bar tooltip, the
/// permission text and the Info.plist cannot drift apart.
enum App {
    static let name = "Am I Shouting?"
}

enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }

    /// Each language names itself, so the picker is readable whichever one is
    /// currently active.
    var endonym: String {
        switch self {
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }

    var shortName: String {
        switch self {
        case .english: return "EN"
        case .turkish: return "TR"
        }
    }
}

/// Every piece of user-facing text, in both languages.
///
/// The app is small enough that a table of literals beats `.strings` files: the
/// compiler catches a missing translation, there are no keys to mistype, and
/// switching language redraws immediately instead of needing a relaunch.
struct Strings {
    let language: Language

    init(_ language: Language) {
        self.language = language
    }

    private func pick(_ english: String, _ turkish: String) -> String {
        switch language {
        case .english: return english
        case .turkish: return turkish
        }
    }

    // MARK: - Verdicts

    func title(for state: LoudnessState) -> String {
        switch state {
        case .quiet: return pick("Quiet", "Sessiz")
        case .normal: return pick("Normal", "Normal")
        case .loud: return pick("Loud", "Yüksek")
        case .shouting: return pick("Shouting", "Bağırıyorsun")
        }
    }

    func detail(for state: LoudnessState) -> String {
        switch state {
        case .quiet:
            return pick("Only the room is audible.",
                        "Sadece ortam sesi duyuluyor.")
        case .normal:
            return pick("You are speaking at your usual level.",
                        "Normal ses tonunda konuşuyorsun.")
        case .loud:
            return pick("Louder than your usual voice.",
                        "Sesin normalden yüksek.")
        case .shouting:
            return pick("You may want to bring it down.",
                        "Sesini biraz alçaltmak isteyebilirsin.")
        }
    }

    // MARK: - Status

    var paused: String { pick("Paused", "Duraklatıldı") }
    var notListening: String { pick("Not listening to the microphone.", "Mikrofon dinlenmiyor.") }
    var noSignal: String { pick("No signal", "Sinyal yok") }
    var noSignalDetail: String {
        pick("The input is completely silent. The microphone may be muted or not ready yet.",
             "Giriş tamamen sessiz. Mikrofon susturulmuş ya da henüz hazır değil.")
    }

    // MARK: - Permission

    var micDenied: String { pick("Microphone access is off.", "Mikrofon erişimi kapalı.") }
    var micDeniedDetail: String {
        pick("Allow \(App.name) under System Settings → Privacy & Security → Microphone, then restart the app.",
             "Sistem Ayarları → Gizlilik ve Güvenlik → Mikrofon bölümünden \"\(App.name)\" uygulamasına izin ver, sonra uygulamayı yeniden başlat.")
    }
    var openPrivacySettings: String { pick("Open privacy settings", "Gizlilik ayarlarını aç") }

    // MARK: - Readings

    var ambientNoise: String { pick("Ambient noise", "Ortam gürültüsü") }
    var yourLevel: String { pick("Your level", "Anlık sesin") }
    var aboveAmbient: String { pick("Above ambient", "Ortamın üstünde") }
    var shoutThreshold: String { pick("Shout threshold", "Bağırma eşiği") }

    // MARK: - Calibration

    var calibration: String { pick("Calibration", "Kalibrasyon") }
    var measureMyVoice: String { pick("Measure my normal voice", "Normal sesimi ölç") }
    func speakNow(_ secondsLeft: Int) -> String {
        pick("Speak… \(secondsLeft)", "Konuş… \(secondsLeft)")
    }
    var reset: String { pick("Reset", "Sıfırla") }
    var calibrationHint: String {
        pick("Speak at your normal level for 5 seconds; the thresholds adjust to it.",
             "5 saniye normal ses tonunda konuş; eşikler buna göre ayarlanır.")
    }
    func normalReference(_ db: Int) -> String {
        pick("normal: +\(db) dB", "normal: +\(db) dB")
    }

    func calibrationOutcome(_ outcome: CalibrationOutcome) -> String {
        switch outcome {
        case .learned(let db):
            return pick("Your normal voice sits \(db) dB above the room.",
                        "Normal sesin ortamın \(db) dB üstünde.")
        case .notHeard:
            return pick("Not enough speech was heard, try again.",
                        "Yeterince konuşma duyulmadı, tekrar dene.")
        case .reset:
            return pick("Back to the default thresholds.",
                        "Varsayılan eşiklere dönüldü.")
        }
    }

    // MARK: - Settings

    var sensitivity: String { pick("Sensitivity", "Hassasiyet") }
    var tolerant: String { pick("tolerant", "toleranslı") }
    var sensitive: String { pick("sensitive", "hassas") }
    var languageLabel: String { pick("Language", "Dil") }
    var pause: String { pick("Pause", "Duraklat") }
    var resume: String { pick("Resume", "Devam et") }
    var quit: String { pick("Quit", "Çık") }

    // MARK: - Menu bar

    var accessibilityLabel: String { pick("\(App.name) level", "\(App.name) ses seviyesi") }
    func tooltip(state: LoudnessState, excessDb: Int) -> String {
        pick("\(title(for: state)) — \(excessDb) dB above ambient",
             "\(title(for: state)) — ortamın \(excessDb) dB üstü")
    }
    var tooltipNoSignal: String { pick("No signal from the microphone", "Mikrofondan sinyal yok") }
    var tooltipPaused: String { pick("\(App.name) is paused", "\(App.name) duraklatıldı") }

    // MARK: - Errors

    func message(for error: AudioMonitorError) -> String {
        switch error {
        case .noInputDevice:
            return pick("No audio input found. Is a microphone connected?",
                        "Ses girişi bulunamadı. Bir mikrofon bağlı mı?")
        case .engineFailed(let reason):
            return pick("Could not start the audio engine: \(reason)",
                        "Ses motoru başlatılamadı: \(reason)")
        }
    }
}

/// The result of a calibration run, kept language-free so the model does not
/// have to know how it will be phrased.
enum CalibrationOutcome: Equatable {
    case learned(Int)
    case notHeard
    case reset
}
