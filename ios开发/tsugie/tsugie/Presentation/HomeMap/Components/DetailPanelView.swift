import SwiftUI

struct DetailPanelView: View {
    let place: HePlace
    let snapshot: EventStatusSnapshot
    let placeState: PlaceState
    let distanceText: String
    let openHoursText: String
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onFocusTap: () -> Void
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(red: 0.33, green: 0.47, blue: 0.52, opacity: 0.35))
                .frame(width: 50, height: 5)
                .padding(.top, 18)
                .padding(.bottom, 8)

            HStack {
                Text(L10n.Detail.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.55, blue: 0.60))

                Spacer()

                Button(action: onClose) {
                    Text("⌄")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.82), in: Circle())
                        .overlay(Circle().stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.86), lineWidth: 1))
                        .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Detail.closeA11y)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .gesture(dragGesture)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text(place.name)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                            .lineLimit(2)
                        Spacer()
                        PlaceStateIconsView(
                            placeState: placeState,
                            size: 19,
                            activeGradient: activeGradient,
                            activeGlowColor: activeGlowColor
                        )
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

                    heroBlock
                        .padding(.top, 14)

                    miniMapBlock
                        .padding(.top, 14)

                    introBlock
                        .padding(.top, 14)

                    statsBlock
                        .padding(.top, 14)
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
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 0.86, green: 0.93, blue: 0.95, opacity: 0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .offset(y: max(0, dragOffset))
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

            TsugieStatusTrackView(snapshot: snapshot, variant: .detail, progress: progressValue)
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
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.imageTag)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color(red: 0.18, green: 0.38, blue: 0.46))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.white.opacity(0.72), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1))

            Text(place.imageHint)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.50))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(height: 166, alignment: .bottomLeading)
        .background(heroGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            Text(place.detailDescription)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                .lineSpacing(3)
        }
        .padding(12)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.85), lineWidth: 1)
        )
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
                .fill(Color(red: 0.79, green: 0.89, blue: 0.92, opacity: 0.58))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.16, green: 0.83, blue: 0.77), Color(red: 0.45, green: 0.73, blue: 1.00)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mask(
                            GeometryReader { proxy in
                                Rectangle()
                                    .frame(width: proxy.size.width * CGFloat(safe) / 100)
                            }
                        )
                }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragOffset = min(max(value.translation.height, 0), 260)
            }
            .onEnded { _ in
                let delta = dragOffset
                dragOffset = 0
                if delta >= 110 {
                    onClose()
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

    private var heroGradient: some ShapeStyle {
        let from: Color
        let to: Color
        switch place.heType {
        case .hanabi:
            from = Color(red: 0.78, green: 0.93, blue: 1.00)
            to = Color(red: 0.86, green: 0.93, blue: 1.00)
        case .matsuri:
            from = Color(red: 1.00, green: 0.92, blue: 0.82)
            to = Color(red: 1.00, green: 0.87, blue: 0.82)
        case .nature:
            from = Color(red: 0.82, green: 0.96, blue: 0.90)
            to = Color(red: 0.83, green: 0.92, blue: 0.99)
        case .other:
            from = Color(red: 0.88, green: 0.91, blue: 1.00)
            to = Color(red: 0.88, green: 0.95, blue: 1.00)
        }

        return LinearGradient(colors: [from, to], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
