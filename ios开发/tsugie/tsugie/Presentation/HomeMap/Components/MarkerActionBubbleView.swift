import SwiftUI

struct MarkerActionBubbleView: View {
    let isVisible: Bool
    let placeState: PlaceState
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onFavoriteTap: () -> Void
    let onCheckedInTap: () -> Void
    private let menuClockwiseDegrees: Double = 33
    private let menuRadius: CGFloat = 52
    private let hiddenScale: CGFloat = 0.36

    var body: some View {
        ZStack {
            actionButton(
                title: placeState.isFavorite ? "★" : "☆",
                active: placeState.isFavorite,
                label: L10n.Marker.favoriteA11y,
                action: onFavoriteTap,
                radius: menuRadius,
                angleDegrees: -150
            )

            actionButton(
                title: placeState.isCheckedIn ? "◉" : "◌",
                active: placeState.isCheckedIn,
                label: L10n.Marker.checkedInA11y,
                action: onCheckedInTap,
                radius: menuRadius,
                angleDegrees: -45
            )
        }
        .frame(width: 1, height: 1)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func actionButton(
        title: String,
        active: Bool,
        label: String,
        action: @escaping () -> Void,
        radius: CGFloat,
        angleDegrees: Double
    ) -> some View {
        let finalAngle = angleDegrees + menuClockwiseDegrees
        let orbit = polarOffset(radius: isVisible ? radius : 0, angleDegrees: finalAngle)

        return Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(active ? AnyShapeStyle(activeGradient) : AnyShapeStyle(Color.white.opacity(0.88)))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(active ? 0 : 0.92), lineWidth: active ? 0 : 1)
                )
                .foregroundStyle(active ? .white : Color(red: 0.37, green: 0.47, blue: 0.52))
                .tsugieActiveGlow(
                    isActive: active,
                    glowGradient: activeGradient,
                    glowColor: activeGlowColor,
                    cornerRadius: 15,
                    blurRadius: 8,
                    glowOpacity: 0.46,
                    scale: 1.04,
                    primaryOpacity: 0.46,
                    primaryRadius: 12,
                    primaryYOffset: 3,
                    secondaryOpacity: 0.22,
                    secondaryRadius: 20,
                    secondaryYOffset: 6
                )
        }
        .offset(orbit)
        .scaleEffect(isVisible ? 1 : hiddenScale)
        .opacity(isVisible ? 1 : 0)
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func polarOffset(radius: CGFloat, angleDegrees: Double) -> CGSize {
        let radians = CGFloat(angleDegrees * .pi / 180)
        return CGSize(
            width: cos(radians) * radius,
            height: sin(radians) * radius
        )
    }
}
