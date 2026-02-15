import SwiftUI

struct MarkerBubbleView: View {
    let placeName: String
    let heType: HeType
    let isSelected: Bool
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onTap: () -> Void

    @State private var isPulseAnimating = false
    @State private var isBreathing = false

    var body: some View {
        let palette = TsugieVisuals.palette(for: heType)
        let markerScale = isSelected ? (isBreathing ? 1.12 : 1.06) : 1

        Button(action: onTap) {
            ZStack {
                if isSelected {
                    radarRing(
                        color: activeGlowColor.opacity(0.34),
                        lineWidth: 1.3,
                        maxScale: 1.88,
                        initialOpacity: 0.36,
                        delay: 0
                    )
                    radarRing(
                        color: palette.markerHalo.opacity(0.48),
                        lineWidth: 1.0,
                        maxScale: 1.58,
                        initialOpacity: 0.26,
                        delay: 0.56
                    )
                }

                Circle()
                    .fill(palette.markerHalo.opacity(isSelected ? 0.34 : 0.14))
                    .frame(width: 34, height: 34)

                Text("へ")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        markerGradient,
                            in: Circle()
                    )
                    .opacity(isSelected ? 1 : 0.64)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: Color(red: 0.08, green: 0.28, blue: 0.34, opacity: isSelected ? 0.28 : 0.20), radius: isSelected ? 7 : 4, x: 0, y: 3)
                    .tsugieActiveGlow(
                        isActive: isSelected,
                        glowGradient: activeGradient,
                        glowColor: activeGlowColor,
                        cornerRadius: 12,
                        blurRadius: 8,
                        glowOpacity: 0.74,
                        scale: 1.07,
                        primaryOpacity: 0.80,
                        primaryRadius: 12,
                        primaryYOffset: 3,
                        secondaryOpacity: 0.42,
                        secondaryRadius: 18,
                        secondaryYOffset: 6
                    )
                    .scaleEffect(markerScale, anchor: .bottom)
            }
            .frame(width: 28, height: 28)
            .overlay(alignment: .trailing) {
                placeNamePill
                    .offset(x: -38)
                    .scaleEffect(x: isSelected ? 1 : 0.22, y: 1, anchor: .trailing)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: isSelected ? 0.32 : 0.22), value: isSelected)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Marker.placeActionA11y)
        .onAppear {
            updateMarkerState(isSelected: isSelected)
        }
        .onChange(of: isSelected) { _, _ in
            updateMarkerState(isSelected: isSelected)
        }
    }

    private var placeNamePill: some View {
        Text(placeName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(red: 0.17, green: 0.32, blue: 0.40))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white, in: Capsule())
            .shadow(color: Color(red: 0.15, green: 0.38, blue: 0.46, opacity: 0.10), radius: 8, x: 0, y: 4)
    }

    private var markerGradient: LinearGradient {
        TsugieVisuals.markerGradient(for: heType)
    }

    private func radarRing(
        color: Color,
        lineWidth: CGFloat,
        maxScale: CGFloat,
        initialOpacity: Double,
        delay: Double
    ) -> some View {
        Circle()
            .stroke(color, lineWidth: lineWidth)
            .frame(width: 28, height: 28)
            .scaleEffect(isPulseAnimating ? maxScale : 1)
            .opacity(isPulseAnimating ? 0 : initialOpacity)
            .animation(
                .easeOut(duration: 1.6)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: isPulseAnimating
            )
    }

    private func updateMarkerState(isSelected: Bool) {
        guard isSelected else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isPulseAnimating = false
                isBreathing = false
            }
            return
        }

        isPulseAnimating = false
        isBreathing = false

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            isPulseAnimating = true
        }
    }
}
