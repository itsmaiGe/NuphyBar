import AppKit
import AgentLightCore
import SwiftUI

struct AgentBrandIcon: View {
    let provider: AgentProvider
    var size: CGFloat = 24

    var body: some View {
        Group {
            switch provider {
            case .codex, .claudeCode, .grokBuild, .hermes, .openClaw:
                if let image = brandImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ResourceFallbackMark(provider: provider)
                }
            case .openCode:
                OpenCodeBrandMark()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var brandImage: NSImage? {
        guard let asset = AgentBrandAsset.forProvider(provider),
              let url = Bundle.main.url(forResource: asset.name, withExtension: asset.extension),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = provider == .codex
        return image
    }
}

struct AgentBrandAsset: Equatable {
    let name: String
    let `extension`: String

    static func forProvider(_ provider: AgentProvider) -> AgentBrandAsset? {
        switch provider {
        case .codex: AgentBrandAsset(name: "Codex", extension: "png")
        case .claudeCode: AgentBrandAsset(name: "ClaudeCode", extension: "png")
        case .openCode: nil
        case .grokBuild: AgentBrandAsset(name: "GrokBuild", extension: "svg")
        case .hermes: AgentBrandAsset(name: "Hermes", extension: "png")
        case .openClaw: AgentBrandAsset(name: "OpenClaw", extension: "png")
        }
    }
}

private struct ResourceFallbackMark: View {
    let provider: AgentProvider

    var body: some View {
        switch provider {
        case .codex:
            Image(systemName: "sparkle")
                .font(.system(size: 17, weight: .semibold))
        case .claudeCode:
            Text("A")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.83, green: 0.39, blue: 0.25))
        case .grokBuild, .hermes, .openClaw:
            Image(systemName: "app.dashed")
                .font(.system(size: 17, weight: .regular))
        case .openCode:
            EmptyView()
        }
    }
}

struct OpenCodeBrandPalette: Equatable {
    let primaryRGB: UInt32
    let secondaryRGB: UInt32

    static let light = OpenCodeBrandPalette(primaryRGB: 0x211E1E, secondaryRGB: 0xCFCECD)
    static let dark = OpenCodeBrandPalette(primaryRGB: 0xF1ECEC, secondaryRGB: 0x4B4646)
}

private struct OpenCodeBrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 300
            let xOffset = (size.width - 300 * scale) / 2
            let yOffset = (size.height - 300 * scale) / 2
            let palette = colorScheme == .dark ? OpenCodeBrandPalette.dark : .light

            let primaryRects = [
                CGRect(x: 30, y: 0, width: 240, height: 60),
                CGRect(x: 30, y: 60, width: 60, height: 60),
                CGRect(x: 210, y: 60, width: 60, height: 60),
                CGRect(x: 30, y: 120, width: 240, height: 180),
            ]

            for rect in primaryRects {
                context.fill(
                    Path(scaled(rect, by: scale, xOffset: xOffset, yOffset: yOffset)),
                    with: .color(Color(rgb: palette.primaryRGB))
                )
            }

            let secondaryRect = CGRect(x: 90, y: 120, width: 120, height: 120)
            context.fill(
                Path(scaled(secondaryRect, by: scale, xOffset: xOffset, yOffset: yOffset)),
                with: .color(Color(rgb: palette.secondaryRGB))
            )
        }
    }

    private func scaled(
        _ rect: CGRect,
        by scale: CGFloat,
        xOffset: CGFloat,
        yOffset: CGFloat
    ) -> CGRect {
        CGRect(
            x: xOffset + rect.minX * scale,
            y: yOffset + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
