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
        case .green: String(localized: "Green")
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Red")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .gray: String(localized: "Gray")
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
