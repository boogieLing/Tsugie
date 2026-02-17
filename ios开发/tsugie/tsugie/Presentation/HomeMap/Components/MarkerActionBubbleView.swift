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
    private let menuRadius: CGFloat = 44
    private let menuContainerSize: CGFloat = 140

    var body: some View {
        Color.clear
        .frame(width: menuContainerSize, height: menuContainerSize)
        .overlay(alignment: .bottom) {
            ZStack {
            actionButton(
                active: placeState.isFavorite,
                label: L10n.Marker.favoriteA11y,
                action: onFavoriteTap,
                radius: menuRadius,
                angleDegrees: -50,
                buttonSize: 26
            ) {
                FavoriteStateIconView(isFavorite: placeState.isFavorite, size: 22)
            }

                if !placeState.isCheckedIn {
                    actionButton(
                        active: false,
                        label: L10n.Marker.checkedInA11y,
                        action: onCheckedInTap,
                        radius: menuRadius,
                        angleDegrees: -150
                    ) {
                        StampIconView(
                            stamp: stamp,
                            isColorized: false,
                            size: 41
                        )
                    }
                }
            }
            .frame(width: 1, height: 1)
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func actionButton<Icon: View>(
        active _: Bool,
        label: String,
        action: @escaping () -> Void,
        radius: CGFloat,
        angleDegrees: Double,
        buttonSize: CGFloat = 30,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let finalAngle = angleDegrees + menuClockwiseDegrees
        let orbit = polarOffset(radius: isVisible ? radius : 0, angleDegrees: finalAngle)
        let hitDiameter = max(buttonSize + 12, 44)

        return Button(action: action) {
            icon()
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.94))
                )
                .tsugieActiveGlow(
                    isActive: false,
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
        .frame(width: hitDiameter, height: hitDiameter)
        .contentShape(Circle())
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
