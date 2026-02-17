import MapKit
import SwiftUI

struct HomeMapView: View {
    @ObservedObject var viewModel: HomeMapViewModel
    let onOpenCalendar: () -> Void

    var body: some View {
        let markerThemeSignature = MarkerThemeSignature(
            scheme: viewModel.selectedThemeScheme,
            alphaRatio: viewModel.themeAlphaRatio,
            saturationRatio: viewModel.themeSaturationRatio,
            glowRatio: viewModel.themeGlowRatio
        )
        let markerActiveGradient = viewModel.activePillGradient
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
                Map(position: mapPositionBinding) {
                    Annotation("CurrentLocation", coordinate: viewModel.currentLocationCoordinate, anchor: .center) {
                        CurrentLocationMarkerView(
                            pinGradient: locationLogoGradient,
                            glowColor: viewModel.activeMapGlowColor
                        )
                            .allowsHitTesting(false)
                    }
                    .annotationTitles(.hidden)

                    ForEach(viewModel.mapMarkerEntries()) { entry in
                        let placeState = viewModel.placeState(for: entry.id)
                        Annotation(entry.name, coordinate: entry.coordinate, anchor: .bottom) {
                            MapMarkerAnnotationView(
                                entry: entry,
                                themeSignature: markerThemeSignature,
                                activeGradient: markerActiveGradient,
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
                                isDecorationVisible: entry.isSelected && placeState.isCheckedIn,
                                isDecorationWhiteBaseEnabled: placeState.isCheckedIn,
                                decoration: (entry.isSelected && placeState.isCheckedIn)
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
                            .zIndex(markerAnnotationZIndex(for: entry))
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .id(viewModel.mapViewInstanceID)
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

                mapAmbientGlowLayer

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
                            metaText: viewModel.quickMetaText(for: place, now: context.date),
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
                            metaText: viewModel.quickMetaText(for: place, now: context.date),
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
                    TimelineView(.periodic(from: .now, by: 1)) { context in
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

                SideDrawerLayerView(viewModel: viewModel)
                    .zIndex(20)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !viewModel.isCalendarPresented && !viewModel.isDetailVisible && !viewModel.isSideDrawerOpen {
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
                    .accessibilityLabel(L10n.Home.openMenuA11y)
                }
                .padding(.top, 14)
                .padding(.trailing, 14)
            }
        }
        .onAppear {
            viewModel.onViewAppear()
        }
        .onDisappear {
            viewModel.onViewDisappear()
        }
        .animation(.spring(response: 0.40, dampingFraction: 0.92), value: viewModel.quickCardPlaceID)
        .animation(.spring(response: 0.40, dampingFraction: 0.92), value: viewModel.expiredCardPlaceID)
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

    private func markerAnnotationZIndex(for entry: MapMarkerEntry) -> Double {
        if entry.isMenuVisible {
            return 30
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
}

struct MapMarkerEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let heType: HeType
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
    let activeGradient: LinearGradient
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
            MarkerDecorationOverlayView(
                isPresented: isDecorationVisible,
                decoration: decoration,
                useWhiteBase: isDecorationWhiteBaseEnabled,
                onTap: onCheckedInTap
            )
            .offset(x: 14, y: -10)
            .zIndex(0)

            MarkerBubbleView(
                placeName: entry.name,
                heType: entry.heType,
                isSelected: entry.isSelected,
                clusterCount: entry.clusterCount,
                activeGradient: activeGradient,
                activeGlowColor: activeGlowColor,
                onTap: onTap
            )
            .allowsHitTesting(!entry.isMenuVisible)
            .zIndex(1)

            MarkerActionBubbleView(
                isVisible: entry.isMenuVisible,
                placeState: entry.menuPlaceState ?? PlaceState(),
                stamp: stamp,
                activeGradient: markerActionStyle.gradient,
                activeGlowColor: markerActionStyle.glowColor,
                onFavoriteTap: onFavoriteTap,
                onCheckedInTap: onCheckedInTap
            )
            .offset(y: -14)
            .allowsHitTesting(entry.isMenuVisible)
            .zIndex(2)
        }
        .frame(width: 220, height: 170, alignment: .bottom)
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
        Group {
            if decoration.isAssetCatalog {
                Image(decoration.resourceName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                if useWhiteBase {
                    ZStack {
                        StampWhiteBaseImageView(
                            resourceName: decoration.resourceName,
                            maxPixelSize: 256
                        )
                        ImmediateStampImageView(
                            resourceName: decoration.resourceName,
                            maxPixelSize: 256
                        )
                    }
                } else {
                    ImmediateStampImageView(
                        resourceName: decoration.resourceName,
                        maxPixelSize: 256
                    )
                }
            }
        }
        .scaledToFit()
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }
}

private struct MarkerDecorationOverlayView: View {
    let isPresented: Bool
    let decoration: PlaceDecorationPresentation?
    let useWhiteBase: Bool
    let onTap: () -> Void

    @State private var displayedDecoration: PlaceDecorationPresentation?
    @State private var progress: CGFloat = 0
    @State private var pendingHide: DispatchWorkItem?

    private let insertAnimation = Animation.spring(response: 0.46, dampingFraction: 0.76)
    private let removeAnimation = Animation.easeInOut(duration: 0.32)
    private let removeDuration: TimeInterval = 0.32

    var body: some View {
        Group {
            if let displayedDecoration {
                Button(action: onTap) {
                    MarkerDecorationBadgeView(
                        decoration: displayedDecoration,
                        useWhiteBase: useWhiteBase
                    )
                    .modifier(MarkerDecorationPhaseModifier(progress: progress))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Marker.checkedInA11y)
            }
        }
        .onAppear {
            syncAnimation()
        }
        .onChange(of: isPresented) { _, _ in
            syncAnimation()
        }
        .onChange(of: decoration?.resourceName) { _, _ in
            syncAnimation()
        }
        .onDisappear {
            pendingHide?.cancel()
            pendingHide = nil
            displayedDecoration = nil
            progress = 0
        }
    }

    private func syncAnimation() {
        pendingHide?.cancel()
        pendingHide = nil

        if isPresented, let decoration {
            displayedDecoration = decoration
            progress = 0
            DispatchQueue.main.async {
                withAnimation(insertAnimation) {
                    progress = 1
                }
            }
            return
        }

        guard displayedDecoration != nil else {
            return
        }

        withAnimation(removeAnimation) {
            progress = 0
        }
        let hideWorkItem = DispatchWorkItem {
            displayedDecoration = nil
        }
        pendingHide = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + removeDuration, execute: hideWorkItem)
    }
}

private struct MarkerDecorationPhaseModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        let clamped = min(max(progress, 0), 1)
        let scale = 0.24 + (0.76 * clamped)
        let rotation = -112 * (1 - clamped)
        let xOffset = -14 * (1 - clamped)
        let yOffset = 12 * (1 - clamped)

        content
            .scaleEffect(scale, anchor: .bottomLeading)
            .rotationEffect(.degrees(Double(rotation)), anchor: .bottomLeading)
            .offset(x: xOffset, y: yOffset)
            .opacity(clamped)
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
