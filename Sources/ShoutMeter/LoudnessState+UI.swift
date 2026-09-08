import AppKit
import SwiftUI

extension LoudnessState {
    var title: String {
        switch self {
        case .quiet: return "Sessiz"
        case .normal: return "Normal"
        case .loud: return "Yüksek"
        case .shouting: return "Bağırıyorsun"
        }
    }

    var detail: String {
        switch self {
        case .quiet: return "Sadece ortam sesi duyuluyor."
        case .normal: return "Normal ses tonunda konuşuyorsun."
        case .loud: return "Sesin normalden yüksek."
        case .shouting: return "Sesini biraz alçaltmak isteyebilirsin."
        }
    }

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
