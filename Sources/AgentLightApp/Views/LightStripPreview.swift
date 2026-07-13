import SwiftUI

enum LightStripEffect {
    case working
    case waiting
    case complete
    case idle
}

enum LightStripStyle {
    static let borderWidth: CGFloat = 0.75
    static let shellOpacity = 0.18
}

struct LightStripSample: Equatable {
    let hue: Double
    let saturation: Double
    let brightness: Double
    let opacity: Double

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
            .opacity(opacity)
    }
}

enum LightStripModel {
    static func idleColorAnchors(time: TimeInterval) -> [LightStripSample] {
        let baseHue = positiveRemainder(time * 0.035, modulus: 1)
        return [
            LightStripSample(hue: baseHue, saturation: 0.88, brightness: 0.98, opacity: 1),
            LightStripSample(
                hue: positiveRemainder(baseHue + 0.11, modulus: 1),
                saturation: 0.88,
                brightness: 0.98,
                opacity: 1
            ),
        ]
    }

    static func samples(
        effect: LightStripEffect,
        time: TimeInterval,
        count: Int
    ) -> [LightStripSample] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let position = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            return sample(effect: effect, time: time, position: position)
        }
    }

    private static func sample(
        effect: LightStripEffect,
        time: TimeInterval,
        position: Double
    ) -> LightStripSample {
        switch effect {
        case .working:
            let phase = positiveRemainder(time * 0.56, modulus: 1)
            let linearDistance = abs(position - phase)
            let circularDistance = min(linearDistance, 1 - linearDistance)
            let wave = exp(-pow(circularDistance / 0.19, 2))
            return LightStripSample(
                hue: 0.58,
                saturation: 0.88,
                brightness: 0.18 + 0.82 * wave,
                opacity: 1
            )
        case .waiting:
            let pulse = 0.5 + 0.5 * sin(time * 6.2)
            return LightStripSample(
                hue: 0.095,
                saturation: 0.9,
                brightness: 0.46 + 0.54 * pulse,
                opacity: 1
            )
        case .complete:
            let breath = 0.5 + 0.5 * sin(time * 3.1)
            return LightStripSample(
                hue: 0.38,
                saturation: 0.82,
                brightness: 0.58 + 0.42 * breath,
                opacity: 1
            )
        case .idle:
            return interpolate(idleColorAnchors(time: time), at: position)
        }
    }

    private static func interpolate(
        _ anchors: [LightStripSample],
        at position: Double
    ) -> LightStripSample {
        guard let first = anchors.first else {
            return LightStripSample(hue: 0, saturation: 0, brightness: 0, opacity: 0)
        }
        guard anchors.count > 1 else { return first }

        let scaledPosition = max(0, min(1, position)) * Double(anchors.count - 1)
        let lowerIndex = min(Int(scaledPosition), anchors.count - 2)
        let amount = scaledPosition - Double(lowerIndex)
        let lower = anchors[lowerIndex]
        let upper = anchors[lowerIndex + 1]
        let hueDelta = positiveRemainder(upper.hue - lower.hue + 0.5, modulus: 1) - 0.5

        return LightStripSample(
            hue: positiveRemainder(lower.hue + hueDelta * amount, modulus: 1),
            saturation: lower.saturation + (upper.saturation - lower.saturation) * amount,
            brightness: lower.brightness + (upper.brightness - lower.brightness) * amount,
            opacity: lower.opacity + (upper.opacity - lower.opacity) * amount
        )
    }

    private static func positiveRemainder(_ value: Double, modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }
}

struct LightStripPreview: View {
    let effect: LightStripEffect
    let time: TimeInterval
    var size = CGSize(width: 10, height: 40)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(LightStripStyle.shellOpacity))

            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(gradient)
                .padding(LightStripStyle.borderWidth)
                .shadow(color: glowColor.opacity(0.42), radius: 2.5)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private var outerCornerRadius: CGFloat {
        min(size.width / 2, 5)
    }

    private var innerCornerRadius: CGFloat {
        max(outerCornerRadius - LightStripStyle.borderWidth, 0)
    }

    private var gradient: LinearGradient {
        let samples = LightStripModel.samples(effect: effect, time: time, count: 24)
        let stops = samples.enumerated().map { index, sample in
            Gradient.Stop(
                color: sample.color,
                location: CGFloat(index) / CGFloat(max(samples.count - 1, 1))
            )
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private var glowColor: Color {
        LightStripModel.samples(effect: effect, time: time, count: 1).first?.color ?? .clear
    }
}
