import SwiftUI
import ImageIO
import UIKit

struct RootView: View {
    @StateObject private var viewModel = HomeMapViewModel()
    @AppStorage("tsugie.privacy.policy.accepted.v1") private var hasAcceptedPrivacyPolicy = false
    @State private var isCalendarPresented = false
    @State private var isLaunchSplashVisible = true
    @State private var pendingCalendarNavigationPlaceID: UUID?

    private var shouldShowPrivacyConsent: Bool {
        !isLaunchSplashVisible && !hasAcceptedPrivacyPolicy
    }

    var body: some View {
        ZStack {
            HomeMapView(
                viewModel: viewModel,
                suppressLocationFallbackAlert: isLaunchSplashVisible || shouldShowPrivacyConsent,
                onOpenCalendar: {
                    viewModel.setCalendarPresented(true)
                    isCalendarPresented = true
                }
            )
            .environment(\.locale, viewModel.selectedLanguageLocale)
            .fullScreenCover(
                isPresented: $isCalendarPresented,
                onDismiss: {
                    viewModel.setCalendarPresented(false)
                    if let placeID = pendingCalendarNavigationPlaceID {
                        pendingCalendarNavigationPlaceID = nil
                        Task { @MainActor in
                            await Task.yield()
                            viewModel.openQuickFromCalendar(placeID: placeID)
                        }
                    }
                }
            ) {
                CalendarPageView(
                    places: viewModel.places,
                    detailPlaces: viewModel.calendarDetailPlaces,
                    placeStateProvider: { viewModel.placeState(for: $0) },
                    stampProvider: { viewModel.stampPresentation(for: $0, heType: $1) },
                    onClose: {
                        pendingCalendarNavigationPlaceID = nil
                        viewModel.setCalendarPresented(false)
                        isCalendarPresented = false
                    },
                    onSelectPlace: { placeID in
                        // Close calendar visual state first (avoid white frame), then navigate on dismiss
                        // to avoid camera race between cover transition and map jump.
                        viewModel.prepareForCalendarPlaceNavigation()
                        viewModel.setCalendarPresented(false)
                        pendingCalendarNavigationPlaceID = placeID
                        isCalendarPresented = false
                    },
                    now: viewModel.now,
                    activeGradient: viewModel.activePillGradient,
                    activeGlowColor: viewModel.activeMapGlowColor
                )
                .environment(\.locale, viewModel.selectedLanguageLocale)
            }

            if isLaunchSplashVisible {
                LaunchSplashOverlayView()
                    .transition(.opacity)
                    .zIndex(100)
            }

            if shouldShowPrivacyConsent {
                FirstLaunchPrivacyConsentView {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        hasAcceptedPrivacyPolicy = true
                    }
                }
                .transition(.opacity)
                .zIndex(110)
            }
        }
        .task(id: isLaunchSplashVisible) {
            guard isLaunchSplashVisible else {
                return
            }
            viewModel.beginLaunchPrewarmIfNeeded()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.24)) {
                isLaunchSplashVisible = false
            }
        }
    }
}

private struct FirstLaunchPrivacyConsentView: View {
    let onAccept: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Privacy.firstLaunchTitle)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Color(red: 0.16, green: 0.31, blue: 0.38))

                    Text(L10n.Privacy.firstLaunchMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.27, green: 0.42, blue: 0.49))
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: L10n.SideDrawer.privacyPolicyURL) {
                        Text(L10n.Privacy.firstLaunchOpenPolicy)
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(red: 0.80, green: 0.89, blue: 0.93), lineWidth: 1)
                            )
                            .foregroundStyle(Color(red: 0.17, green: 0.35, blue: 0.43))
                    }
                    .buttonStyle(.plain)

                    Button(action: onAccept) {
                        Text(L10n.Privacy.firstLaunchAccept)
                            .font(.system(size: 14, weight: .heavy))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.36, green: 0.66, blue: 0.82),
                                        Color(red: 0.17, green: 0.46, blue: 0.64)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)

                    Text(L10n.Privacy.firstLaunchRequiredHint)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.42, green: 0.53, blue: 0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: min(max(proxy.size.width - 32, 280), 420))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.98, blue: 0.99, opacity: 0.98))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(red: 0.86, green: 0.93, blue: 0.96), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct LaunchSplashOverlayView: View {
    @State private var splashImage: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                    .ignoresSafeArea()

                if let splashImage {
                    let horizontalInset: CGFloat = 10
                    let availableWidth = max(0, proxy.size.width - horizontalInset * 2)
                    let availableHeight = max(
                        0,
                        proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom - 8
                    )

                    Image(uiImage: splashImage)
                        .resizable()
                        .interpolation(.low)
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 22, opaque: true)
                        .clipped()
                        .saturation(0.92)
                        .brightness(0.03)
                        .overlay(Color.white.opacity(0.18))
                        .overlay {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .opacity(0.28)
                        }
                        .ignoresSafeArea()

                    Image(uiImage: splashImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: availableWidth,
                            height: availableHeight,
                            alignment: .center
                        )
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                } else {
                    ProgressView()
                        .tint(Color(red: 0.22, green: 0.43, blue: 0.52))
                }
            }
        }
        .task {
            guard splashImage == nil else {
                return
            }
            let loaded = await Task.detached(priority: .userInitiated) {
                SplashAssetLoader.loadSplashImage()
            }.value
            splashImage = loaded
        }
        .onDisappear {
            splashImage = nil
        }
    }
}

private enum SplashAssetLoader {
    nonisolated static func loadSplashImage() -> UIImage? {
        guard let url = splashImageURL() else {
            return nil
        }
        return downsampledImage(at: url, maxPixelSize: 1_600)
    }

    nonisolated static func splashImageURL() -> URL? {
        let imageURLs = allSplashImageURLs()
        guard !imageURLs.isEmpty else {
            return nil
        }
        return imageURLs.randomElement()
    }

    nonisolated private static func allSplashImageURLs() -> [URL] {
        let subdirectoryCandidates = ["tsugie_splash", nil]
        let imageExtensions = ["jpg", "jpeg", "png", "webp"]
        var urls: [URL] = []

        for subdirectory in subdirectoryCandidates {
            for ext in imageExtensions {
                urls.append(contentsOf:
                    contentsOfBundle(forExtension: ext, subdirectory: subdirectory)
                )
            }
        }

        let filtered = urls.filter { isSplashImageFileName($0.lastPathComponent) }
        let candidates = filtered.isEmpty ? urls : filtered

        // Keep deterministic ordering and deduplicate identical file URLs.
        let unique = Dictionary(grouping: candidates, by: \.path).compactMap { $0.value.first }
        return unique.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    nonisolated private static func isImageFileName(_ fileName: String) -> Bool {
        let lowercased = fileName.lowercased()
        return lowercased.hasSuffix(".jpg")
            || lowercased.hasSuffix(".jpeg")
            || lowercased.hasSuffix(".png")
            || lowercased.hasSuffix(".webp")
    }

    nonisolated private static func isSplashImageFileName(_ fileName: String) -> Bool {
        guard isImageFileName(fileName) else {
            return false
        }
        let baseName = (fileName as NSString).deletingPathExtension
        return !baseName.isEmpty && baseName.allSatisfy(\.isNumber)
    }

    nonisolated private static func contentsOfBundle(
        forExtension ext: String,
        subdirectory: String?
    ) -> [URL] {
        if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: subdirectory) {
            return urls
        }
        return []
    }

    nonisolated private static func downsampledImage(at url: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(128, maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
