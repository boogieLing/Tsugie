import SwiftUI

struct DetailPanelView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    let place: HePlace
    let snapshot: EventStatusSnapshot
    let placeState: PlaceState
    let stamp: PlaceStampPresentation?
    let distanceText: String
    let openHoursText: String
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onFocusTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.Detail.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.55, blue: 0.60))

                FavoriteStateIconView(isFavorite: placeState.isFavorite, size: 30)

                Spacer()

                TsugieClosePillButton(action: onClose, accessibilityLabel: L10n.Detail.closeA11y)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text(place.name)
                            .font(.system(size: detailTitleFontSize, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                            .lineLimit(detailTitleLineLimit)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let oneLiner = localizedOneLiner,
                       !oneLiner.isEmpty {
                        Text(oneLiner)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color(red: 0.30, green: 0.44, blue: 0.50))
                            .lineSpacing(2)
                            .padding(.top, 8)
                    }

                    HStack {
                        Text(distanceText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                        Spacer()
                        Text(openHoursText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                    }
                    .padding(.top, 8)

                    detailProgressBlock
                        .padding(.top, 12)

                    if place.hasImageAsset {
                        heroImageBlock
                            .padding(.top, 14)
                    }

                    miniMapBlock
                        .padding(.top, 14)

                    statsBlock
                        .padding(.top, 14)

                    introBlock
                        .padding(.top, 14)

                    if preferredSourceURL != nil {
                        sourceBlock
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background {
            ZStack {
                TsugieVisuals.detailBackground
                Circle()
                    .fill(Color(red: 0.72, green: 1.0, blue: 0.90, opacity: 0.3))
                    .frame(width: 360, height: 360)
                    .offset(x: -140, y: -220)
                PlaceStampBackgroundView(
                    stamp: stamp,
                    size: 260,
                    loadMode: .immediate,
                    rotationDegrees: stamp?.rotationDegrees ?? 0
                )
                    .opacity(0.76)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 16, y: 20)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 0.86, green: 0.93, blue: 0.95, opacity: 0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var detailProgressBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(progressTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                Spacer()
                Text(progressMeta)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
            }

            TsugieStatusTrackView(
                snapshot: snapshot,
                variant: .detail,
                progress: progressValue,
                endpointIconName: TsugieSmallIcon.assetName(for: place.heType),
                endpointIconIsColorized: placeState.isFavorite
            )
                .padding(.top, 8)

            HStack {
                Text(progressLeft)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                Spacer()
                Text(progressRight)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
            }
            .padding(.top, 9)
        }
    }

    private var heroImageBlock: some View {
        HePlaceDetailImageView(place: place, height: 196)
            .frame(maxWidth: .infinity)
            .frame(height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.9), lineWidth: 1)
            )
    }

    private var miniMapBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.Detail.mapLocation)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                Spacer()
                Button(L10n.Detail.focus, action: onFocusTap)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.86), in: Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.80, green: 0.89, blue: 0.93, opacity: 0.95), lineWidth: 1))
                    .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                    .buttonStyle(.plain)
            }
            Text(place.mapSpot)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                .padding(.top, 8)
        }
        .padding(12)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.85), lineWidth: 1)
        )
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Detail.intro)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
            Text(localizedDetailDescription)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.85), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var sourceBlock: some View {
        if let sourceURLText = preferredSourceURL,
           let sourceURL = URL(string: sourceURLText) {
            HStack {
                Button {
                    openURL(sourceURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(L10n.Detail.sourceTitle) ٩(^ᴗ^)۶")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(red: 0.22, green: 0.43, blue: 0.56))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.86), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 0.80, green: 0.89, blue: 0.93, opacity: 0.95), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Detail.sourceTitle)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preferredSourceURL: String? {
        if let primary = place.descriptionSourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !primary.isEmpty {
            return primary
        }
        return place.sourceURLs.first
    }

    private var localizedDetailDescription: String {
        place.localizedDetailDescription(for: locale.identifier)
    }

    private var localizedOneLiner: String? {
        place.localizedOneLiner(for: locale.identifier)
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Detail.atmosphere)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
            statRow(title: L10n.Detail.heat, value: place.heatScore)
            statRow(title: L10n.Detail.surprise, value: place.surpriseScore)
        }
        .padding(12)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.85), lineWidth: 1)
        )
    }

    private func statRow(title: String, value: Int) -> some View {
        let safe = min(max(value, 0), 100)
        return VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                Spacer()
                Text("\(safe)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
            }
            .padding(.bottom, 7)

            Capsule()
                .fill(activeGlowColor.opacity(0.20))
                .frame(height: 8)
                .overlay {
                    GeometryReader { proxy in
                        let width = max(8, proxy.size.width * CGFloat(safe) / 100)
                        Capsule()
                            .fill(activeGradient)
                            .frame(width: width, height: 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
        }
    }

    private var progressTitle: String {
        switch snapshot.status {
        case .ongoing: L10n.Detail.progressTitleOngoing
        case .upcoming: L10n.Detail.progressTitleUpcoming
        case .ended: L10n.Detail.progressTitleEnded
        case .unknown: L10n.Detail.progressTitleUnknown
        }
    }

    private var progressMeta: String {
        switch snapshot.status {
        case .ongoing:
            L10n.Detail.progressMetaOngoing(
                percent: Int((snapshot.progress ?? 0) * 100),
                eta: snapshot.etaLabel
            )
        case .upcoming:
            snapshot.etaLabel.isEmpty ? L10n.Detail.upcomingPending : L10n.Detail.progressMetaUpcoming(snapshot.etaLabel)
        case .ended:
            L10n.EventStatus.ended
        case .unknown:
            L10n.Common.unknownTime
        }
    }

    private var progressLeft: String {
        switch snapshot.status {
        case .ongoing, .ended: L10n.Detail.startAt(snapshot.startLabel)
        case .upcoming, .unknown: L10n.Common.now
        }
    }

    private var progressRight: String {
        switch snapshot.status {
        case .ongoing, .ended: L10n.Detail.endAt(snapshot.endLabel)
        case .upcoming: L10n.Detail.startAt(snapshot.startLabel)
        case .unknown: L10n.Common.startUnknown
        }
    }

    private var progressValue: Double {
        switch snapshot.status {
        case .ongoing: min(max(snapshot.progress ?? 0, 0), 1)
        case .upcoming: min(max(snapshot.waitProgress ?? 0.08, 0), 1)
        case .ended: 1
        case .unknown: 0.08
        }
    }

    private var detailTitleLineLimit: Int {
        place.name.count >= 20 ? 3 : 2
    }

    private var detailTitleFontSize: CGFloat {
        if place.name.count >= 30 {
            return 24
        }
        if place.name.count >= 20 {
            return 27
        }
        return 30
    }
}

private struct HePlaceDetailImageView: View {
    let place: HePlace
    let height: CGFloat
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else if isLoading {
                ProgressView()
                    .tint(Color(red: 0.24, green: 0.43, blue: 0.52))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.89, green: 0.95, blue: 0.98),
                    Color(red: 0.95, green: 0.98, blue: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task(id: place.id) {
            isLoading = true
            image = HePlaceImageRepository.loadImage(for: place)
            isLoading = false
        }
        .onDisappear {
            image = nil
            isLoading = false
        }
    }
}
