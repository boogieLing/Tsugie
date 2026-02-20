import SwiftUI

struct QuickCardView: View {
    enum Mode {
        case quick
        case expired
    }

    let place: HePlace
    let snapshot: EventStatusSnapshot
    let progress: Double?
    let metaText: String
    let hintText: String
    let placeState: PlaceState
    let stamp: PlaceStampPresentation?
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    var mode: Mode = .quick
    let onClose: () -> Void
    let onOpenDetail: () -> Void
    let onStartRoute: () -> Void
    let onExpandDetailBySwipe: () -> Void
    let onDismissBySwipe: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var dragStartAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(red: 0.33, green: 0.47, blue: 0.52, opacity: 0.35))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)

            HStack(alignment: .center, spacing: 10) {
                titleView

                Spacer()

                HStack(spacing: 8) {
                    FavoriteStateIconView(isFavorite: placeState.isFavorite, size: 30)

                    TsugieClosePillButton(action: onClose, accessibilityLabel: L10n.QuickCard.closeA11y)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Text(place.name)
                    .font(.system(size: quickTitleFontSize, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                    .lineLimit(quickTitleLineLimit)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Text(timeRangeText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.33, green: 0.45, blue: 0.51))
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)

            TsugieStatusTrackView(
                snapshot: snapshot,
                variant: .quick,
                progress: progress ?? 0.08,
                endpointIconName: TsugieSmallIcon.assetName(for: place.heType),
                endpointIconIsColorized: placeState.isFavorite
            )
            .padding(.top, 8)

            Text(metaText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                .padding(.top, 10)

            Text(hintText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(red: 0.42, green: 0.55, blue: 0.60))
                .padding(.top, 8)

            HStack(spacing: 10) {
                Button(action: onOpenDetail) {
                    Text(L10n.QuickCard.viewDetails)
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                }
                .buttonStyle(.plain)

                Button(action: onStartRoute) {
                    Text(L10n.QuickCard.startRoute)
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(activeGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                        .tsugieActiveGlow(
                            isActive: true,
                            glowGradient: activeGradient,
                            glowColor: activeGlowColor,
                            cornerRadius: 14,
                            blurRadius: 10,
                            glowOpacity: 0.84,
                            scale: 1.03
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(.top, 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .background(alignment: .bottomTrailing) {
            PlaceStampBackgroundView(
                stamp: stamp,
                size: 208,
                loadMode: .immediate,
                rotationDegrees: stamp?.rotationDegrees ?? 0
            )
                .offset(x: 18, y: 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.66))
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 0.91, green: 0.96, blue: 0.98, opacity: 0.84), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.31, blue: 0.38, opacity: 0.16), radius: 18, x: 0, y: 10)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if dragStartAt == nil {
                        dragStartAt = Date()
                    }
                    dragOffset = min(max(value.translation.height, -190), 180)
                }
                .onEnded { _ in
                    let delta = dragOffset
                    let elapsed = Date().timeIntervalSince(dragStartAt ?? Date())
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                    dragStartAt = nil

                    if delta <= -44 || (delta <= -20 && elapsed <= 0.22) {
                        onExpandDetailBySwipe()
                        return
                    }
                    if delta >= 56 || (delta >= 26 && elapsed <= 0.22) {
                        onDismissBySwipe()
                    }
                }
        )
    }

    private var timeRangeText: String {
        guard snapshot.status != .unknown else { return L10n.Common.unknownTime }
        return L10n.Common.timeRange(snapshot.startLabel, snapshot.endLabel)
    }

    @ViewBuilder
    private var titleView: some View {
        switch mode {
        case .quick:
            Text(L10n.QuickCard.fastPlanTitle)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(quickTitleGradient)
        case .expired:
            let titleText = "☁️ \(L10n.QuickCard.expiredTitle)"
            Text(titleText)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(expiredTitleLinearGradient)
                .overlay {
                    Text(titleText)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(expiredTitleRadialGradient)
                        .blendMode(.screen)
                        .mask(
                            Text(titleText)
                                .font(.system(size: 15, weight: .heavy))
                        )
                }
        }
    }

    private var quickTitleGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.00, green: 0.48, blue: 0.87),
                Color(red: 0.00, green: 0.93, blue: 0.74)
            ],
            startPoint: UnitPoint(x: 0.05, y: 0.02),
            endPoint: UnitPoint(x: 0.95, y: 0.98)
        )
    }

    private var expiredTitleLinearGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 188.0 / 255.0, green: 197.0 / 255.0, blue: 206.0 / 255.0),
                Color(red: 146.0 / 255.0, green: 158.0 / 255.0, blue: 173.0 / 255.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var expiredTitleRadialGradient: RadialGradient {
        RadialGradient(
            colors: [
                Color.white.opacity(0.30),
                Color.black.opacity(0.30)
            ],
            center: .topLeading,
            startRadius: 0,
            endRadius: 120
        )
    }

    private var quickTitleLineLimit: Int {
        place.name.count >= 16 ? 2 : 1
    }

    private var quickTitleFontSize: CGFloat {
        if place.name.count >= 26 {
            return 18
        }
        if place.name.count >= 16 {
            return 20
        }
        return 22
    }
}
