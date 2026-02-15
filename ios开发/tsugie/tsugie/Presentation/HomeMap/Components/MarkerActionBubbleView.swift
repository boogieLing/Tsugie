import SwiftUI

struct MarkerActionBubbleView: View {
    let isVisible: Bool
    let placeState: PlaceState
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onFavoriteTap: () -> Void
    let onQuickTap: () -> Void
    let onCheckedInTap: () -> Void
    private let collapsedBubbleScale: CGFloat = 0.32
    private let menuClockwiseDegrees: CGFloat = 33
    private let menuHorizontalShift: CGFloat = 12

    var body: some View {
        ZStack(alignment: .bottom) {
            actionButton(
                title: placeState.isFavorite ? "★" : "☆",
                active: placeState.isFavorite,
                label: L10n.Marker.favoriteA11y,
                action: onFavoriteTap,
                targetOffset: CGSize(width: -48, height: 10),
                arcDegrees: -205,
                delay: 0.03
            )

            actionButton(
                title: "↗",
                active: false,
                label: L10n.Marker.quickA11y,
                action: onQuickTap,
                targetOffset: CGSize(width: 0, height: -20),
                arcDegrees: -168,
                delay: 0
            )

            actionButton(
                title: placeState.isCheckedIn ? "◉" : "◌",
                active: placeState.isCheckedIn,
                label: L10n.Marker.checkedInA11y,
                action: onCheckedInTap,
                targetOffset: CGSize(width: 48, height: 10),
                arcDegrees: -132,
                delay: 0.06
            )
        }
        .frame(width: 186, height: 108, alignment: .bottom)
        .offset(x: menuHorizontalShift)
    }

    private func actionButton(
        title: String,
        active: Bool,
        label: String,
        action: @escaping () -> Void,
        targetOffset: CGSize,
        arcDegrees: Double,
        delay: Double
    ) -> some View {
        let progress: CGFloat = isVisible ? 1 : 0
        let easedProgress = progress * (2 - progress)
        let rotatedTargetOffset = rotateClockwise(targetOffset, by: menuClockwiseDegrees)
        let animatedOffset = orbitOffset(
            targetOffset: rotatedTargetOffset,
            progress: easedProgress,
            arcDegrees: arcDegrees
        )

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
        .offset(animatedOffset)
        .scaleEffect(collapsedBubbleScale + (1 - collapsedBubbleScale) * easedProgress)
        .rotationEffect(.degrees((1 - Double(easedProgress)) * -18))
        .opacity(Double(easedProgress))
        .animation(
            isVisible
            ? .spring(response: 0.24, dampingFraction: 0.76).delay(delay)
            : .easeOut(duration: 0.15).delay(delay * 0.35),
            value: isVisible
        )
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func orbitOffset(
        targetOffset: CGSize,
        progress: CGFloat,
        arcDegrees: Double
    ) -> CGSize {
        let clampedProgress = min(max(progress, 0), 1)
        let targetRadius = hypot(targetOffset.width, targetOffset.height)
        guard targetRadius > 0.01 else { return .zero }

        let targetAngle = atan2(targetOffset.height, targetOffset.width)
        let arcRadians = CGFloat(arcDegrees * .pi / 180)
        let currentAngle = targetAngle + arcRadians * (1 - clampedProgress)
        let currentRadius = targetRadius * clampedProgress

        return CGSize(
            width: cos(currentAngle) * currentRadius,
            height: sin(currentAngle) * currentRadius
        )
    }

    private func rotateClockwise(_ offset: CGSize, by degrees: CGFloat) -> CGSize {
        let radians = degrees * .pi / 180
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        return CGSize(
            width: offset.width * cosValue - offset.height * sinValue,
            height: offset.width * sinValue + offset.height * cosValue
        )
    }
}
