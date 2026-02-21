import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = HomeMapViewModel()
    @State private var isCalendarPresented = false
    @State private var isLaunchSplashVisible = true
    @State private var pendingCalendarNavigationPlaceID: UUID?

    var body: some View {
        ZStack {
            HomeMapView(
                viewModel: viewModel,
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
        }
        .task(id: isLaunchSplashVisible) {
            guard isLaunchSplashVisible else {
                return
            }
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

private struct LaunchSplashOverlayView: View {
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                    .ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: proxy.size.width,
                            maxHeight: max(0, proxy.size.height - proxy.safeAreaInsets.top - 12)
                        )
                        .padding(.top, proxy.safeAreaInsets.top + 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color.white)
                } else {
                    ProgressView()
                        .tint(Color(red: 0.22, green: 0.43, blue: 0.52))
                }
            }
        }
        .task {
            guard image == nil else {
                return
            }
            image = await Task.detached(priority: .utility) {
                SplashAssetLoader.loadSplashImage()
            }.value
        }
        .onDisappear {
            image = nil
        }
    }
}

private enum SplashAssetLoader {
    nonisolated static func loadSplashImage() -> UIImage? {
        guard let url = splashImageURL() else {
            return nil
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return UIImage(data: data)
    }

    nonisolated static func splashImageURL() -> URL? {
        if let direct = Bundle.main.url(forResource: "1", withExtension: "jpg", subdirectory: "tsugie_splash") {
            return direct
        }
        if let direct = Bundle.main.url(forResource: "1", withExtension: "jpg") {
            return direct
        }

        guard let resourcePath = Bundle.main.resourcePath else {
            return nil
        }
        let directory = (resourcePath as NSString).appendingPathComponent("tsugie_splash")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        let target = entries
            .filter { $0.lowercased().hasSuffix(".jpg") || $0.lowercased().hasSuffix(".jpeg") || $0.lowercased().hasSuffix(".png") }
            .sorted()
            .first
        guard let target else {
            return nil
        }
        return URL(fileURLWithPath: (directory as NSString).appendingPathComponent(target))
    }
}
