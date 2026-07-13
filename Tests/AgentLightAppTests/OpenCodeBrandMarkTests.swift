@testable import AgentLightApp
import AgentLightCore
import AppKit
import SwiftUI
import Testing

@Test("OpenCode mark uses the official light and dark appearance colors")
func openCodeBrandMarkUsesAdaptiveOfficialColors() {
    #expect(OpenCodeBrandPalette.light.primaryRGB == 0x211E1E)
    #expect(OpenCodeBrandPalette.light.secondaryRGB == 0xCFCECD)
    #expect(OpenCodeBrandPalette.dark.primaryRGB == 0xF1ECEC)
    #expect(OpenCodeBrandPalette.dark.secondaryRGB == 0x4B4646)
}

@MainActor
@Test("OpenCode mark renders on transparency instead of a white tile")
func openCodeBrandMarkRendersWithoutWhiteTile() throws {
    let renderer = ImageRenderer(
        content: AgentBrandIcon(provider: .openCode, size: 300)
            .environment(\.colorScheme, .light)
    )
    renderer.scale = 1

    let image = try #require(renderer.nsImage)
    let representation = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init))
    let transparentEdge = try #require(representation.colorAt(x: 0, y: 150))
    let primary = try #require(representation.colorAt(x: 150, y: 30))
    let secondary = try #require(representation.colorAt(x: 150, y: 150))

    #expect(transparentEdge.alphaComponent < 0.01)
    #expect(primary.isClose(toRGB: 0x211E1E))
    #expect(secondary.isClose(toRGB: 0xCFCECD))
}

private extension NSColor {
    func isClose(toRGB rgb: UInt32, tolerance: CGFloat = 0.02) -> Bool {
        let expectedRed = CGFloat((rgb >> 16) & 0xFF) / 255
        let expectedGreen = CGFloat((rgb >> 8) & 0xFF) / 255
        let expectedBlue = CGFloat(rgb & 0xFF) / 255
        return abs(redComponent - expectedRed) <= tolerance
            && abs(greenComponent - expectedGreen) <= tolerance
            && abs(blueComponent - expectedBlue) <= tolerance
    }
}
