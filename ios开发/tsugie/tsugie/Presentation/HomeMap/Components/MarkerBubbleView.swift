import SwiftUI

struct MarkerBubbleView: View {
    let placeName: String
    let heType: HeType
    let isEnded: Bool
    let isSelected: Bool
    let clusterCount: Int
    let activeGlowColor: Color
    let onTap: () -> Void

    private var isCluster: Bool {
        clusterCount > 1
    }

    var body: some View {
        let palette = TsugieVisuals.palette(for: heType)
        let haloColor = isEnded ? endedMarkerHaloColor : palette.markerHalo
        let showsHighlight = isSelected

        Button(action: onTap) {
            ZStack {
                if isSelected || isCluster {
                    Circle()
                        .fill(haloColor.opacity(isSelected ? 0.20 : 0.12))
                        .frame(width: isSelected ? 36 : 32, height: isSelected ? 36 : 32)
                }

                Text("へ")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        markerGradient,
                            in: Circle()
                    )
                    .opacity(isSelected ? 1 : 0.68)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(
                        color: showsHighlight ? (isEnded ? endedMarkerGlowColor.opacity(0.34) : activeGlowColor.opacity(0.34)) : .clear,
                        radius: showsHighlight ? 8 : 0,
                        x: 0,
                        y: 2
                    )
                    .shadow(color: Color(red: 0.08, green: 0.28, blue: 0.34, opacity: 0.14), radius: 3, x: 0, y: 2)
            }
            .frame(width: 30, height: 30)
            .background(alignment: .bottomTrailing) {
                if isCluster {
                    clusterCountBadge
                        .offset(x: 11, y: 9)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Marker.placeActionA11y)
    }

    private var markerGradient: LinearGradient {
        if isEnded {
            return LinearGradient(
                colors: [endedMarkerFromColor, endedMarkerToColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return TsugieVisuals.markerGradient(for: heType)
    }

    private var endedMarkerFromColor: Color {
        Color(red: 0.58, green: 0.62, blue: 0.67)
    }

    private var endedMarkerToColor: Color {
        Color(red: 0.45, green: 0.49, blue: 0.54)
    }

    private var endedMarkerHaloColor: Color {
        Color(red: 0.74, green: 0.77, blue: 0.82, opacity: 0.24)
    }

    private var endedMarkerGlowColor: Color {
        Color(red: 0.62, green: 0.66, blue: 0.72)
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
