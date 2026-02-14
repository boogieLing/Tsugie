import SwiftUI

struct NearbyCarouselView: View {
    @ObservedObject var viewModel: HomeMapViewModel
    let onSelectPlace: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(viewModel.nearbyPlaces()) { place in
                    nearbyItem(place)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func nearbyItem(_ place: HePlace) -> some View {
        let palette = TsugieVisuals.palette(for: place.heType)
        let snapshot = viewModel.eventSnapshot(for: place)
        let state = viewModel.placeState(for: place.id)

        return Button {
            onSelectPlace(place.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    Text(place.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(viewModel.distanceText(for: place))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.44))

                    PlaceStateIconsView(
                        placeState: state,
                        size: 16,
                        activeGradient: viewModel.activePillGradient,
                        activeGlowColor: viewModel.activeMapGlowColor,
                        activeGlowBoost: 2.5
                    )
                }

                HStack(spacing: 10) {
                    Text(etaLabel(snapshot))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.44))

                    Spacer(minLength: 4)

                    Text(startLabel(snapshot))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.44))
                }

                TsugieMiniProgressView(snapshot: snapshot, glowBoost: 1.7)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 232, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.84),
                                palette.nearbyTo.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.9), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.15, green: 0.35, blue: 0.42, opacity: 0.13), radius: 10, x: 0, y: 5)
            .shadow(color: palette.nearbyFrom.opacity(0.34), radius: 18, x: 0, y: 0)
            .shadow(color: palette.nearbyTo.opacity(0.30), radius: 28, x: 0, y: 0)
        }
        .buttonStyle(.plain)
    }

    private func etaLabel(_ snapshot: EventStatusSnapshot) -> String {
        switch snapshot.status {
        case .ongoing:
            return "残り \(snapshot.etaLabel)"
        case .upcoming:
            return snapshot.etaLabel.isEmpty ? "開催準備中" : "あと \(snapshot.etaLabel)"
        case .ended:
            return "終了済み"
        case .unknown:
            return "時刻未定"
        }
    }

    private func startLabel(_ snapshot: EventStatusSnapshot) -> String {
        switch snapshot.status {
        case .ongoing, .upcoming:
            return "\(snapshot.startLabel) 開始"
        case .ended:
            return "终了 \(snapshot.endLabel)"
        case .unknown:
            return "開始 未定"
        }
    }
}
