import ImageIO
import SwiftUI

struct DetailPanelView: View {
    private enum RenderPhase: Int {
        case header = 0
        case media = 1
        case full = 2
    }

    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @State private var illustrationSelectionID = UUID()
    @State private var renderPhase: RenderPhase = .header

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
                        if shouldRenderMediaSection {
                            heroImageBlock
                                .padding(.top, 14)
                        } else {
                            heroImageSkeletonBlock
                                .padding(.top, 14)
                        }
                    }

                    if shouldRenderMediaSection {
                        atmosphereCompositionBlock
                            .padding(.top, 14)
                    } else {
                        atmosphereCompositionSkeletonBlock
                            .padding(.top, 14)
                    }

                    if shouldRenderFullSection {
                        miniMapBlock
                            .padding(.top, 10)

                        if !extraInfoRows.isEmpty {
                            extraInfoBlock
                                .padding(.top, 14)
                        }

                        introBlock
                            .padding(.top, 14)

                        if preferredSourceURL != nil {
                            sourceBlock
                                .padding(.top, 14)
                        }
                    } else {
                        deferredContentSkeletonBlock
                            .padding(.top, 10)
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
                if shouldRenderFullSection {
                    PlaceStampBackgroundView(
                        stamp: stamp,
                        size: 260,
                        loadMode: .deferred,
                        rotationDegrees: stamp?.rotationDegrees ?? 0
                    )
                        .opacity(0.76)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .offset(x: 16, y: 20)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(red: 0.86, green: 0.93, blue: 0.95, opacity: 0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear {
            illustrationSelectionID = UUID()
            renderPhase = .header
        }
        .onChange(of: place.id) { _, _ in
            illustrationSelectionID = UUID()
            renderPhase = .header
        }
        .task(id: place.id) {
            await advanceRenderPhase()
        }
    }

    private var shouldRenderMediaSection: Bool {
        renderPhase.rawValue >= RenderPhase.media.rawValue
    }

    private var shouldRenderFullSection: Bool {
        renderPhase == .full
    }

    @MainActor
    private func advanceRenderPhase() async {
        renderPhase = .header
        await Task.yield()
        try? await Task.sleep(nanoseconds: 45_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            renderPhase = .media
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            renderPhase = .full
        }
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

    private var heroImageSkeletonBlock: some View {
        DetailSkeletonBlock(cornerRadius: 16)
            .frame(maxWidth: .infinity)
            .frame(height: 196)
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

    private var extraInfoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Detail.extraInfo)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))

            ForEach(Array(extraInfoRows.enumerated()), id: \.offset) { index, row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                    Text(row.value)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(red: 0.37, green: 0.49, blue: 0.53))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if index < extraInfoRows.count - 1 {
                    Divider()
                        .overlay(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.85), lineWidth: 1)
        )
    }

    private var extraInfoRows: [(title: String, value: String)] {
        var rows: [(title: String, value: String)] = []

        func append(_ title: String, _ rawValue: String?) {
            guard let value = normalizedExtraInfoValue(rawValue) else { return }
            rows.append((title: title, value: value))
        }

        switch place.heType {
        case .hanabi:
            append(L10n.Detail.launchCount, place.launchCount)
            append(L10n.Detail.launchScale, place.launchScale)
            append(L10n.Detail.paidSeat, place.paidSeat)
            append(L10n.Detail.accessText, place.accessText)
            append(L10n.Detail.parkingText, place.parkingText)
            append(L10n.Detail.trafficControlText, place.trafficControlText)
        case .matsuri:
            append(L10n.Detail.organizer, place.organizer)
            append(L10n.Detail.festivalType, place.festivalType)
            append(L10n.Detail.admissionFee, place.admissionFee)
            append(L10n.Detail.expectedVisitors, place.expectedVisitors)
            append(L10n.Detail.accessText, place.accessText)
            append(L10n.Detail.parkingText, place.parkingText)
        default:
            append(L10n.Detail.accessText, place.accessText)
            append(L10n.Detail.parkingText, place.parkingText)
        }

        return rows
    }

    private func normalizedExtraInfoValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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

    private var atmosphereCompositionBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            DetailRandomIllustrationView(selectionID: illustrationSelectionID)
                .frame(width: 146, height: 146)
                .offset(y: 10)

            atmosphereStatsCardBlock
                .frame(maxWidth: 214, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var atmosphereCompositionSkeletonBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            DetailSkeletonBlock(cornerRadius: 14)
                .frame(width: 146, height: 146)
                .offset(y: 10)

            DetailSkeletonBlock(cornerRadius: 14)
                .frame(maxWidth: 214)
                .frame(height: 128)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deferredContentSkeletonBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSkeletonBlock(cornerRadius: 14)
                .frame(height: 74)

            if !extraInfoRows.isEmpty {
                DetailSkeletonBlock(cornerRadius: 14)
                    .frame(height: min(230, CGFloat(92 + (extraInfoRows.count * 26))))
            }

            DetailSkeletonBlock(cornerRadius: 14)
                .frame(height: 164)

            if preferredSourceURL != nil {
                DetailSkeletonBlock(cornerRadius: 999)
                    .frame(width: 168, height: 32)
            }
        }
        .transition(.opacity)
    }

    private var atmosphereStatsCardBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Detail.atmosphere)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
            statRow(title: L10n.Detail.heat, value: dynamicHeatScore)
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

    private var dynamicHeatScore: Int {
        let baseHeat = min(max(place.heatScore, 0), 100)
        guard let startAt = place.startAt else { return baseHeat }

        let defaultEnd = startAt.addingTimeInterval(2 * 3600)
        let endAt = max(place.endAt ?? defaultEnd, defaultEnd)
        let now = Date()

        let leadHours = 36.0 + stableUnitValue(salt: "heat_lead") * 28.0
        let rampStart = startAt.addingTimeInterval(-leadHours * 3600.0)

        let duration = max(endAt.timeIntervalSince(startAt), 2 * 3600)
        let peakFraction = 0.52 + stableUnitValue(salt: "heat_peak") * 0.33
        let peakAt = min(endAt, startAt.addingTimeInterval(duration * peakFraction))

        let boost = 12 + Int((stableUnitValue(salt: "heat_boost") * 18.0).rounded())
        let peakHeat = min(100, baseHeat + boost)

        if now <= rampStart {
            return baseHeat
        }
        if now >= peakAt {
            return peakHeat
        }

        let total = max(peakAt.timeIntervalSince(rampStart), 1)
        let progress = min(max(now.timeIntervalSince(rampStart) / total, 0), 1)
        let eased = pow(progress, 1.08)
        let heat = Double(baseHeat) + (Double(peakHeat - baseHeat) * eased)
        return min(max(Int(heat.rounded()), baseHeat), peakHeat)
    }

    private func stableUnitValue(salt: String) -> Double {
        let key = "\(place.id.uuidString)#\(salt)"
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Double(hash % 10_000) / 10_000.0
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

private struct DetailRandomIllustrationView: View {
    let selectionID: UUID

    private struct IllustrationResource {
        let fileName: String
        let fileURL: URL
    }

    nonisolated private static let supportedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]
    nonisolated private static let fallbackNamePrefix = "detail-illustration-"
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if isLoading {
                ProgressView()
                    .tint(Color(red: 0.24, green: 0.43, blue: 0.52))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: selectionID) {
            await loadRandomIllustration()
        }
        .onDisappear {
            // Explicitly release bitmap memory when detail panel is dismissed.
            image = nil
            isLoading = false
        }
    }

    @MainActor
    private func loadRandomIllustration() async {
        image = nil
        isLoading = true

        let targetResource = await Task.detached(priority: .utility) {
            Self.availableIllustrationResources().randomElement()
        }.value
        guard let targetResource else {
            isLoading = false
            return
        }

        let loaded = await Task.detached(priority: .utility) {
            Self.loadIllustrationImage(from: targetResource.fileURL, maxPixelSize: 420)
        }.value

        guard !Task.isCancelled else {
            return
        }

        image = loaded
        isLoading = false
    }

    private nonisolated static func availableIllustrationResources() -> [IllustrationResource] {
        discoverIllustrationResources()
    }

    private nonisolated static func loadIllustrationImage(from fileURL: URL, maxPixelSize: Int) -> UIImage? {
        if let downsampled = downsampleImage(url: fileURL, maxPixelSize: maxPixelSize) {
            return downsampled
        }
        if let direct = UIImage(contentsOfFile: fileURL.path) {
            return direct
        }
        return nil
    }

    private nonisolated static func discoverIllustrationResources() -> [IllustrationResource] {
        let fileManager = FileManager.default
        var discovered: [IllustrationResource] = []
        var seen = Set<String>()

        for directoryURL in illustrationDirectoryURLs() {
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in fileURLs {
                let isRegularFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? true
                guard isRegularFile else {
                    continue
                }
                let fileExtension = fileURL.pathExtension.lowercased()
                guard supportedImageExtensions.contains(fileExtension) else {
                    continue
                }

                let fileName = fileURL.lastPathComponent
                let dedupeKey = fileName.lowercased()
                if seen.insert(dedupeKey).inserted {
                    discovered.append(IllustrationResource(fileName: fileName, fileURL: fileURL))
                }
            }
        }

        // Fallback: some build pipelines flatten resource files to bundle root.
        if discovered.isEmpty {
            discovered = discoverIllustrationResourcesFromBundleIndex()
        }

        return discovered.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    private nonisolated static func discoverIllustrationResourcesFromBundleIndex() -> [IllustrationResource] {
        let bundle = Bundle.main
        var discovered: [IllustrationResource] = []
        var seen = Set<String>()

        for ext in supportedImageExtensions {
            let candidates =
                (bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []) +
                (bundle.urls(forResourcesWithExtension: ext, subdirectory: "illustration") ?? []) +
                (bundle.urls(forResourcesWithExtension: ext, subdirectory: "Resources/illustration") ?? [])

            for fileURL in candidates {
                let fileName = fileURL.lastPathComponent
                guard isFallbackIllustrationFileName(fileName) else {
                    continue
                }
                let dedupeKey = fileName.lowercased()
                if seen.insert(dedupeKey).inserted {
                    discovered.append(IllustrationResource(fileName: fileName, fileURL: fileURL))
                }
            }
        }

        return discovered
    }

    private nonisolated static func isFallbackIllustrationFileName(_ fileName: String) -> Bool {
        fileName.lowercased().hasPrefix(fallbackNamePrefix)
    }

    private nonisolated static func illustrationDirectoryURLs() -> [URL] {
        let fileManager = FileManager.default
        var urls: [URL] = []
        var seen = Set<String>()

        func appendIfDirectory(_ url: URL?) {
            guard let url else {
                return
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return
            }

            let key = url.standardizedFileURL.path.lowercased()
            guard seen.insert(key).inserted else {
                return
            }
            urls.append(url)
        }

        let bundle = Bundle.main
        appendIfDirectory(bundle.url(forResource: "illustration", withExtension: nil))
        appendIfDirectory(bundle.url(forResource: "illustration", withExtension: nil, subdirectory: "Resources"))
        appendIfDirectory(bundle.resourceURL?.appendingPathComponent("illustration", isDirectory: true))
        appendIfDirectory(bundle.resourceURL?.appendingPathComponent("Resources/illustration", isDirectory: true))

        return urls
    }

    private nonisolated static func downsampleImage(url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

}

private struct DetailSkeletonBlock: View {
    let cornerRadius: CGFloat
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.64))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.82, green: 0.91, blue: 0.95))
                    .opacity(pulse ? 0.34 : 0.58)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .onDisappear {
                pulse = false
            }
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
            image = nil
            let imageRef = place.imageRef
            let loadedImage = await Task.detached(priority: .utility) {
                HePlaceImageRepository.loadImage(imageRef: imageRef)
            }.value
            guard !Task.isCancelled else {
                return
            }
            image = loadedImage
            isLoading = false
        }
        .onDisappear {
            image = nil
            isLoading = false
        }
    }
}
