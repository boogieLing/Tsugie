import SwiftUI
import UIKit

enum TsugieVisuals {
    static let notificationToggleAnimation: Animation = .easeInOut(duration: 0.2)

    struct HePalette {
        let markerFrom: Color
        let markerTo: Color
        let markerHalo: Color
        let nearbyFrom: Color
        let nearbyTo: Color
    }

    static let pillGradient = LinearGradient(
        colors: [
            Color(red: 0.93, green: 0.47, blue: 0.67),
            Color(red: 0.47, green: 0.45, blue: 0.96)
        ],
        startPoint: UnitPoint(x: 0.16, y: 0.03),
        endPoint: UnitPoint(x: 0.86, y: 0.97)
    )

    static func pillGradient(scheme: String, alphaRatio: Double, saturationRatio: Double) -> LinearGradient {
        let base = schemeBaseColors(scheme)
        let points = schemeGradientPoints(scheme)
        return LinearGradient(
            colors: base.map { adjustedColor($0, alphaRatio: alphaRatio, saturationRatio: saturationRatio) },
            startPoint: points.start,
            endPoint: points.end
        )
    }

    static func drawerBackground(scheme: String, alphaRatio: Double, saturationRatio: Double) -> LinearGradient {
        let base = schemeDrawerBackgroundColors(scheme)
        let points = schemeGradientPoints(scheme)
        return LinearGradient(
            colors: base.map { adjustedColor($0, alphaRatio: alphaRatio, saturationRatio: saturationRatio) },
            startPoint: points.start,
            endPoint: points.end
        )
    }

    static func drawerThemeBackground(scheme: String) -> LinearGradient {
        let base = schemeDrawerBackgroundColors(scheme)
        let points = schemeGradientPoints(scheme)
        return LinearGradient(
            colors: base.map { Color(uiColor: $0) },
            startPoint: points.start,
            endPoint: points.end
        )
    }

    static func mapGlowColor(scheme: String, alphaRatio: Double, saturationRatio: Double) -> Color {
        adjustedColor(schemeMapGlowColor(scheme), alphaRatio: alphaRatio, saturationRatio: saturationRatio)
    }

    static func themeAccentColor(scheme: String, saturationRatio: Double) -> Color {
        let base = schemeBaseColors(scheme).first ?? UIColor(red: 0.24, green: 0.20, blue: 0.58, alpha: 1)
        // Keep current-location pin fully opaque while still following theme hue/saturation.
        return adjustedColor(base, alphaRatio: 1, saturationRatio: saturationRatio)
    }

    static func markerGradient(for type: HeType) -> LinearGradient {
        switch type {
        case .hanabi:
            return LinearGradient(
                colors: [
                    Color(red: 254.0 / 255.0, green: 81.0 / 255.0, blue: 150.0 / 255.0),
                    Color(red: 247.0 / 255.0, green: 112.0 / 255.0, blue: 98.0 / 255.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .matsuri:
            return LinearGradient(
                colors: [
                    Color(red: 32.0 / 255.0, green: 156.0 / 255.0, blue: 255.0 / 255.0),
                    Color(red: 104.0 / 255.0, green: 224.0 / 255.0, blue: 207.0 / 255.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [palette(for: type).markerFrom, palette(for: type).markerTo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func markerGlowColor(for type: HeType) -> Color {
        switch type {
        case .hanabi:
            return Color(red: 0.92, green: 0.45, blue: 0.74)
        case .matsuri:
            return Color(red: 0.62, green: 0.79, blue: 1.00)
        default:
            return palette(for: type).markerTo
        }
    }

    static let detailBackground = LinearGradient(
        colors: [
            Color(red: 0.97, green: 1.00, blue: 1.00, opacity: 0.97),
            Color(red: 0.95, green: 1.00, blue: 0.98, opacity: 0.95),
            Color(red: 0.93, green: 0.97, blue: 1.00, opacity: 0.94)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func palette(for type: HeType) -> HePalette {
        switch type {
        case .hanabi:
            return HePalette(
                markerFrom: Color(red: 0.00, green: 0.72, blue: 0.58),
                markerTo: Color(red: 0.33, green: 0.94, blue: 0.77),
                markerHalo: Color(red: 0.33, green: 0.94, blue: 0.77, opacity: 0.24),
                nearbyFrom: Color(red: 0.00, green: 0.72, blue: 0.58),
                nearbyTo: Color(red: 0.33, green: 0.94, blue: 0.77)
            )
        case .matsuri:
            return HePalette(
                markerFrom: Color(red: 1.00, green: 0.56, blue: 0.32),
                markerTo: Color(red: 1.00, green: 0.74, blue: 0.35),
                markerHalo: Color(red: 1.00, green: 0.71, blue: 0.42, opacity: 0.24),
                nearbyFrom: Color(red: 1.00, green: 0.56, blue: 0.32),
                nearbyTo: Color(red: 1.00, green: 0.74, blue: 0.35)
            )
        case .nature:
            return HePalette(
                markerFrom: Color(red: 0.20, green: 0.78, blue: 0.55),
                markerTo: Color(red: 0.45, green: 0.90, blue: 0.66),
                markerHalo: Color(red: 0.45, green: 0.90, blue: 0.66, opacity: 0.24),
                nearbyFrom: Color(red: 0.20, green: 0.78, blue: 0.55),
                nearbyTo: Color(red: 0.45, green: 0.90, blue: 0.66)
            )
        case .other:
            return HePalette(
                markerFrom: Color(red: 0.36, green: 0.64, blue: 1.00),
                markerTo: Color(red: 0.53, green: 0.55, blue: 1.00),
                markerHalo: Color(red: 0.49, green: 0.61, blue: 1.00, opacity: 0.24),
                nearbyFrom: Color(red: 0.36, green: 0.64, blue: 1.00),
                nearbyTo: Color(red: 0.53, green: 0.55, blue: 1.00)
            )
        }
    }

    private static func schemeBaseColors(_ scheme: String) -> [UIColor] {
        switch scheme {
        case "ocean":
            return [
                UIColor(red: 0.88, green: 0.31, blue: 0.68, alpha: 1),
                UIColor(red: 0.98, green: 0.83, blue: 0.14, alpha: 1)
            ]
        case "sunset":
            return [
                UIColor(red: 0.17, green: 0.85, blue: 0.84, alpha: 1),
                UIColor(red: 0.77, green: 0.76, blue: 1.00, alpha: 1),
                UIColor(red: 1.00, green: 0.73, blue: 0.76, alpha: 1)
            ]
        case "sakura":
            return [
                UIColor(red: 0.65, green: 0.75, blue: 1.00, alpha: 1),
                UIColor(red: 0.96, green: 0.50, blue: 0.52, alpha: 1)
            ]
        case "night":
            return [
                UIColor(red: 0.97, green: 0.58, blue: 0.64, alpha: 1),
                UIColor(red: 0.99, green: 0.84, blue: 0.74, alpha: 1)
            ]
        default:
            return [
                UIColor(red: 0.24, green: 0.20, blue: 0.58, alpha: 1),
                UIColor(red: 0.17, green: 0.46, blue: 0.73, alpha: 1),
                UIColor(red: 0.17, green: 0.67, blue: 0.82, alpha: 1),
                UIColor(red: 0.21, green: 0.92, blue: 0.58, alpha: 1)
            ]
        }
    }

    private static func schemeDrawerBackgroundColors(_ scheme: String) -> [UIColor] {
        switch scheme {
        case "ocean":
            return [
                UIColor(red: 0.99, green: 0.92, blue: 0.97, alpha: 0.95),
                UIColor(red: 1.00, green: 0.97, blue: 0.88, alpha: 0.89),
                UIColor(red: 1.00, green: 0.99, blue: 0.95, alpha: 0.86)
            ]
        case "sunset":
            return [
                UIColor(red: 0.90, green: 0.99, blue: 0.99, alpha: 0.95),
                UIColor(red: 0.95, green: 0.94, blue: 1.00, alpha: 0.89),
                UIColor(red: 1.00, green: 0.93, blue: 0.95, alpha: 0.86)
            ]
        case "sakura":
            return [
                UIColor(red: 0.93, green: 0.96, blue: 1.00, alpha: 0.95),
                UIColor(red: 0.98, green: 0.92, blue: 0.94, alpha: 0.89),
                UIColor(red: 1.00, green: 0.95, blue: 0.96, alpha: 0.86)
            ]
        case "night":
            return [
                UIColor(red: 0.91, green: 0.99, blue: 0.97, alpha: 0.95),
                UIColor(red: 0.96, green: 0.93, blue: 1.00, alpha: 0.89),
                UIColor(red: 0.91, green: 0.89, blue: 0.99, alpha: 0.86)
            ]
        default:
            return [
                UIColor(red: 0.98, green: 0.94, blue: 0.97, alpha: 0.95),
                UIColor(red: 0.94, green: 0.94, blue: 1.00, alpha: 0.89),
                UIColor(red: 0.96, green: 0.97, blue: 1.00, alpha: 0.86)
            ]
        }
    }

    private static func schemeMapGlowColor(_ scheme: String) -> UIColor {
        switch scheme {
        case "ocean":
            return UIColor(red: 0.95, green: 0.69, blue: 0.73, alpha: 0.30)
        case "sunset":
            return UIColor(red: 0.78, green: 0.76, blue: 1.00, alpha: 0.30)
        case "sakura":
            return UIColor(red: 0.96, green: 0.68, blue: 0.72, alpha: 0.28)
        case "night":
            return UIColor(red: 0.79, green: 0.70, blue: 0.98, alpha: 0.30)
        default:
            return UIColor(red: 0.71, green: 0.58, blue: 0.95, alpha: 0.26)
        }
    }

    private static func schemeGradientPoints(_ scheme: String) -> (start: UnitPoint, end: UnitPoint) {
        _ = scheme
        // Unify all scheme angles to ~133deg.
        return (UnitPoint(x: 0.16, y: 0.03), UnitPoint(x: 0.86, y: 0.97))
    }

    private static func adjustedColor(_ color: UIColor, alphaRatio: Double, saturationRatio: Double) -> Color {
        let clampedAlpha = max(0.7, min(alphaRatio, 1.3))
        let clampedSat = max(0.7, min(saturationRatio, 1.5))
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            let rgba = color.cgColor.components ?? [1, 1, 1, 1]
            let adjustedAlpha = min(max((rgba.count >= 4 ? rgba[3] : 1) * clampedAlpha, 0), 1)
            return Color(
                red: Double(rgba[0]),
                green: Double(rgba[min(1, rgba.count - 1)]),
                blue: Double(rgba[min(2, rgba.count - 1)]),
                opacity: adjustedAlpha
            )
        }

        let adjustedSaturation = min(max(saturation * clampedSat, 0), 1)
        let adjustedAlpha = min(max(alpha * clampedAlpha, 0), 1)
        return Color(
            hue: Double(hue),
            saturation: Double(adjustedSaturation),
            brightness: Double(brightness),
            opacity: Double(adjustedAlpha)
        )
    }
}

extension View {
    func tsugieActiveGlow(
        isActive: Bool,
        glowGradient: LinearGradient,
        glowColor: Color,
        cornerRadius: CGFloat = 16,
        blurRadius: CGFloat = 12,
        glowOpacity: Double = 0.88,
        scale: CGFloat = 1.03,
        primaryOpacity: Double = 0.90,
        primaryRadius: CGFloat = 24,
        primaryYOffset: CGFloat = 8,
        secondaryOpacity: Double = 0.55,
        secondaryRadius: CGFloat = 42,
        secondaryYOffset: CGFloat = 14
    ) -> some View {
        let softenedOverlayOpacity = min(max(glowOpacity * 0.76, 0), 1)
        let softenedPrimaryOpacity = min(max(primaryOpacity * 0.72, 0), 1)
        let softenedSecondaryOpacity = min(max(secondaryOpacity * 0.66, 0), 1)
        let softenedBlurRadius = blurRadius * 1.16
        let softenedPrimaryRadius = primaryRadius * 1.10
        let softenedSecondaryRadius = secondaryRadius * 1.14

        return self
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(glowGradient)
                        .blur(radius: softenedBlurRadius)
                        .opacity(softenedOverlayOpacity)
                        .scaleEffect(scale)
                }
            }
            .shadow(
                color: isActive ? glowColor.opacity(softenedPrimaryOpacity) : .clear,
                radius: isActive ? softenedPrimaryRadius : 0,
                x: 0,
                y: isActive ? primaryYOffset : 0
            )
            .shadow(
                color: isActive ? glowColor.opacity(softenedSecondaryOpacity) : .clear,
                radius: isActive ? softenedSecondaryRadius : 0,
                x: 0,
                y: isActive ? secondaryYOffset : 0
            )
    }
}

struct PlaceStateIconsView: View {
    let placeState: PlaceState
    let size: CGFloat
    var activeGradient: LinearGradient = TsugieVisuals.pillGradient
    var activeGlowColor: Color = TsugieVisuals.mapGlowColor(scheme: "fresh", alphaRatio: 1.0, saturationRatio: 1.2)
    var activeGlowBoost: Double = 1.7

    var body: some View {
        HStack(spacing: 5) {
            stateIcon(text: placeState.isFavorite ? "★" : "☆", isOn: placeState.isFavorite, label: L10n.PlaceState.favoriteA11y)
            stateIcon(text: placeState.isCheckedIn ? "◉" : "◌", isOn: placeState.isCheckedIn, label: L10n.PlaceState.checkedInA11y)
        }
    }

    private func stateIcon(text: String, isOn: Bool, label: String) -> some View {
        let glowBoost = min(max(activeGlowBoost, 1), 3.6)

        return Text(text)
            .font(.system(size: size * 0.58, weight: .bold))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isOn ? AnyShapeStyle(activeGradient) : AnyShapeStyle(Color.white.opacity(0.84)))
            )
            .overlay(
                Circle()
                    .stroke(isOn ? .clear : Color(red: 0.84, green: 0.91, blue: 0.93, opacity: 0.92), lineWidth: 1)
            )
            .foregroundStyle(isOn ? .white : Color(red: 0.43, green: 0.53, blue: 0.57))
            .shadow(
                color: Color(red: 0.17, green: 0.35, blue: 0.42, opacity: isOn ? 0 : 0.14),
                radius: isOn ? 0 : 5,
                x: 0,
                y: 3
            )
            .tsugieActiveGlow(
                isActive: isOn,
                glowGradient: activeGradient,
                glowColor: activeGlowColor,
                cornerRadius: size / 2,
                blurRadius: 9 + glowBoost * 2.3,
                glowOpacity: min(0.84, 0.46 + glowBoost * 0.08),
                scale: 1.02,
                primaryOpacity: min(0.82, 0.42 + glowBoost * 0.09),
                primaryRadius: 11 + glowBoost * 3.2,
                primaryYOffset: 3,
                secondaryOpacity: min(0.58, 0.26 + glowBoost * 0.07),
                secondaryRadius: 18 + glowBoost * 4.8,
                secondaryYOffset: 6
            )
            .shadow(
                color: isOn ? activeGlowColor.opacity(min(0.62, 0.36 + glowBoost * 0.08)) : .clear,
                radius: isOn ? 9 + glowBoost * 2.2 : 0,
                x: 0,
                y: isOn ? 3 : 0
            )
            .shadow(
                color: isOn ? activeGlowColor.opacity(min(0.36, 0.20 + glowBoost * 0.05)) : .clear,
                radius: isOn ? 16 + glowBoost * 3.2 : 0,
                x: 0,
                y: isOn ? 7 : 0
            )
            .accessibilityLabel(label)
    }
}

struct TsugieClosePillButton: View {
    let action: () -> Void
    var accessibilityLabel: String = L10n.Common.close

    var body: some View {
        Button(action: action) {
            Text("×")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 24)
                .background(Color.white.opacity(0.86), in: Capsule())
                .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TsugieStatusTrackView: View {
    enum Variant {
        case quick
        case detail
    }

    let snapshot: EventStatusSnapshot
    let variant: Variant
    let progress: Double
    var endpointIconName: String? = nil
    var endpointIconIsColorized: Bool = true

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        GeometryReader { proxy in
            let width = proxy.size.width
            let fillWidth = max(width * clamped, 0)
            let x = edgeAdjustedX(for: width, progress: endpointProgressValue)
            let centerY = proxy.size.height / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(fillGradient)
                    .frame(width: max(fillWidth, 6), height: trackHeight)
                    .overlay(
                        Capsule().stroke(fillBorder, lineWidth: variant == .quick ? 1 : 0)
                    )
                    .shadow(color: fillShadowColor, radius: fillShadowRadius, x: 0, y: 0)

                endpointBubbleContent
                    .frame(minWidth: endpointBubbleMinWidth, minHeight: endpointBubbleMinHeight)
                    .padding(.horizontal, endpointBubbleHorizontalPadding)
                    .background(endpointBackground, in: Capsule())
                    .overlay(Capsule().stroke(endpointBorder, lineWidth: 1))
                    .position(x: x, y: centerY)
            }
        }
        .frame(height: variant == .quick ? 10 : 25)
    }

    private func edgeAdjustedX(for width: CGFloat, progress: Double) -> CGFloat {
        guard width > 0 else { return 0 }
        let px = width * progress
        let half = endpointBubbleHalfWidth
        guard width > (half * 2) else { return width / 2 }
        let minX = half
        let maxX = width - half
        return min(max(px, minX), maxX)
    }

    private var trackHeight: CGFloat {
        variant == .quick ? 10 : 13
    }

    private var endpointProgressValue: Double {
        switch snapshot.status {
        case .upcoming, .unknown:
            return 0
        case .ended:
            return 1
        case .ongoing:
            return min(max(progress, 0), 1)
        }
    }

    private var endpointBubbleMinWidth: CGFloat { 27 }
    private var endpointBubbleMinHeight: CGFloat { 24 }
    private var endpointBubbleHorizontalPadding: CGFloat { 9 }
    private var endpointBubbleHalfWidth: CGFloat {
        (endpointBubbleMinWidth + endpointBubbleHorizontalPadding * 2) / 2
    }

    private var trackColor: Color {
        switch snapshot.status {
        case .ongoing:
            return Color(red: 0.85, green: 0.90, blue: 0.92, opacity: 0.34)
        case .upcoming, .ended, .unknown:
            return Color(red: 0.84, green: 0.89, blue: 0.91, opacity: 0.32)
        }
    }

    private var fillGradient: LinearGradient {
        switch snapshot.status {
        case .ongoing:
            return LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.95, blue: 0.82),
                    Color(red: 0.20, green: 0.82, blue: 1.00),
                    Color(red: 0.55, green: 0.55, blue: 1.00),
                    Color(red: 1.00, green: 0.40, blue: 0.77)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .upcoming:
            return LinearGradient(
                colors: [
                    Color(red: 0.49, green: 0.64, blue: 0.70, opacity: 0.52),
                    Color(red: 0.63, green: 0.75, blue: 0.80, opacity: 0.30)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .ended:
            return LinearGradient(
                colors: [
                    Color(red: 0.51, green: 0.64, blue: 0.70, opacity: 0.60),
                    Color(red: 0.63, green: 0.74, blue: 0.79, opacity: 0.42)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .unknown:
            return LinearGradient(
                colors: [
                    Color(red: 0.56, green: 0.66, blue: 0.71, opacity: 0.45),
                    Color(red: 0.67, green: 0.75, blue: 0.80, opacity: 0.28)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var fillBorder: Color {
        Color(red: 0.94, green: 0.97, blue: 0.99, opacity: 0.94)
    }

    private var fillShadowColor: Color {
        guard variant == .detail else { return .clear }
        return snapshot.status == .ongoing ? Color(red: 0.28, green: 0.89, blue: 0.88, opacity: 0.42) : .clear
    }

    private var fillShadowRadius: CGFloat {
        guard variant == .detail else { return 0 }
        return snapshot.status == .ongoing ? 8 : 0
    }

    private var endpointBackground: Color {
        snapshot.status == .upcoming || snapshot.status == .ended || snapshot.status == .unknown
        ? Color(red: 0.98, green: 0.99, blue: 1.00)
        : .white
    }

    private var endpointBorder: Color {
        snapshot.status == .ongoing ? Color.white.opacity(0.96) : Color(red: 0.93, green: 0.96, blue: 0.98)
    }

    private var endpointTextColor: Color {
        switch snapshot.status {
        case .ongoing:
            return Color(red: 0.20, green: 0.82, blue: 1.00)
        case .upcoming, .ended, .unknown:
            return Color(red: 0.34, green: 0.44, blue: 0.49, opacity: 0.88)
        }
    }

    @ViewBuilder
    private var endpointBubbleContent: some View {
        if let endpointIconName {
            let isHanabiEndpoint = endpointIconName == TsugieSmallIcon.hanabiAsset
            let endpointScale: CGFloat = (1.65 * 1.3) * (isHanabiEndpoint ? 0.8 : 1.0)
            if endpointIconIsColorized {
                if isHanabiEndpoint {
                    Image(endpointIconName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .scaleEffect(endpointScale)
                        .rotationEffect(.degrees(23))
                        .foregroundStyle(hanabiEndpointGradient)
                } else {
                    Image(endpointIconName)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .scaleEffect(endpointScale)
                        .saturation(1.18)
                        .contrast(1.05)
                }
            } else {
                Image(endpointIconName)
                    .resizable()
                    .renderingMode(isHanabiEndpoint ? .template : .original)
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .scaleEffect(endpointScale)
                    .rotationEffect(.degrees(isHanabiEndpoint ? 23 : 0))
                    .saturation(0)
                    .contrast(0.95)
                    .foregroundStyle(Color(red: 0.54, green: 0.61, blue: 0.67))
            }
        } else {
            Text("へ")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(endpointTextColor)
        }
    }

    private var hanabiEndpointGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 250.0 / 255.0, green: 112.0 / 255.0, blue: 154.0 / 255.0),
                Color(red: 254.0 / 255.0, green: 225.0 / 255.0, blue: 64.0 / 255.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct TsugieMiniProgressView: View {
    let snapshot: EventStatusSnapshot
    var trackHeight: CGFloat = 10
    var glowBoost: CGFloat = 1
    var endpointIconName: String? = nil
    var endpointIconIsColorized: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let pct = min(max(progressValue, 0), 1)
            let fillWidth = max(width * pct, 6)
            let endpointX = edgeAdjustedX(for: width, progress: endpointProgressValue)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.84, green: 0.89, blue: 0.91, opacity: 0.34))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(fillGradient)
                    .frame(width: fillWidth, height: trackHeight)
                    .shadow(color: fillGlowColor, radius: fillGlowRadius, x: 0, y: 0)

                endpointBubbleContent
                    .frame(minWidth: endpointBubbleMinWidth, minHeight: endpointBubbleMinHeight)
                    .padding(.horizontal, endpointBubbleHorizontalPadding)
                    .background(endpointBackground, in: Capsule())
                    .overlay(Capsule().stroke(endpointBorder, lineWidth: 1))
                    .shadow(color: endpointGlowColor, radius: endpointGlowRadius, x: 0, y: 0)
                    .position(x: endpointX, y: trackHeight / 2)
            }
        }
        .frame(height: trackHeight)
    }

    private var progressValue: Double {
        switch snapshot.status {
        case .ongoing:
            return snapshot.progress ?? 0
        case .upcoming:
            return snapshot.waitProgress ?? 0.08
        case .ended:
            return 1
        case .unknown:
            return 0.08
        }
    }

    private var endpointProgressValue: Double {
        switch snapshot.status {
        case .upcoming, .unknown:
            return 0
        case .ended:
            return 1
        case .ongoing:
            return progressValue
        }
    }

    private var endpointBubbleMinWidth: CGFloat { 26 }
    private var endpointBubbleMinHeight: CGFloat { 23 }
    private var endpointBubbleHorizontalPadding: CGFloat { 8 }
    private var endpointBubbleHalfWidth: CGFloat {
        (endpointBubbleMinWidth + endpointBubbleHorizontalPadding * 2) / 2
    }

    private func edgeAdjustedX(for width: CGFloat, progress: Double) -> CGFloat {
        guard width > 0 else { return 0 }
        let px = width * progress
        let half = endpointBubbleHalfWidth
        guard width > (half * 2) else { return width / 2 }
        let minX = half
        let maxX = width - half
        return min(max(px, minX), maxX)
    }

    private var fillGradient: LinearGradient {
        switch snapshot.status {
        case .ongoing:
            return LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.95, blue: 0.82),
                    Color(red: 0.20, green: 0.82, blue: 1.00),
                    Color(red: 1.00, green: 0.40, blue: 0.77)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .upcoming:
            return LinearGradient(
                colors: [
                    Color(red: 0.49, green: 0.64, blue: 0.70, opacity: 0.52),
                    Color(red: 0.63, green: 0.75, blue: 0.80, opacity: 0.30)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .ended:
            return LinearGradient(
                colors: [
                    Color(red: 0.51, green: 0.64, blue: 0.70, opacity: 0.60),
                    Color(red: 0.63, green: 0.74, blue: 0.79, opacity: 0.42)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .unknown:
            return LinearGradient(
                colors: [
                    Color(red: 0.56, green: 0.66, blue: 0.71, opacity: 0.45),
                    Color(red: 0.67, green: 0.75, blue: 0.80, opacity: 0.28)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var endpointBackground: Color {
        snapshot.status == .ongoing ? .white : Color(red: 0.98, green: 0.99, blue: 1.00)
    }

    private var endpointBorder: Color {
        snapshot.status == .ongoing ? Color.white.opacity(0.96) : Color(red: 0.93, green: 0.96, blue: 0.98)
    }

    private var endpointTextColor: Color {
        switch snapshot.status {
        case .ongoing:
            return Color(red: 0.20, green: 0.82, blue: 1.00)
        case .upcoming, .ended, .unknown:
            return Color(red: 0.34, green: 0.44, blue: 0.49, opacity: 0.88)
        }
    }

    private var fillGlowColor: Color {
        switch snapshot.status {
        case .ongoing:
            return Color(red: 0.38, green: 0.86, blue: 1.00, opacity: 0.31)
        case .upcoming:
            return Color(red: 0.61, green: 0.73, blue: 0.80, opacity: 0.19)
        case .ended:
            return Color(red: 0.55, green: 0.66, blue: 0.72, opacity: 0.14)
        case .unknown:
            return Color(red: 0.56, green: 0.66, blue: 0.71, opacity: 0.11)
        }
    }

    private var fillGlowRadius: CGFloat {
        switch snapshot.status {
        case .ongoing:
            return 8 * glowBoost
        case .upcoming:
            return 5 * glowBoost
        case .ended, .unknown:
            return 3 * glowBoost
        }
    }

    private var endpointGlowColor: Color {
        switch snapshot.status {
        case .ongoing:
            return Color(red: 0.42, green: 0.80, blue: 1.00, opacity: 0.33)
        case .upcoming:
            return Color(red: 0.67, green: 0.76, blue: 0.83, opacity: 0.21)
        case .ended:
            return Color(red: 0.62, green: 0.72, blue: 0.78, opacity: 0.17)
        case .unknown:
            return Color(red: 0.62, green: 0.72, blue: 0.78, opacity: 0.13)
        }
    }

    private var endpointGlowRadius: CGFloat {
        switch snapshot.status {
        case .ongoing:
            return 10 * glowBoost
        case .upcoming:
            return 7 * glowBoost
        case .ended:
            return 5 * glowBoost
        case .unknown:
            return 4 * glowBoost
        }
    }

    @ViewBuilder
    private var endpointBubbleContent: some View {
        if let endpointIconName {
            if endpointIconIsColorized {
                if endpointIconName == TsugieSmallIcon.hanabiAsset {
                    Image(endpointIconName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .scaleEffect(1.65 * 1.3)
                        .rotationEffect(.degrees(23))
                        .foregroundStyle(hanabiEndpointGradient)
                } else {
                    Image(endpointIconName)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .scaleEffect(1.65 * 1.3)
                        .saturation(1.18)
                        .contrast(1.05)
                }
            } else {
                Image(endpointIconName)
                    .resizable()
                    .renderingMode(endpointIconName == TsugieSmallIcon.hanabiAsset ? .template : .original)
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .scaleEffect(1.65 * 1.3)
                    .rotationEffect(.degrees(endpointIconName == TsugieSmallIcon.hanabiAsset ? 23 : 0))
                    .saturation(0)
                    .contrast(0.95)
                    .foregroundStyle(Color(red: 0.54, green: 0.61, blue: 0.67))
            }
        } else {
            Text("へ")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(endpointTextColor)
        }
    }

    private var hanabiEndpointGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 250.0 / 255.0, green: 112.0 / 255.0, blue: 154.0 / 255.0),
                Color(red: 254.0 / 255.0, green: 225.0 / 255.0, blue: 64.0 / 255.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
