import AppKit
import EnvCore
import SwiftUI

extension EnvColor {
    var nsColor: NSColor {
        switch self {
        case .green: .systemGreen
        case .orange: .systemOrange
        case .red: .systemRed
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var title: String {
        switch self {
        case .green: "Yeşil"
        case .orange: "Turuncu"
        case .red: "Kırmızı"
        case .blue: "Mavi"
        case .purple: "Mor"
        case .gray: "Gri"
        }
    }
}

/// A colored dot that keeps its color in the menu bar and in menus (not a template image).
enum DotImage {
    static func make(_ color: NSColor, size: CGFloat = 8) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
