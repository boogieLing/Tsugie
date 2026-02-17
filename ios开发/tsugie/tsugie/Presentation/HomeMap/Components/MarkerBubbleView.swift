import SwiftUI

struct MarkerBubbleView: View {
    let placeName: String
    let heType: HeType
    let isSelected: Bool
    let clusterCount: Int
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onTap: () -> Void

    private var isCluster: Bool {
        clusterCount > 1
    }

    var body: some View {
        let palette = TsugieVisuals.palette(for: heType)

        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(activeGlowColor.opacity(0))
                    .frame(width: 48, height: 48)
                    .blur(radius: 0)

                Circle()
                    .fill(palette.markerHalo.opacity(0.14))
                    .frame(width: 32, height: 32)

                Text("へ")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        markerGradient,
                            in: Circle()
                    )
                    .opacity(isSelected ? 1 : 0.64)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(
                        color: Color(
                            red: 0.08,
                            green: 0.28,
                            blue: 0.34,
                            opacity: isSelected ? 0 : 0.20
                        ),
                        radius: isSelected ? 0 : 4,
                        x: 0,
                        y: 3
                    )
                    .tsugieActiveGlow(
                        isActive: false,
                        glowGradient: activeGradient,
                        glowColor: activeGlowColor,
                        cornerRadius: 12,
                        blurRadius: 11,
                        glowOpacity: 0.94,
                        scale: 1.12,
                        primaryOpacity: 0.92,
                        primaryRadius: 16,
                        primaryYOffset: 3,
                        secondaryOpacity: 0.58,
                        secondaryRadius: 24,
                        secondaryYOffset: 6
                    )
            }
            .frame(width: 30, height: 30)
            .overlay(alignment: .bottomLeading) {
                if isCluster {
                    clusterCountBadge
                        .offset(x: -11, y: 9)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Marker.placeActionA11y)
    }

    private var markerGradient: LinearGradient {
        TsugieVisuals.markerGradient(for: heType)
    }

    private var clusterCountBadge: some View {
        Text("+\(clusterCount)")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color(red: 0.23, green: 0.24, blue: 0.26))
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(
                Capsule()
                    .fill(Color.white)
            )
            .overlay(
                Capsule()
                    .stroke(Color(red: 0.82, green: 0.89, blue: 0.93, opacity: 0.9), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.12),
                radius: 3,
                x: 0,
                y: 1
            )
    }
}
