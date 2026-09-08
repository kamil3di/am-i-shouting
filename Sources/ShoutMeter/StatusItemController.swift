import AppKit
import Combine
import SwiftUI

/// The menu bar item: a live level bar that turns yellow, then red.
final class StatusItemController {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: MeterModel
    private var cancellables: Set<AnyCancellable> = []
    private var lastFill: Double = -1
    private var lastMark: Double = -1
    private var lastColor: NSColor = .clear

    init(model: MeterModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: LevelBarImage.size.width + 8)

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("ShoutMeter ses seviyesi")
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 340)
        popover.contentViewController = NSHostingController(rootView: DetailView(model: model))

        // Redraw on every reading, but only when something visibly changed.
        model.$reading
            .combineLatest(model.$state)
            .sink { [weak self] reading, state in
                self?.render(reading: reading, state: state)
            }
            .store(in: &cancellables)

        model.$permission
            .sink { [weak self] permission in
                if permission == .denied { self?.render(reading: .empty, state: .quiet) }
            }
            .store(in: &cancellables)

        render(reading: .empty, state: .quiet)
    }

    private func render(reading: Reading, state: LoudnessState) {
        let live = model.isRunning && reading.hasSignal
        let color = live ? state.nsColor : NSColor.tertiaryLabelColor
        let fill = live ? max(reading.fill, state == .quiet ? 0 : 0.03) : 0
        // Quantise so we are not rebuilding an identical image 20 times a second.
        let quantisedFill = (fill * 60).rounded() / 60
        guard quantisedFill != lastFill || reading.thresholdMark != lastMark || color != lastColor else {
            return
        }
        lastFill = quantisedFill
        lastMark = reading.thresholdMark
        lastColor = color

        statusItem.button?.image = LevelBarImage.make(
            fill: quantisedFill,
            thresholdMark: reading.thresholdMark,
            color: color
        )
        statusItem.button?.toolTip = live
            ? "\(state.title) — ortamın \(Int(reading.excessDb.rounded())) dB üstü"
            : (model.isRunning ? "Mikrofondan sinyal yok" : "ShoutMeter duraklatıldı")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
