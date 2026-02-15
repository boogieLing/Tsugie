import SwiftUI

struct MarkerActionBubbleView: View {
    let placeName: String
    let placeState: PlaceState
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onFavoriteTap: () -> Void
    let onQuickTap: () -> Void
    let onCheckedInTap: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(.clear, lineWidth: 0)
                .frame(width: 108, height: 54)
                .offset(y: -14)

            actionButton(
                title: placeState.isFavorite ? "★" : "☆",
                active: placeState.isFavorite,
                label: L10n.Marker.favoriteA11y,
                action: onFavoriteTap
            )
            .offset(x: -44, y: 4)

            actionButton(
                title: "↗",
                active: false,
                label: L10n.Marker.quickA11y,
                action: onQuickTap
            )
            .offset(y: -16)

            actionButton(
                title: placeState.isCheckedIn ? "◉" : "◌",
                active: placeState.isCheckedIn,
                label: L10n.Marker.checkedInA11y,
                action: onCheckedInTap
            )
            .offset(x: 44, y: 4)

            Text(placeName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.16, green: 0.33, blue: 0.40))
                .lineLimit(1)
                .shadow(color: .white.opacity(0.72), radius: 0, x: 0, y: 1)
                .offset(y: 33)
        }
        .frame(width: 148, height: 88)
    }

    private func actionButton(
        title: String,
        active: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(active ? AnyShapeStyle(activeGradient) : AnyShapeStyle(Color.white.opacity(0.36)))
                )
                .foregroundStyle(active ? .white : Color(red: 0.37, green: 0.47, blue: 0.52))
                .tsugieActiveGlow(
                    isActive: active,
                    glowGradient: activeGradient,
                    glowColor: activeGlowColor,
                    cornerRadius: 15,
                    blurRadius: 8,
                    glowOpacity: 0.72,
                    scale: 1.04,
                    primaryOpacity: 0.78,
                    primaryRadius: 12,
                    primaryYOffset: 3,
                    secondaryOpacity: 0.44,
                    secondaryRadius: 20,
                    secondaryYOffset: 6
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
