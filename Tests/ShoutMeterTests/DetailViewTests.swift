import AppKit
import SwiftUI
import XCTest
@testable import ShoutMeter

/// Smoke tests: actually build and lay out the popover, so a broken view body
/// or a bad binding fails here instead of on the first click in the menu bar.
final class DetailViewTests: XCTestCase {

    private func model() -> MeterModel {
        MeterModel(defaults: UserDefaults(suiteName: "ShoutMeterTests.\(UUID().uuidString)")!)
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
