import SwiftUI

struct WaveformView: View {
    let audioLevel: Float
    @State private var animationPhase: CGFloat = 0
    @State private var animationTimer: Timer?

    private let barCount = 40
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: index))
                        .frame(width: barWidth(geometry: geometry), height: barHeight(for: index))
                        .animation(
                            .easeInOut(duration: 0.1)
                                .delay(Double(index) * 0.01),
                            value: audioLevel
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func barWidth(geometry: GeometryProxy) -> CGFloat {
        let totalSpacing = CGFloat(barCount - 1) * 3
        return (geometry.size.width - totalSpacing) / CGFloat(barCount)
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Create wave effect
        let normalizedIndex = CGFloat(index) / CGFloat(barCount)
        let phase = normalizedIndex * .pi * 2 + animationPhase

        // Combine wave pattern with audio level
        let waveIntensity = sin(phase) * 0.5 + 0.5
        let levelIntensity = CGFloat(audioLevel)

        let combinedIntensity = waveIntensity * 0.3 + levelIntensity * 0.7

        return minBarHeight + (maxBarHeight - minBarHeight) * combinedIntensity
    }

    private func barColor(for index: Int) -> Color {
        let normalizedIndex = CGFloat(index) / CGFloat(barCount)
        let intensity = CGFloat(audioLevel)

        // Gradient from accent to recording red based on position and intensity
        if intensity > 0.7 && normalizedIndex > 0.6 {
            return DesignSystem.Colors.recordingRed.opacity(0.8)
        } else if intensity > 0.5 {
            return DesignSystem.Colors.accent
        } else {
            return DesignSystem.Colors.accent.opacity(0.5)
        }
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                animationPhase += 0.1
            }
        }
    }
}

