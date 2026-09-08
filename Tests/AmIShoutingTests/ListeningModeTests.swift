import XCTest
@testable import AmIShouting

final class ListeningModeTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AmIShoutingTests.\(UUID().uuidString)")!
    }

    // MARK: - The decision itself

    private func shouldListen(
        _ permission: MicPermission = .granted,
        paused: Bool = false,
        mode: ListeningMode = .always,
        call: Bool = false
    ) -> Bool {
        MeterModel.shouldListen(
            permission: permission, isPaused: paused, mode: mode, callInProgress: call
        )
    }

    func testAlwaysListensOncePermitted() {
        XCTAssertTrue(shouldListen(mode: .always))
    }

    func testNothingListensWithoutPermission() {
        for mode in ListeningMode.allCases {
            XCTAssertFalse(shouldListen(.denied, mode: mode, call: true))
            XCTAssertFalse(shouldListen(.unknown, mode: mode, call: true))
        }
    }

    /// Pause is the user's word and outranks every mode.
    func testPauseWinsOverEverything() {
        for mode in ListeningMode.allCases {
            XCTAssertFalse(shouldListen(paused: true, mode: mode, call: true))
        }
    }

    func testDuringCallsWaitsUntilSomethingElseOpensTheMicrophone() {
        XCTAssertFalse(shouldListen(mode: .duringCalls, call: false))
        XCTAssertTrue(shouldListen(mode: .duringCalls, call: true))
    }

    /// In "always" mode a call is irrelevant either way.
    func testACallDoesNotChangeAlwaysMode() {
        XCTAssertEqual(shouldListen(mode: .always, call: false),
                       shouldListen(mode: .always, call: true))
    }

    // MARK: - Preference

    func testDefaultsToListeningAlways() {
        XCTAssertEqual(MeterModel(defaults: freshDefaults()).listeningMode, .always)
    }

    func testTheChosenModeIsRemembered() {
        let defaults = freshDefaults()
        let model = MeterModel(defaults: defaults)
        model.listeningMode = .duringCalls
        XCTAssertEqual(MeterModel(defaults: defaults).listeningMode, .duringCalls)
    }

    func testAnUnknownStoredModeFallsBackToAlways() {
        let defaults = freshDefaults()
        defaults.set("whenever", forKey: "listeningMode")
        XCTAssertEqual(MeterModel(defaults: defaults).listeningMode, .always)
    }

    /// Without permission there is nothing to wait for, so the panel must not
    /// claim to be waiting for a call.
    func testNotWaitingForACallBeforePermissionIsGranted() {
        let model = MeterModel(defaults: freshDefaults())
        model.listeningMode = .duringCalls
        XCTAssertFalse(model.isWaitingForCall)
    }

    // MARK: - What counts as a call

    /// The bug this guards: CoreSpeech (a daemon, not an app) grabs the input
    /// whenever anything else records, and kept the meter awake after the call
    /// had ended.
    func testSystemDaemonsDoNotCountAsCalls() {
        XCTAssertFalse(MicrophoneActivityMonitor.isUserFacingApp(1), "launchd is not a call")
        XCTAssertFalse(MicrophoneActivityMonitor.isUserFacingApp(0))
    }

    func testAProcessWithNoUIDoesNotCountAsACall() {
        // The test runner itself has no Dock presence.
        XCTAssertFalse(
            MicrophoneActivityMonitor.isUserFacingApp(ProcessInfo.processInfo.processIdentifier)
        )
    }

    func testAnUnknownProcessDoesNotCountAsACall() {
        XCTAssertFalse(MicrophoneActivityMonitor.isUserFacingApp(pid_t.max))
    }

    func testEveryModeIsNamedAndExplainedInBothLanguages() {
        for language in Language.allCases {
            let strings = Strings(language)
            for mode in ListeningMode.allCases {
                XCTAssertFalse(strings.name(for: mode).isEmpty)
                XCTAssertFalse(strings.hint(for: mode).isEmpty)
            }
            XCTAssertEqual(Set(ListeningMode.allCases.map(strings.name(for:))).count,
                           ListeningMode.allCases.count,
                           "the two modes read the same in \(language.rawValue)")
        }
    }
}
