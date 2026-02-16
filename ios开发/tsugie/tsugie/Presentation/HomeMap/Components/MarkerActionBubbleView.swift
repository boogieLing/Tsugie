import SwiftUI

struct MarkerActionBubbleView: View {
    let isVisible: Bool
    let placeState: PlaceState
    let stamp: PlaceStampPresentation?
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onFavoriteTap: () -> Void
    let onCheckedInTap: () -> Void
    private let menuClockwiseDegrees: Double = 33
    private let menuRadius: CGFloat = 52

    var body: some View {
        ZStack {
            actionButton(
                active: placeState.isFavorite,
                label: L10n.Marker.favoriteA11y,
                action: onFavoriteTap,
                radius: menuRadius,
                angleDegrees: -150
            ) {
                FavoriteStateIconView(isFavorite: placeState.isFavorite, size: 27)
            }

            actionButton(
                active: placeState.isCheckedIn,
                label: L10n.Marker.checkedInA11y,
                action: onCheckedInTap,
                radius: menuRadius,
                angleDegrees: -45
            ) {
                StampIconView(
                    stamp: stamp,
                    isColorized: placeState.isCheckedIn,
                    size: 41
                )
            }
        }
        .frame(width: 1, height: 1)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func actionButton<Icon: View>(
        active: Bool,
        label: String,
        action: @escaping () -> Void,
        radius: CGFloat,
        angleDegrees: Double,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let finalAngle = angleDegrees + menuClockwiseDegrees
        let orbit = polarOffset(radius: isVisible ? radius : 0, angleDegrees: finalAngle)

        return Button(action: action) {
            icon()
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.94))
                )
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
        .opacity(isVisible ? 1 : 0)
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .animation(nil, value: isVisible)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func polarOffset(radius: CGFloat, angleDegrees: Double) -> CGSize {
        let radians = CGFloat(angleDegrees * .pi / 180)
        return CGSize(
            width: cos(radians) * radius,
            height: sin(radians) * radius
        )
    }
}
