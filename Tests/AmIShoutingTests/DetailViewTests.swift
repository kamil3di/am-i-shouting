import AppKit
import SwiftUI
import XCTest
@testable import AmIShouting

/// Smoke tests: actually build and lay out the popover, so a broken view body
/// or a bad binding fails here instead of on the first click in the menu bar.
final class DetailViewTests: XCTestCase {

    private func model() -> MeterModel {
        MeterModel(defaults: UserDefaults(suiteName: "AmIShoutingTests.\(UUID().uuidString)")!)
    }

    private func layout(_ model: MeterModel) -> NSHostingView<DetailView> {
        let view = NSHostingView(rootView: DetailView(model: model))
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 420)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testPopoverLaysOutInBothLanguages() {
        for language in Language.allCases {
            let model = model()
            model.language = language
            let view = layout(model)
            XCTAssertGreaterThan(view.fittingSize.height, 100,
                                 "popover collapsed in \(language.rawValue)")
            XCTAssertGreaterThan(view.fittingSize.width, 100)
        }
    }

    /// The permission-denied branch replaces most of the panel, so it needs its
    /// own pass.
    func testPopoverLaysOutWithoutMicrophoneAccess() {
        let model = model()
        model.simulatePermissionDeniedForTesting()
        for language in Language.allCases {
            model.language = language
            XCTAssertGreaterThan(layout(model).fittingSize.height, 50)
        }
    }

    /// The prompt adds a block to the panel, so it needs its own layout pass.
    func testPopoverLaysOutWithAndWithoutTheCalibrationPrompt() {
        let uncalibrated = model()
        XCTAssertFalse(uncalibrated.isCalibrated)
        let withPrompt = layout(uncalibrated).fittingSize.height

        let defaults = UserDefaults(suiteName: "AmIShoutingTests.\(UUID().uuidString)")!
        defaults.set(17.0, forKey: "normalExcessDb")
        let calibrated = MeterModel(defaults: defaults)
        let withoutPrompt = layout(calibrated).fittingSize.height

        XCTAssertGreaterThan(withPrompt, withoutPrompt,
                             "the prompt should actually take up space when shown")
    }

    func testSwitchingLanguageChangesWhatThePopoverWouldShow() {
        let model = model()
        model.language = .english
        XCTAssertEqual(model.strings.paused, "Paused")
        _ = layout(model)
        model.language = .turkish
        XCTAssertEqual(model.strings.paused, "Duraklatıldı")
        XCTAssertGreaterThan(layout(model).fittingSize.height, 100)
    }
}
