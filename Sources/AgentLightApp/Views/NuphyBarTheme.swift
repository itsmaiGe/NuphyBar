import AppKit
import SwiftUI

enum NuphyBarTheme {
    static let background = Color(nsColor: .textBackgroundColor)
    static let accent = Color.accentColor
    static let text = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    static var windowBackgroundColor: NSColor {
        .textBackgroundColor
    }
}
