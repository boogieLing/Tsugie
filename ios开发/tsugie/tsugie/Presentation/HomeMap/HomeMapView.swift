import MapKit
import SwiftUI

struct HomeMapView: View {
    @Environment(\.openURL) private var openURL
    @State private var routeNavigationPlace: HePlace?
    @State private var launchBridgeRevealProgress: Double = 0
    @State private var launchBridgeRevealTask: Task<Void, Never>?
    @State private var launchBridgeAnimationGeneration: Int = 0
    @State private var launchBridgeCacheKey: LaunchBridgeCacheKey?
    @State private var launchBridgeBaseBars: [LaunchBridgeVerticalBarTemplate] = []
    @State private var launchBridgeGradientStops: [LaunchBridgeGradientStop] = []

    @ObservedObject var viewModel: HomeMapViewModel
    let suppressLocationFallbackAlert: Bool
    let onOpenCalendar: () -> Void

    var body: some View {
        let markerThemeSignature = MarkerThemeSignature(
            scheme: viewModel.selectedThemeScheme,
            alphaRatio: viewModel.themeAlphaRatio,
            saturationRatio: viewModel.themeSaturationRatio,
            glowRatio: viewModel.themeGlowRatio
        )
        let markerActiveGlowColor = viewModel.activeMapGlowColor
        let markerActionStyleHanabi = MarkerActionStyle(
            gradient: TsugieVisuals.markerGradient(for: .hanabi),
            glowColor: TsugieVisuals.markerGlowColor(for: .hanabi)
        )
        let markerActionStyleMatsuri = MarkerActionStyle(
            gradient: TsugieVisuals.markerGradient(for: .matsuri),
            glowColor: TsugieVisuals.markerGlowColor(for: .matsuri)
        )
        let markerActionStyleFallback = MarkerActionStyle(
            gradient: TsugieVisuals.markerGradient(for: .other),
            glowColor: TsugieVisuals.markerGlowColor(for: .other)
        )
        let markerEntries = viewModel.mapMarkerEntries()
        let hasVisibleMarkerMenu = markerEntries.contains(where: \.isMenuVisible)
        let quickCardDismissAnimation = Animation.spring(response: 0.40, dampingFraction: 0.92)
        let locationLogoGradient = LinearGradient(
            colors: [
                Color(red: 34.0 / 255.0, green: 225.0 / 255.0, blue: 1.0),
                Color(red: 29.0 / 255.0, green: 143.0 / 255.0, blue: 225.0 / 255.0),
                Color(red: 98.0 / 255.0, green: 94.0 / 255.0, blue: 177.0 / 255.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let locationIconColor = Color(
            red: 81.0 / 255.0,
            green: 81.0 / 255.0,
            blue: 81.0 / 255.0
        )
        let sidebarIconColor = locationIconColor

        ZStack(alignment: .bottom) {
            if viewModel.isCalendarPresented {
                Color.clear
                    .ignoresSafeArea()
            } else {
                mapCanvas(
                    markerEntries: markerEntries,
                    markerThemeSignature: markerThemeSignature,
                    markerActiveGlowColor: markerActiveGlowColor,
                    markerActionStyleHanabi: markerActionStyleHanabi,
                    markerActionStyleMatsuri: markerActionStyleMatsuri,
                    markerActionStyleFallback: markerActionStyleFallback,
                    hasVisibleMarkerMenu: hasVisibleMarkerMenu,
                    locationLogoGradient: locationLogoGradient
                )

                if let detailPlace = viewModel.detailPlace {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        DetailPanelView(
                            place: detailPlace,
                            snapshot: viewModel.eventSnapshot(for: detailPlace, now: context.date),
                            placeState: viewModel.placeState(for: detailPlace.id),
                            stamp: viewModel.stampPresentation(for: detailPlace),
                            distanceText: viewModel.distanceText(for: detailPlace),
                            openHoursText: viewModel.detailOpenHoursText(for: detailPlace, now: context.date),
                            activeGradient: viewModel.activePillGradient,
                            activeGlowColor: viewModel.activeMapGlowColor,
                            onFocusTap: {
                                viewModel.handleDetailFocusTap(on: detailPlace)
                            },
                            onClose: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                                    viewModel.closeDetail()
                                }
                            },
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(15)
                } else if let place = viewModel.expiredCardPlace {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        QuickCardView(
                            place: place,
                            snapshot: viewModel.eventSnapshot(for: place, now: context.date),
                            progress: viewModel.quickProgress(for: place, now: context.date),
                            distanceText: viewModel.distanceText(for: place),
                            metaStatusText: viewModel.quickMetaStatusText(for: place, now: context.date),
                            hintText: viewModel.quickHintText(for: place),
                            placeState: viewModel.placeState(for: place.id),
                            stamp: viewModel.stampPresentation(for: place),
                            activeGradient: viewModel.activePillGradient,
                            activeGlowColor: viewModel.activeMapGlowColor,
                            mode: .expired,
                            onClose: {
                                withAnimation(quickCardDismissAnimation) {
                                    viewModel.closeExpiredCard()
                                }
                            },
                            onOpenDetail: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    viewModel.openDetailForCurrentQuickCard()
                                }
                            },
                            onStartRoute: {
                                routeNavigationPlace = place
                            },
                            onExpandDetailBySwipe: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    viewModel.openDetailForCurrentQuickCard()
                                }
                            },
                            onDismissBySwipe: {
                                withAnimation(quickCardDismissAnimation) {
                                    viewModel.closeExpiredCard()
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(14)
                } else if let place = viewModel.quickCardPlace {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        QuickCardView(
                            place: place,
                            snapshot: viewModel.eventSnapshot(for: place, now: context.date),
                            progress: viewModel.quickProgress(for: place, now: context.date),
                            distanceText: viewModel.distanceText(for: place),
                            metaStatusText: viewModel.quickMetaStatusText(for: place, now: context.date),
                            hintText: viewModel.quickHintText(for: place),
                            placeState: viewModel.placeState(for: place.id),
                            stamp: viewModel.stampPresentation(for: place),
                            activeGradient: viewModel.activePillGradient,
                            activeGlowColor: viewModel.activeMapGlowColor,
                            onClose: {
                                withAnimation(quickCardDismissAnimation) {
                                    viewModel.closeQuickCard()
                                }
                            },
                            onOpenDetail: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    viewModel.openDetailForCurrentQuickCard()
                                }
                            },
                            onStartRoute: {
                                routeNavigationPlace = place
                            },
                            onExpandDetailBySwipe: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    viewModel.openDetailForCurrentQuickCard()
                                }
                            },
                            onDismissBySwipe: {
                                withAnimation(quickCardDismissAnimation) {
                                    viewModel.closeQuickCard()
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(14)
                } else if !viewModel.isSideDrawerOpen {
                    TimelineView(.periodic(from: .now, by: 8)) { context in
                        NearbyCarouselView(
                            items: viewModel.nearbyCarouselItems(now: context.date),
                            onSelectPlace: { placeID in
                                viewModel.selectPlaceFromCarousel(placeID: placeID)
                            }
                        )
                    }
                    .padding(.horizontal, -14)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(13)
                }

                if !viewModel.isDetailVisible {
                    topTrailingControls(
                        locationIconColor: locationIconColor,
                        sidebarIconColor: sidebarIconColor
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                    .zIndex(12)
                }

                SideDrawerLayerView(viewModel: viewModel)
                    .zIndex(20)
            }
        }
        .overlay(alignment: .top) {
            if let notice = viewModel.topNotice {
                TopNoticeBubbleView(message: notice.message) {
                    viewModel.dismissTopNotice()
                }
                .padding(.top, 8)
                .padding(.horizontal, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(200)
            }
        }
        .onAppear {
            viewModel.onViewAppear()
            updateLaunchBridgeCacheIfNeeded()
            restartLaunchBridgeAnimationIfNeeded()
        }
        .onDisappear {
            viewModel.onViewDisappear()
            teardownLaunchBridgeAnimation(clearCache: true)
        }
        .onChange(of: viewModel.launchRecommendationBridge?.targetPlaceID) { _, _ in
            updateLaunchBridgeCacheIfNeeded()
            restartLaunchBridgeAnimationIfNeeded()
        }
        .alert(
            item: Binding(
                get: {
                    guard !suppressLocationFallbackAlert else {
                        return nil
                    }
                    return viewModel.locationFallbackNotice
                },
                set: { _ in viewModel.dismissLocationFallbackNotice() }
            )
        ) { notice in
            Alert(
                title: Text(viewModel.locationFallbackAlertTitle),
                message: Text(viewModel.locationFallbackAlertMessage(for: notice)),
                dismissButton: .default(Text(L10n.Common.close)) {
                    viewModel.dismissLocationFallbackNotice()
                }
            )
        }
        .confirmationDialog(
            L10n.QuickCard.navigationChooserTitle,
            isPresented: Binding(
                get: { routeNavigationPlace != nil },
                set: { isPresented in
                    if !isPresented {
                        routeNavigationPlace = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.QuickCard.navigationOptionAppleMaps) {
                if let place = routeNavigationPlace {
                    openAppleMapsNavigation(to: place)
                }
                routeNavigationPlace = nil
            }
            Button(L10n.QuickCard.navigationOptionGoogleMaps) {
                if let place = routeNavigationPlace {
                    openGoogleMapsNavigation(to: place)
                }
                routeNavigationPlace = nil
            }
            Button(L10n.Common.close, role: .cancel) {
                routeNavigationPlace = nil
            }
        } message: {
            if let place = routeNavigationPlace {
                Text(L10n.QuickCard.navigationChooserMessage(place.name))
            }
        }
        .animation(.spring(response: 0.40, dampingFraction: 0.92), value: viewModel.quickCardPlaceID)
        .animation(.spring(response: 0.40, dampingFraction: 0.92), value: viewModel.expiredCardPlaceID)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viewModel.topNotice?.id)
    }

    private func topTrailingControls(locationIconColor: Color, sidebarIconColor: Color) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.closeMarkerActionBubble()
                onOpenCalendar()
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.24, green: 0.40, blue: 0.46))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.66), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color(red: 0.91, green: 0.96, blue: 0.98, opacity: 0.84), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(5)
            .contentShape(Rectangle())
            .accessibilityLabel(L10n.Home.openCalendarA11y)

            Button {
                viewModel.resetToCurrentLocation()
            } label: {
                Image(systemName: "location.fill")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(locationIconColor)
                    .opacity(1)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.66), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color(red: 0.91, green: 0.96, blue: 0.98, opacity: 0.84), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(5)
            .contentShape(Rectangle())
            .accessibilityLabel(L10n.Home.resetLocationA11y)

            Button {
                viewModel.toggleSideDrawerPanel()
            } label: {
                Image("HomeSidebarIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: 19)
                    .foregroundStyle(sidebarIconColor)
                    .opacity(1)
                    .shadow(color: sidebarIconColor.opacity(0.24), radius: 1.2, x: 0, y: 1)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.66), in: Capsule())
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.91, green: 0.96, blue: 0.98, opacity: 0.84), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .accessibilityLabel(L10n.Home.openMenuA11y)
        }
    }

    private func mapCanvas(
        markerEntries: [MapMarkerEntry],
        markerThemeSignature: MarkerThemeSignature,
        markerActiveGlowColor: Color,
        markerActionStyleHanabi: MarkerActionStyle,
        markerActionStyleMatsuri: MarkerActionStyle,
        markerActionStyleFallback: MarkerActionStyle,
        hasVisibleMarkerMenu: Bool,
        locationLogoGradient: LinearGradient
    ) -> some View {
        Map(position: mapPositionBinding) {
            Annotation("CurrentLocation", coordinate: viewModel.currentLocationCoordinate, anchor: .center) {
                CurrentLocationMarkerView(
                    pinGradient: locationLogoGradient,
                    glowColor: viewModel.activeMapGlowColor
                )
                .allowsHitTesting(false)
            }
            .annotationTitles(.hidden)

            if let launchBridge = viewModel.launchRecommendationBridge {
                let bridgeFixedStops = launchBridgeGradientStops.isEmpty
                    ? launchBridgeFixedSchemeStops(for: launchBridge)
                    : launchBridgeGradientStops
                let bridgeBars = launchBridgeVerticalBars(revealProgress: launchBridgeRevealProgress)

                ForEach(bridgeBars) { bar in
                    MapPolyline(coordinates: [bar.baseCoordinate, bar.tipCoordinate])
                        .stroke(
                            launchBridgeBarGlassColor(for: launchBridge, intensity: bar.intensity),
                            style: StrokeStyle(
                                lineWidth: bar.strokeWidth + 0.45,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    MapPolyline(coordinates: [bar.baseCoordinate, bar.tipCoordinate])
                        .stroke(
                            launchBridgeBarCoreColor(
                                from: bridgeFixedStops,
                                progress: bar.trackProgress,
                                intensity: bar.intensity
                            ),
                            style: StrokeStyle(
                                lineWidth: bar.strokeWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
            }

            ForEach(markerEntries) { entry in
                let placeState = viewModel.placeState(for: entry.id)
                let shouldShowDecoration = (entry.isMenuVisible || entry.isSelected) && placeState.isCheckedIn
                Annotation(entry.name, coordinate: entry.coordinate, anchor: .bottom) {
                    MapMarkerAnnotationView(
                        entry: entry,
                        themeSignature: markerThemeSignature,
                        activeGlowColor: markerActiveGlowColor,
                        markerActionStyle: markerActionStyle(
                            for: entry.heType,
                            hanabi: markerActionStyleHanabi,
                            matsuri: markerActionStyleMatsuri,
                            fallback: markerActionStyleFallback
                        ),
                        stamp: entry.isMenuVisible
                        ? viewModel.stampPresentation(for: entry.id, heType: entry.heType)
                        : nil,
                        isDecorationVisible: shouldShowDecoration,
                        isDecorationWhiteBaseEnabled: placeState.isCheckedIn,
                        decoration: shouldShowDecoration
                        ? viewModel.markerDecorationPresentation(for: entry.id, heType: entry.heType)
                        : nil,
                        onFavoriteTap: {
                            viewModel.markAnnotationTapCooldown(0.4)
                            viewModel.toggleFavorite(for: entry.id)
                        },
                        onCheckedInTap: {
                            viewModel.markAnnotationTapCooldown(0.4)
                            viewModel.toggleCheckedIn(for: entry.id)
                        },
                        onTap: {
                            viewModel.tapMarker(placeID: entry.id)
                        }
                    )
                    .equatable()
                    .allowsHitTesting(
                        markerAnnotationAllowsHitTesting(
                            for: entry,
                            hasVisibleMarkerMenu: hasVisibleMarkerMenu
                        )
                    )
                    .zIndex(
                        markerAnnotationZIndex(
                            for: entry,
                            hasVisibleMarkerMenu: hasVisibleMarkerMenu
                        )
                    )
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .preferredColorScheme(.light)
        .id(viewModel.mapViewInstanceID)
        .onMapCameraChange(frequency: .continuous) { context in
            viewModel.handleMapCameraMotion(context.region)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.handleMapCameraChange(context.region)
        }
        .ignoresSafeArea()
        .gesture(
            TapGesture().onEnded {
                viewModel.handleMapBackgroundTap()
            },
            including: .gesture
        )
    }

    private func openAppleMapsNavigation(to place: HePlace) {
        let origin = viewModel.currentLocationCoordinate
        guard var components = URLComponents(string: "http://maps.apple.com/") else {
            return
        }
        components.queryItems = [
            URLQueryItem(name: "saddr", value: "\(origin.latitude),\(origin.longitude)"),
            URLQueryItem(name: "daddr", value: "\(place.coordinate.latitude),\(place.coordinate.longitude)"),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        guard let url = components.url else {
            return
        }
        openURL(url)
    }

    private func openGoogleMapsNavigation(to place: HePlace) {
        let origin = viewModel.currentLocationCoordinate
        guard let googleAppURL = URL(
            string: "comgooglemaps://?saddr=\(origin.latitude),\(origin.longitude)&daddr=\(place.coordinate.latitude),\(place.coordinate.longitude)&directionsmode=driving"
        ) else {
            return
        }
        openURL(googleAppURL) { accepted in
            guard !accepted else {
                return
            }
            guard var components = URLComponents(string: "https://www.google.com/maps/dir/") else {
                return
            }
            components.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "origin", value: "\(origin.latitude),\(origin.longitude)"),
                URLQueryItem(name: "destination", value: "\(place.coordinate.latitude),\(place.coordinate.longitude)"),
                URLQueryItem(name: "travelmode", value: "driving")
            ]
            guard let webURL = components.url else {
                return
            }
            openURL(webURL)
        }
    }

    private var mapAmbientGlowLayer: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let glowRatio = min(max(viewModel.themeGlowRatio, 0.6), 1.8)
            let ambientGlowRatio = min(max(glowRatio - 0.18, 0.6), 1.8)
            let mainSize = min(max(width * (0.84 + ambientGlowRatio * 0.10), 300), 560)
            let haloSize = min(max(width * (0.60 + ambientGlowRatio * 0.10), 230), 450)
            let echoSize = min(max(width * (0.36 + ambientGlowRatio * 0.06), 150), 300)
            let mainOpacity = min(0.56, 0.26 + ambientGlowRatio * 0.16)
            let haloOpacity = min(0.66, 0.30 + ambientGlowRatio * 0.20)
            let echoOpacity = min(0.42, 0.16 + ambientGlowRatio * 0.14)

            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(viewModel.activePillGradient)
                    .frame(width: mainSize, height: mainSize)
                    .blur(radius: 56)
                    .opacity(mainOpacity)
                    .offset(x: width * 0.30, y: 180)

                Circle()
                    .fill(viewModel.activeMapGlowColor)
                    .frame(width: haloSize, height: haloSize)
                    .blur(radius: 48)
                    .opacity(haloOpacity)
                    .offset(x: width * 0.28, y: 160)

                Circle()
                    .fill(viewModel.activeMapGlowColor)
                    .frame(width: echoSize, height: echoSize)
                    .blur(radius: 36)
                    .opacity(echoOpacity)
                    .offset(x: width * 0.20, y: -32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var mapPositionBinding: Binding<MapCameraPosition> {
        Binding(
            get: { viewModel.mapPosition },
            set: { viewModel.updateMapPositionFromInteraction($0) }
        )
    }

    private struct LaunchBridgeVerticalBar: Identifiable {
        let id: Int
        let baseCoordinate: CLLocationCoordinate2D
        var tipCoordinate: CLLocationCoordinate2D
        var intensity: Double
        let strokeWidth: Double
        let trackProgress: Double
    }

    private struct LaunchBridgeVerticalBarTemplate {
        let id: Int
        let baseCoordinate: CLLocationCoordinate2D
        var fullHeightLat: Double
        var baseIntensity: Double
        let strokeWidth: Double
        let trackProgress: Double
    }

    private struct LaunchBridgeCacheKey: Equatable {
        let targetPlaceID: UUID
        let barCount: Int
        let palette: HomeMapViewModel.LaunchRecommendationBridge.Palette
        let trackCount: Int
        let fromLatE6: Int
        let fromLonE6: Int
        let toLatE6: Int
        let toLonE6: Int
        let midLatE6: Int
        let midLonE6: Int
    }

    private struct LaunchBridgeGradientStop {
        let location: Double
        let rgba: (r: Double, g: Double, b: Double, a: Double)
    }

    private func teardownLaunchBridgeAnimation(clearCache: Bool) {
        launchBridgeAnimationGeneration += 1
        launchBridgeRevealTask?.cancel()
        launchBridgeRevealTask = nil
        launchBridgeRevealProgress = 0
        guard clearCache else {
            return
        }
        launchBridgeCacheKey = nil
        launchBridgeBaseBars = []
        launchBridgeGradientStops = []
    }

    private func updateLaunchBridgeCacheIfNeeded() {
        guard let bridge = viewModel.launchRecommendationBridge else {
            launchBridgeCacheKey = nil
            launchBridgeBaseBars = []
            launchBridgeGradientStops = []
            return
        }
        let nextKey = launchBridgeCacheKey(for: bridge)
        guard nextKey != launchBridgeCacheKey else {
            return
        }
        launchBridgeCacheKey = nextKey
        launchBridgeBaseBars = launchBridgeBaseBars(for: bridge)
        launchBridgeGradientStops = launchBridgeFixedSchemeStops(for: bridge)
    }

    private func launchBridgeCacheKey(
        for bridge: HomeMapViewModel.LaunchRecommendationBridge
    ) -> LaunchBridgeCacheKey {
        let track = bridge.trackCoordinates
        let midpoint = track[track.count / 2]
        return LaunchBridgeCacheKey(
            targetPlaceID: bridge.targetPlaceID,
            barCount: bridge.barCount,
            palette: bridge.palette,
            trackCount: track.count,
            fromLatE6: quantizedE6(bridge.fromCoordinate.latitude),
            fromLonE6: quantizedE6(bridge.fromCoordinate.longitude),
            toLatE6: quantizedE6(bridge.toCoordinate.latitude),
            toLonE6: quantizedE6(bridge.toCoordinate.longitude),
            midLatE6: quantizedE6(midpoint.latitude),
            midLonE6: quantizedE6(midpoint.longitude)
        )
    }

    private func quantizedE6(_ value: Double) -> Int {
        Int((value * 1_000_000).rounded())
    }

    private func restartLaunchBridgeAnimationIfNeeded() {
        guard viewModel.launchRecommendationBridge != nil else {
            teardownLaunchBridgeAnimation(clearCache: true)
            return
        }
        launchBridgeAnimationGeneration += 1
        let generation = launchBridgeAnimationGeneration
        launchBridgeRevealTask?.cancel()
        launchBridgeRevealTask = nil
        launchBridgeRevealProgress = 0
        launchBridgeRevealTask = Task { @MainActor in
            let startedAt = Date()
            let duration: TimeInterval = 3.0
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                let raw = min(max(elapsed / duration, 0), 1)
                let eased = raw * raw * (3 - 2 * raw)
                launchBridgeRevealProgress = eased
                if raw >= 1 {
                    break
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            if launchBridgeAnimationGeneration == generation {
                launchBridgeRevealTask = nil
            }
        }
    }

    private func launchBridgeBarGlassColor(
        for bridge: HomeMapViewModel.LaunchRecommendationBridge,
        intensity: Double
    ) -> Color {
        switch bridge.palette {
        case .theme:
            return Color.white.opacity(0.22 + 0.18 * intensity)
        case .subdued:
            return Color.white.opacity(0.18 + 0.16 * intensity)
        }
    }

    private func launchBridgeFixedSchemeStops(
        for _: HomeMapViewModel.LaunchRecommendationBridge
    ) -> [LaunchBridgeGradientStop] {
        let fixedScheme = "ocean" // Side drawer selectable theme list's 2nd scheme.
        let colors = TsugieVisuals.pillGradientColors(
            scheme: fixedScheme,
            alphaRatio: 1,
            saturationRatio: 1
        )
        guard !colors.isEmpty else {
            return [
                LaunchBridgeGradientStop(location: 0, rgba: (1, 1, 1, 1)),
                LaunchBridgeGradientStop(location: 1, rgba: (1, 1, 1, 1))
            ]
        }
        if colors.count == 1, let first = colors.first {
            let rgba = launchBridgeRGBA(from: first)
            return [
                LaunchBridgeGradientStop(location: 0, rgba: rgba),
                LaunchBridgeGradientStop(location: 1, rgba: rgba)
            ]
        }

        let denominator = max(colors.count - 1, 1)
        return colors.enumerated().map { index, color in
            LaunchBridgeGradientStop(
                location: Double(index) / Double(denominator),
                rgba: launchBridgeRGBA(from: color)
            )
        }
    }

    private func launchBridgeBarCoreColor(
        from stops: [LaunchBridgeGradientStop],
        progress: Double,
        intensity: Double
    ) -> Color {
        guard stops.count >= 2 else {
            return .white.opacity(0.9)
        }
        let clampedProgress = min(max(progress, 0), 1)
        var lower = stops[0]
        var upper = stops[stops.count - 1]
        for idx in 1..<stops.count {
            let candidate = stops[idx]
            if candidate.location >= clampedProgress {
                lower = stops[idx - 1]
                upper = candidate
                break
            }
        }
        let span = max(upper.location - lower.location, 0.0001)
        let localT = min(max((clampedProgress - lower.location) / span, 0), 1)
        let red = lower.rgba.r + (upper.rgba.r - lower.rgba.r) * localT
        let green = lower.rgba.g + (upper.rgba.g - lower.rgba.g) * localT
        let blue = lower.rgba.b + (upper.rgba.b - lower.rgba.b) * localT
        let baseAlpha = lower.rgba.a + (upper.rgba.a - lower.rgba.a) * localT
        let alpha = min(max(baseAlpha * (0.82 + 0.18 * intensity), 0), 1)
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    private func launchBridgeRGBA(from color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Double(red), Double(green), Double(blue), Double(alpha))
        }
        var white: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            let channel = Double(white)
            return (channel, channel, channel, Double(alpha))
        }
        return (1, 1, 1, 1)
    }

    private func launchBridgeBaseBars(
        for bridge: HomeMapViewModel.LaunchRecommendationBridge
    ) -> [LaunchBridgeVerticalBarTemplate] {
        let track = bridge.trackCoordinates
        let visibleTrack = track
        guard visibleTrack.count >= 2 else {
            return []
        }

        let preferredBarCount = min(max(10, bridge.barCount), 37)
        let visualBarCount = min(max(12, preferredBarCount - 11), 26)
        guard visualBarCount > 0 else {
            return []
        }
        let maxIndex = visibleTrack.count - 1
        var cumulativeDistanceKm: [Double] = Array(repeating: 0, count: visibleTrack.count)
        if visibleTrack.count >= 2 {
            for idx in 1..<visibleTrack.count {
                cumulativeDistanceKm[idx] = cumulativeDistanceKm[idx - 1] +
                    bridgeDistanceKm(from: visibleTrack[idx - 1], to: visibleTrack[idx])
            }
        }
        let totalTrackDistanceKm = max(cumulativeDistanceKm.last ?? 0, 0.0001)
        var segmentCursor = 0
        let sigma = 0.22
        let edgeGaussian = Foundation.exp(-0.5 * Foundation.pow(0.5 / sigma, 2))

        var bars: [LaunchBridgeVerticalBarTemplate] = []
        bars.reserveCapacity(visualBarCount)

        for index in 0..<visualBarCount {
            let t = visualBarCount <= 1 ? 0 : Double(index) / Double(visualBarCount - 1)
            let targetDistanceKm = totalTrackDistanceKm * t
            while segmentCursor < maxIndex && cumulativeDistanceKm[segmentCursor + 1] < targetDistanceKm {
                segmentCursor += 1
            }
            let segmentStart = visibleTrack[segmentCursor]
            let segmentEnd = visibleTrack[min(segmentCursor + 1, maxIndex)]
            let segmentStartDistance = cumulativeDistanceKm[segmentCursor]
            let segmentEndDistance = cumulativeDistanceKm[min(segmentCursor + 1, maxIndex)]
            let segmentLength = max(segmentEndDistance - segmentStartDistance, 0.000001)
            let segmentProgress = min(max((targetDistanceKm - segmentStartDistance) / segmentLength, 0), 1)
            let baseCoordinate = CLLocationCoordinate2D(
                latitude: segmentStart.latitude + (segmentEnd.latitude - segmentStart.latitude) * segmentProgress,
                longitude: segmentStart.longitude + (segmentEnd.longitude - segmentStart.longitude) * segmentProgress
            )

            let z = (t - 0.5) / sigma
            let gaussianHeight = Foundation.exp(-0.5 * z * z)
            let normalizedHeight = (gaussianHeight - edgeGaussian) / max(1 - edgeGaussian, 0.0001)
            let shapedHeight = min(max(0.14 + normalizedHeight * 0.86, 0), 1)
            let fullBarHeightKm = 0.026 + 0.165 * shapedHeight
            let fullBarHeightLat = fullBarHeightKm / 111.0

            bars.append(
                LaunchBridgeVerticalBarTemplate(
                    id: index,
                    baseCoordinate: baseCoordinate,
                    fullHeightLat: fullBarHeightLat,
                    baseIntensity: min(1, 0.20 + 0.80 * shapedHeight),
                    strokeWidth: 4.10 + 1.35 * shapedHeight,
                    trackProgress: t
                )
            )
        }

        guard bars.count >= 4 else {
            return bars
        }

        let startThirdIndex = 2
        let endFirstIndex = bars.count - 1
        let startThirdHeightLat = max(bars[startThirdIndex].fullHeightLat, 0)
        let endFirstHeightLat = max(bars[endFirstIndex].fullHeightLat, 0)

        if endFirstHeightLat <= startThirdHeightLat {
            bars[endFirstIndex].fullHeightLat = startThirdHeightLat * 1.10
            bars[endFirstIndex].baseIntensity = min(
                1,
                max(bars[endFirstIndex].baseIntensity, bars[startThirdIndex].baseIntensity + 0.08)
            )
        }

        return bars
    }

    private func launchBridgeVerticalBars(
        revealProgress: Double
    ) -> [LaunchBridgeVerticalBar] {
        guard !launchBridgeBaseBars.isEmpty else {
            return []
        }
        let clampedReveal = min(max(revealProgress, 0), 1)
        let visualBarCount = launchBridgeBaseBars.count
        let revealInBars = clampedReveal * Double(visualBarCount)
        let fullyGrownCount = min(max(Int(revealInBars.rounded(.down)), 0), max(visualBarCount - 1, 0))
        let activeBarFractionRaw = revealInBars - Double(fullyGrownCount)
        let activeBarGrowth = activeBarFractionRaw * activeBarFractionRaw * (3 - 2 * activeBarFractionRaw)

        var bars: [LaunchBridgeVerticalBar] = []
        bars.reserveCapacity(visualBarCount)

        for template in launchBridgeBaseBars {
            let growth: Double
            if template.id < fullyGrownCount {
                growth = 1
            } else if template.id == fullyGrownCount {
                growth = activeBarGrowth
            } else {
                continue
            }

            let tipCoordinate = CLLocationCoordinate2D(
                latitude: min(template.baseCoordinate.latitude + template.fullHeightLat * growth, 85),
                longitude: template.baseCoordinate.longitude
            )

            bars.append(
                LaunchBridgeVerticalBar(
                    id: template.id,
                    baseCoordinate: template.baseCoordinate,
                    tipCoordinate: tipCoordinate,
                    intensity: min(1, template.baseIntensity * (0.35 + 0.65 * growth)),
                    strokeWidth: template.strokeWidth,
                    trackProgress: template.trackProgress
                )
            )
        }

        return bars
    }

    private func bridgeDistanceKm(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let earthRadiusKm = 6_371.0
        let lat1 = lhs.latitude * .pi / 180
        let lon1 = lhs.longitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let lon2 = rhs.longitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1
        let a = Foundation.sin(dLat / 2) * Foundation.sin(dLat / 2) +
            Foundation.cos(lat1) * Foundation.cos(lat2) *
            Foundation.sin(dLon / 2) * Foundation.sin(dLon / 2)
        let c = 2 * Foundation.atan2(Foundation.sqrt(a), Foundation.sqrt(max(1 - a, 0)))
        return earthRadiusKm * c
    }

    private func markerActionStyle(
        for type: HeType,
        hanabi: MarkerActionStyle,
        matsuri: MarkerActionStyle,
        fallback: MarkerActionStyle
    ) -> MarkerActionStyle {
        switch type {
        case .hanabi:
            return hanabi
        case .matsuri:
            return matsuri
        default:
            return fallback
        }
    }

    private func markerAnnotationZIndex(
        for entry: MapMarkerEntry,
        hasVisibleMarkerMenu: Bool
    ) -> Double {
        if entry.isMenuVisible {
            return 1_000
        }
        if hasVisibleMarkerMenu {
            if entry.isSelected {
                return 900
            }
            if entry.isTemporary {
                return -100
            }
            if entry.isCluster {
                return -110
            }
            return -120
        }
        if entry.isTemporary {
            return 21
        }
        if entry.isSelected {
            return 20
        }
        if entry.isCluster {
            return 10
        }
        return 0
    }

    private func markerAnnotationAllowsHitTesting(
        for _: MapMarkerEntry,
        hasVisibleMarkerMenu _: Bool
    ) -> Bool {
        true
    }
}

struct MapMarkerEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let heType: HeType
    let isEnded: Bool
    let isSelected: Bool
    let isCluster: Bool
    let clusterCount: Int
    let isTemporary: Bool
    let isMenuVisible: Bool
    let menuPlaceState: PlaceState?

    static func == (lhs: MapMarkerEntry, rhs: MapMarkerEntry) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.heType == rhs.heType &&
        lhs.isEnded == rhs.isEnded &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isCluster == rhs.isCluster &&
        lhs.clusterCount == rhs.clusterCount &&
        lhs.isTemporary == rhs.isTemporary &&
        lhs.isMenuVisible == rhs.isMenuVisible &&
        lhs.menuPlaceState == rhs.menuPlaceState &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

private struct MapMarkerAnnotationView: View, Equatable {
    let entry: MapMarkerEntry
    let themeSignature: MarkerThemeSignature
    let activeGlowColor: Color
    let markerActionStyle: MarkerActionStyle
    let stamp: PlaceStampPresentation?
    let isDecorationVisible: Bool
    let isDecorationWhiteBaseEnabled: Bool
    let decoration: PlaceDecorationPresentation?
    let onFavoriteTap: () -> Void
    let onCheckedInTap: () -> Void
    let onTap: () -> Void

    static func == (lhs: MapMarkerAnnotationView, rhs: MapMarkerAnnotationView) -> Bool {
        lhs.entry == rhs.entry &&
        lhs.themeSignature == rhs.themeSignature &&
        lhs.isDecorationVisible == rhs.isDecorationVisible &&
        lhs.isDecorationWhiteBaseEnabled == rhs.isDecorationWhiteBaseEnabled &&
        lhs.stamp == rhs.stamp &&
        lhs.decoration == rhs.decoration
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isDecorationVisible, let decoration {
                Button(action: onCheckedInTap) {
                    MarkerDecorationBadgeView(
                        decoration: decoration,
                        useWhiteBase: isDecorationWhiteBaseEnabled
                    )
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Marker.checkedInA11y)
                .offset(x: 14, y: -10)
                .zIndex(5)
            }

            MarkerBubbleView(
                placeName: entry.name,
                heType: entry.heType,
                isEnded: entry.isEnded,
                isSelected: entry.isSelected,
                clusterCount: entry.clusterCount,
                activeGlowColor: activeGlowColor,
                onTap: onTap
            )
            .allowsHitTesting(true)
            .zIndex(1)

            if entry.isMenuVisible {
                MarkerActionBubbleView(
                    isVisible: true,
                    placeState: entry.menuPlaceState ?? PlaceState(),
                    stamp: stamp,
                    activeGradient: markerActionStyle.gradient,
                    activeGlowColor: markerActionStyle.glowColor,
                    onFavoriteTap: onFavoriteTap,
                    onCheckedInTap: onCheckedInTap
                )
                .offset(y: -14)
                .allowsHitTesting(true)
                .zIndex(4)
            }
        }
    }
}

private struct MarkerThemeSignature: Equatable {
    let scheme: String
    let alphaRatio: Double
    let saturationRatio: Double
    let glowRatio: Double
}

private struct MarkerActionStyle {
    let gradient: LinearGradient
    let glowColor: Color
}

private struct MarkerDecorationBadgeView: View {
    let decoration: PlaceDecorationPresentation
    let useWhiteBase: Bool

    var body: some View {
        ZStack {
            if useWhiteBase {
                StampWhiteBaseImageView(
                    resourceName: decoration.resourceName,
                    maxPixelSize: 256
                )
            }
            ImmediateStampImageView(
                resourceName: decoration.resourceName,
                maxPixelSize: 256
            )
        }
        .scaledToFit()
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }
}

private struct CurrentLocationMarkerView: View {
    let pinGradient: LinearGradient
    let glowColor: Color

    var body: some View {
        ZStack {
            // Use the same logo shape as shadow base to create a stronger 3D lift.
            Image("CurrentLocationPinIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(glowColor)
                .opacity(0.52)
                .offset(x: 1.8, y: 2.8)
                .blur(radius: 1.9)

            Image("CurrentLocationPinIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(.black)
                .opacity(0.18)
                .offset(x: 0.6, y: 2.2)
                .blur(radius: 1.4)

            Image("CurrentLocationPinIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(pinGradient)
                .shadow(color: glowColor.opacity(0.34), radius: 3.6, x: 0, y: 1.4)
                .overlay {
                    Image("CurrentLocationPinIcon")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.62),
                                    .white.opacity(0.08),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(0.74)
                        .blendMode(.screen)
                }
        }
        .frame(width: 40, height: 40)
        .saturation(1.65)
        .shadow(color: glowColor.opacity(0.44), radius: 10, x: 0, y: 2)
        .shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 3)
        .accessibilityHidden(true)
    }
}

private struct TopNoticeBubbleView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.86, green: 0.42, blue: 0.20))
                    .accessibilityHidden(true)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.24))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.92), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(red: 0.92, green: 0.95, blue: 0.98, opacity: 0.95), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel(message)
        .accessibilityHint(L10n.Common.close)
    }
}
