import SwiftUI

struct NearbyCarouselItemModel: Identifiable, Equatable {
    let id: UUID
    let name: String
    let snapshot: EventStatusSnapshot
    let distanceText: String
    let placeState: PlaceState
    let stamp: PlaceStampPresentation?
    let endpointIconName: String
}

struct NearbyCarouselView: View {
    let items: [NearbyCarouselItemModel]
    let onSelectPlace: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    NearbyCarouselItemView(
                        item: item,
                        onSelectPlace: onSelectPlace
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Color.clear)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .background(Color.clear)
    }

}

private struct NearbyCarouselItemView: View, Equatable {
    let item: NearbyCarouselItemModel
    let onSelectPlace: (UUID) -> Void

    static func == (lhs: NearbyCarouselItemView, rhs: NearbyCarouselItemView) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        Button {
            onSelectPlace(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(item.distanceText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.44))

                    HStack(spacing: 6) {
                        FavoriteStateIconView(
                            isFavorite: item.placeState.isFavorite,
                            size: 19
                        )
                        StampIconView(
                            stamp: item.stamp,
                            isColorized: item.placeState.isCheckedIn,
                            size: 20
                        )
                    }
                }

                HStack(spacing: 10) {
                    Text(etaLabel(item.snapshot))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.44))

                    Spacer(minLength: 4)

                    Text(startLabel(item.snapshot))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.44))
                }

                TsugieMiniProgressView(
                    snapshot: item.snapshot,
                    glowBoost: 1.7,
                    endpointIconName: item.endpointIconName
                )
                    .padding(.top, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 232, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.64))
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.89, green: 0.95, blue: 0.97, opacity: 0.94), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.13, green: 0.31, blue: 0.38, opacity: 0.14), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func etaLabel(_ snapshot: EventStatusSnapshot) -> String {
        switch snapshot.status {
        case .ongoing:
            return L10n.Nearby.remaining(snapshot.etaLabel)
        case .upcoming:
            return snapshot.etaLabel.isEmpty ? L10n.Nearby.preparing : L10n.Nearby.startsIn(snapshot.etaLabel)
        case .ended:
            return L10n.EventStatus.ended
        case .unknown:
            return L10n.Common.unknownTime
        }
    }

    private func startLabel(_ snapshot: EventStatusSnapshot) -> String {
        switch snapshot.status {
        case .ongoing, .upcoming:
            return L10n.Nearby.startsAt(snapshot.startLabel)
        case .ended:
            return L10n.Nearby.endedAt(snapshot.endLabel)
        case .unknown:
            return L10n.Common.startUnknown
        }
    }
}
