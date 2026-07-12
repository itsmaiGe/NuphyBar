import AgentLightCore
import AppKit
import SwiftUI

extension Color {
    init(rgb: AgentLightCore.RGBColor) {
        self.init(
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255
        )
    }

    var rgbColor: AgentLightCore.RGBColor? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return AgentLightCore.RGBColor(
            red: UInt8((color.redComponent * 255).rounded()),
            green: UInt8((color.greenComponent * 255).rounded()),
            blue: UInt8((color.blueComponent * 255).rounded())
        )
    }
}
