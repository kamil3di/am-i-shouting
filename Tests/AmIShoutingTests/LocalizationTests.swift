import XCTest
@testable import AmIShouting

final class LocalizationTests: XCTestCase {

    private let english = Strings(.english)
    private let turkish = Strings(.turkish)
    private let allStates: [LoudnessState] = [.quiet, .normal, .loud, .shouting]

    private func freshModel() -> (MeterModel, UserDefaults) {
        let suite = "AmIShoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (MeterModel(defaults: defaults), defaults)
    }

    // MARK: - Language preference

    func testShipsInEnglish() {
        let (model, _) = freshModel()
        XCTAssertEqual(model.language, .english)
        XCTAssertEqual(model.strings.quit, "Quit")
    }

    func testLanguageCanBeSwitchedAtRuntime() {
        let (model, _) = freshModel()
        model.language = .turkish
        XCTAssertEqual(model.strings.quit, "Çık")
        model.language = .english
        XCTAssertEqual(model.strings.quit, "Quit")
    }

    func testChosenLanguageIsRemembered() {
        let (model, defaults) = freshModel()
        model.language = .turkish
        let relaunched = MeterModel(defaults: defaults)
        XCTAssertEqual(relaunched.language, .turkish, "the choice must survive a restart")
    }

    func testAnUnknownStoredLanguageFallsBackToEnglish() {
        let (_, defaults) = freshModel()
        defaults.set("kw", forKey: "language")
        XCTAssertEqual(MeterModel(defaults: defaults).language, .english)
    }

    // MARK: - Calibration state

    func testAFreshInstallIsNotCalibrated() {
        let (model, _) = freshModel()
        XCTAssertFalse(model.isCalibrated, "the prompt has to show on a fresh install")
    }

    func testAStoredReferenceCountsAsCalibrated() {
        let (_, defaults) = freshModel()
        defaults.set(17.0, forKey: "normalExcessDb")
        XCTAssertTrue(MeterModel(defaults: defaults).isCalibrated)
    }

    func testResettingCalibrationBringsThePromptBack() {
        let (_, defaults) = freshModel()
        defaults.set(17.0, forKey: "normalExcessDb")
        let model = MeterModel(defaults: defaults)
        model.resetCalibration()
        XCTAssertFalse(model.isCalibrated, "back to guessed thresholds, so say so again")
        XCTAssertEqual(model.calibrationResult, .reset)
    }

    /// The prompt has to name the button that dismisses it, in either language.
    func testThePromptPointsAtTheButton() {
        for language in Language.allCases {
            let strings = Strings(language)
            XCTAssertTrue(strings.notCalibratedDetail.contains(strings.measureMyVoice),
                          "the prompt does not name the button in \(language.rawValue)")
        }
    }

    // MARK: - Coverage

    func testEveryVerdictHasTextInBothLanguages() {
        for language in Language.allCases {
            let strings = Strings(language)
            for state in allStates {
                XCTAssertFalse(strings.title(for: state).isEmpty,
                               "\(state) has no title in \(language.rawValue)")
                XCTAssertFalse(strings.detail(for: state).isEmpty,
                               "\(state) has no detail in \(language.rawValue)")
            }
        }
    }

    func testVerdictsAreDistinguishableWithinALanguage() {
        for language in Language.allCases {
            let strings = Strings(language)
            let titles = Set(allStates.map { strings.title(for: $0) })
            XCTAssertEqual(titles.count, allStates.count,
                           "two verdicts read the same in \(language.rawValue)")
        }
    }

    func testCalibrationOutcomesAreLocalisedAndDistinct() {
        let outcomes: [CalibrationOutcome] = [.learned(18), .notHeard, .reset]
        for language in Language.allCases {
            let strings = Strings(language)
            let texts = Set(outcomes.map(strings.calibrationOutcome))
            XCTAssertEqual(texts.count, outcomes.count)
        }
        XCTAssertNotEqual(english.calibrationOutcome(.notHeard),
                          turkish.calibrationOutcome(.notHeard))
        XCTAssertTrue(english.calibrationOutcome(.learned(18)).contains("18"))
        XCTAssertTrue(turkish.calibrationOutcome(.learned(18)).contains("18"))
    }

    func testErrorsAreLocalised() {
        XCTAssertNotEqual(english.message(for: .noInputDevice),
                          turkish.message(for: .noInputDevice))
        XCTAssertTrue(english.message(for: .engineFailed("boom")).contains("boom"),
                      "the underlying reason must survive translation")
        XCTAssertTrue(turkish.message(for: .engineFailed("boom")).contains("boom"))
    }

    /// A copy-paste slip would leave English text in the Turkish table. Sample
    /// the phrases that genuinely have to differ.
    func testTurkishIsActuallyTranslated() {
        let pairs: [(String, String)] = [
            (english.paused, turkish.paused),
            (english.noSignal, turkish.noSignal),
            (english.ambientNoise, turkish.ambientNoise),
            (english.yourLevel, turkish.yourLevel),
            (english.aboveAmbient, turkish.aboveAmbient),
            (english.shoutThreshold, turkish.shoutThreshold),
            (english.measureMyVoice, turkish.measureMyVoice),
            (english.calibrationHint, turkish.calibrationHint),
            (english.sensitivity, turkish.sensitivity),
            (english.languageLabel, turkish.languageLabel),
            (english.pause, turkish.pause),
            (english.quit, turkish.quit),
            (english.micDenied, turkish.micDenied),
            (english.notCalibrated, turkish.notCalibrated),
            (english.notCalibratedDetail, turkish.notCalibratedDetail),
            (english.tooltipNotCalibrated, turkish.tooltipNotCalibrated),
            (english.tooltipPaused, turkish.tooltipPaused),
            (english.tooltipWaiting, turkish.tooltipWaiting),
            (english.waitingForCall, turkish.waitingForCall),
            (english.waitingForCallDetail, turkish.waitingForCallDetail),
            (english.whenToListen, turkish.whenToListen),
            (english.hint(for: .duringCalls), turkish.hint(for: .duringCalls)),
        ]
        for (en, tr) in pairs {
            XCTAssertNotEqual(en, tr, "\"\(en)\" was left untranslated")
            XCTAssertFalse(tr.isEmpty)
        }
    }

    func testTooltipCarriesTheMeasurement() {
        for language in Language.allCases {
            let text = Strings(language).tooltip(state: .shouting, excessDb: 37)
            XCTAssertTrue(text.contains("37"))
            XCTAssertTrue(text.contains(Strings(language).title(for: .shouting)))
        }
    }

    func testEachLanguageNamesItself() {
        XCTAssertEqual(Language.english.endonym, "English")
        XCTAssertEqual(Language.turkish.endonym, "Türkçe")
        XCTAssertEqual(Set(Language.allCases.map(\.endonym)).count, Language.allCases.count)
    }
}
