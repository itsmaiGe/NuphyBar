@testable import AgentLightApp
import AgentLightCore
import AppKit
import SwiftUI
import Testing

@Test("every supported Agent has a visible brand mark")
@MainActor
func everySupportedAgentHasAVisibleBrandMark() throws {
    let providers: [AgentProvider] = [
        .codex,
        .claudeCode,
        .openCode,
        .grokBuild,
        .hermes,
        .openClaw,
        .antigravity,
    ]

    for provider in providers {
        let renderer = ImageRenderer(content: AgentBrandIcon(provider: provider, size: 96))
        renderer.scale = 1

        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init))
        let visiblePixels = (0..<bitmap.pixelsHigh).reduce(into: 0) { count, y in
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                count += 1
            }
        }

        #expect(visiblePixels > 80, "\(provider.rawValue) rendered an empty icon")
    }
}

@Test("working light strip is sampled as one continuous gradient")
func workingLightStripUsesContinuousSamples() {
    let samples = LightStripModel.samples(effect: .working, time: 0.75, count: 32)

    #expect(samples.count == 32)
    #expect(Set(samples.map { Int(($0.brightness * 100).rounded()) }).count > 8)

    let largestAdjacentJump = zip(samples, samples.dropFirst())
        .map { abs($0.brightness - $1.brightness) }
        .max() ?? 0
    #expect(largestAdjacentJump < 0.18)
}

@Test("Halo75 previews keep the agreed rich state colors")
func halo75RichStatePreviewColors() throws {
    let tool = try #require(LightStripModel.samples(effect: .toolRunning, time: 0, count: 1).first)
    #expect(tool.hue == 0)
    #expect(tool.brightness == 1)

    let output = try #require(LightStripModel.samples(effect: .outputting, time: 0.5, count: 1).first)
    #expect(output.hue > 0.09 && output.hue < 0.12)

    let permission = try #require(LightStripModel.samples(effect: .permissionRequired, time: 0.5, count: 1).first)
    #expect(permission.hue > 0.58 && permission.hue < 0.63)

    let complete = try #require(LightStripModel.samples(effect: .solidGreen, time: 0, count: 1).first)
    #expect(complete.hue > 0.35 && complete.hue < 0.42)
    #expect(complete.brightness == 1)
}

@Test("Air60 previews preserve amber double pulses and green breathing")
func air60PreviewEffectsRemainDistinct() throws {
    let waiting = [0.01, 0.12, 0.20, 0.40].map {
        LightStripModel.samples(effect: .waiting, time: $0, count: 1)[0]
    }
    #expect(waiting.allSatisfy { $0.hue > 0.08 && $0.hue < 0.12 })
    #expect(waiting.map { $0.brightness > 0 } == [true, false, true, false])
    let complete = [0.0, 0.5, 1.5].map {
        LightStripModel.samples(effect: .complete, time: $0, count: 1)[0]
    }
    #expect(Set(complete.map(\.brightness)).count == 3)
    #expect(complete.allSatisfy { $0.hue > 0.35 && $0.hue < 0.42 })
}

@Test("keyboard settings distinguish every supported keyboard profile")
func keyboardSettingsDistinguishProfiles() {
    #expect(KeyboardLightingProfile(productName: "NuPhy Halo75 V2 NuphyBar") == .halo75USB)
    #expect(KeyboardLightingProfile(productName: "NuPhy Halo75 V2-1") == .halo75Bluetooth)
    #expect(KeyboardLightingProfile(productName: "NuPhy Halo75 V2-3") == .halo75Bluetooth)
    #expect(KeyboardLightingProfile(productName: "NuPhy Air60 V2-1") == .air60Bluetooth)
    #expect(KeyboardLightingProfile(productName: "AULA-F99Pro 5.0 ") == .aulaF99ProBluetooth)
}

@Test("settings navigation matches the compact three-tab reference")
func settingsNavigationUsesThreeCompactTabs() {
    #expect(SettingsSection.allCases.map { $0.title(in: .simplifiedChinese) } == ["Agent", "键盘", "关于"])
    #expect(SettingsSection.allCases.map(\.systemImage) == [
        "point.3.connected.trianglepath.dotted",
        "keyboard",
        "info.circle",
    ])
}

@Test("settings window matches the compact PopClip reference scale")
func settingsWindowMatchesCompactReferenceScale() {
    #expect(SettingsLayout.windowWidth == 440)
    #expect(SettingsLayout.windowHeight == 330)
    #expect(SettingsLayout.tabWidth == 56)
    #expect(SettingsLayout.tabHeight == 48)
    #expect(SettingsLayout.horizontalPadding <= 18)
}

@Test("about content is one compact, aligned settings group")
func aboutContentUsesCompactAlignedLayout() {
    #expect(SettingsLayout.aboutContentWidth == 280)
    #expect(SettingsLayout.aboutRowHeight <= 30)
    #expect(SettingsLayout.aboutSectionSpacing <= 24)
}

@Test("light strip preview uses a hairline shell")
func lightStripPreviewUsesAHairlineShell() {
    #expect(LightStripStyle.borderWidth <= 0.8)
}

@Test("settings typography and rows use compact Mac utility sizing")
func settingsTypographyUsesCompactUtilitySizing() {
    #expect(SettingsLayout.sectionTitleSize <= 11.5)
    #expect(SettingsLayout.primaryTextSize <= 12.5)
    #expect(SettingsLayout.secondaryTextSize <= 9.5)
    #expect(SettingsLayout.actionTextSize >= 11)
    #expect(SettingsLayout.agentRowHeight <= 36)
    #expect(SettingsLayout.lightRowHeight <= 34)
}

@Test("light strip shell stays softer than primary text")
func lightStripShellUsesASubtleSemanticTone() {
    #expect(LightStripStyle.shellOpacity < 0.3)
}

@Test("new Agent integrations use bundled official brand assets")
func newAgentsUseOfficialBrandAssets() {
    #expect(AgentBrandAsset.forProvider(.grokBuild) == .init(name: "GrokBuild", extension: "svg"))
    #expect(AgentBrandAsset.forProvider(.hermes) == .init(name: "Hermes", extension: "png"))
    #expect(AgentBrandAsset.forProvider(.openClaw) == .init(name: "OpenClaw", extension: "png"))
    #expect(AgentBrandAsset.forProvider(.antigravity) == .init(name: "Antigravity", extension: "png"))
}

@Test("idle preview uses at most three neighboring source colors")
func idlePreviewUsesARestrainedPalette() {
    for time in stride(from: 0.0, through: 12.0, by: 0.5) {
        let anchors = LightStripModel.idleColorAnchors(time: time)
        #expect((2...3).contains(anchors.count))

        let hues = anchors.map(\.hue)
        let circularDistances = hues.dropFirst().map { hue in
            let distance = abs(hue - hues[0])
            return min(distance, 1 - distance)
        }
        #expect(circularDistances.allSatisfy { $0 <= 0.18 })
    }
}
