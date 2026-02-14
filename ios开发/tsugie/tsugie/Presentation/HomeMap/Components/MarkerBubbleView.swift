import SwiftUI

struct MarkerBubbleView: View {
    let placeName: String
    let heType: HeType
    let isSelected: Bool
    let placeState: PlaceState
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onTap: () -> Void

    var body: some View {
        let palette = TsugieVisuals.palette(for: heType)

        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(palette.markerHalo.opacity(isSelected ? 0.40 : 0.24))
                    .frame(width: 40, height: 40)
                    .offset(x: -8, y: -8)
                    .scaleEffect(isSelected ? 1.10 : 1)
                    .opacity(isSelected ? 1 : 0.72)
                    .animation(isSelected ? .easeOut(duration: 0.24).repeatForever(autoreverses: false) : .default, value: isSelected)

                HStack(spacing: 8) {
                    Text("へ")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            LinearGradient(
                                colors: [palette.markerFrom, palette.markerTo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: Color(red: 0.08, green: 0.28, blue: 0.34, opacity: isSelected ? 0.30 : 0.22), radius: isSelected ? 9 : 6, x: 0, y: 4)
                        .tsugieActiveGlow(
                            isActive: isSelected,
                            glowGradient: activeGradient,
                            glowColor: activeGlowColor,
                            cornerRadius: 14,
                            blurRadius: 9,
                            glowOpacity: 0.78,
                            scale: 1.06,
                            primaryOpacity: 0.82,
                            primaryRadius: 13,
                            primaryYOffset: 4,
                            secondaryOpacity: 0.46,
                            secondaryRadius: 23,
                            secondaryYOffset: 7
                        )

                    Text(placeName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.17, green: 0.32, blue: 0.40))
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.86), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected
                                    ? Color(red: 0.58, green: 0.84, blue: 0.90, opacity: 0.95)
                                    : Color(red: 0.84, green: 0.92, blue: 0.94),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color(red: 0.15, green: 0.38, blue: 0.46, opacity: isSelected ? 0.08 : 0), radius: 8, x: 0, y: 5)
                        .tsugieActiveGlow(
                            isActive: isSelected,
                            glowGradient: activeGradient,
                            glowColor: activeGlowColor,
                            cornerRadius: 16,
                            blurRadius: 10,
                            glowOpacity: 0.62,
                            scale: 1.02,
                            primaryOpacity: 0.74,
                            primaryRadius: 14,
                            primaryYOffset: 4,
                            secondaryOpacity: 0.40,
                            secondaryRadius: 24,
                            secondaryYOffset: 8
                        )
                }

                if placeState.isFavorite || placeState.isCheckedIn {
                    PlaceStateIconsView(
                        placeState: placeState,
                        size: 16,
                        activeGradient: activeGradient,
                        activeGlowColor: activeGlowColor
                    )
                        .offset(x: 20, y: 23)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("地点操作")
    }
}
