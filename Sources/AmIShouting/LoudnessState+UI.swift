import AppKit
import SwiftUI

extension LoudnessState {
    var nsColor: NSColor {
        switch self {
        case .quiet: return .tertiaryLabelColor
        case .normal: return .systemGreen
        case .loud: return .systemYellow
        case .shouting: return .systemRed
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}
