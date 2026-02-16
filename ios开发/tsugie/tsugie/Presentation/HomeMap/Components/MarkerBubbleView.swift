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
                    .fill(activeGlowColor.opacity(isSelected ? 0.34 : 0))
                    .frame(width: 56, height: 56)
                    .blur(radius: isSelected ? 12 : 0)

                Circle()
                    .fill(palette.markerHalo.opacity(isSelected ? 0.34 : 0.14))
                    .frame(width: 40, height: 40)

                Text("へ")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
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
                            opacity: isSelected ? 0.28 : 0.20
                        ),
                        radius: isSelected ? 7 : 4,
                        x: 0,
                        y: 3
                    )
                    .tsugieActiveGlow(
                        isActive: isSelected,
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
            .frame(width: 36, height: 36)
            .overlay(alignment: .trailing) {
                placeNamePill
                    .offset(x: -38)
                    .offset(x: isSelected ? 0 : 26)
                    .scaleEffect(x: isSelected ? 1 : 0.82, y: 1, anchor: .trailing)
                    .opacity(isSelected ? 1 : 0)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
            .overlay(alignment: .topTrailing) {
                if isCluster {
                    clusterCountBadge
                        .offset(x: 11, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Marker.placeActionA11y)
    }

    private var placeNamePill: some View {
        Text(isCluster ? "" : placeName)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(red: 0.17, green: 0.32, blue: 0.40))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white, in: Capsule())
            .shadow(color: Color(red: 0.15, green: 0.38, blue: 0.46, opacity: 0.10), radius: 8, x: 0, y: 4)
            .opacity(isCluster ? 0 : 1)
    }

    private var markerGradient: LinearGradient {
        TsugieVisuals.markerGradient(for: heType)
    }

    private var clusterCountBadge: some View {
        Text("+\(clusterCount)")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(
                Capsule()
                    .fill(Color(red: 0.15, green: 0.34, blue: 0.44))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
            .shadow(
                color: activeGlowColor.opacity(0.22),
                radius: 4,
                x: 0,
                y: 2
            )
    }
}
