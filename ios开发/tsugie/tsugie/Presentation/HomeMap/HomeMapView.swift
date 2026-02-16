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

        ZStack(alignment: .bottom) {
            if viewModel.isCalendarPresented {
                Color.clear
                    .ignoresSafeArea()
            } else {
                Map(position: mapPositionBinding) {
                    ForEach(viewModel.mapMarkerEntries()) { entry in
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
                                onFavoriteTap: {
                                    viewModel.markAnnotationTapCooldown()
                                    viewModel.toggleFavorite(for: entry.id)
                                },
                                onCheckedInTap: {
                                    viewModel.markAnnotationTapCooldown()
                                    viewModel.toggleCheckedIn(for: entry.id)
                                },
                                onTap: {
                                    viewModel.tapMarker(placeID: entry.id)
                                }
                            )
                            .equatable()
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .id(viewModel.mapViewInstanceID)
                .onMapCameraChange(frequency: .onEnd) { context in
                    viewModel.handleMapCameraChange(context.region)
                }
                .ignoresSafeArea()
                .simultaneousGesture(TapGesture().onEnded {
                    viewModel.handleMapBackgroundTap()
                })

                mapAmbientGlowLayer

                if let detailPlace = viewModel.detailPlace {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        DetailPanelView(
                            place: detailPlace,
                            snapshot: viewModel.eventSnapshot(for: detailPlace, now: context.date),
                            placeState: viewModel.placeState(for: detailPlace.id),
                            distanceText: viewModel.distanceText(for: detailPlace),
                            openHoursText: viewModel.detailOpenHoursText(for: detailPlace, now: context.date),
                            activeGradient: viewModel.activePillGradient,
                            activeGlowColor: viewModel.activeMapGlowColor,
                            onFocusTap: {
                                viewModel.focus(on: detailPlace)
                            },
                            onClose: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                                    viewModel.closeDetail()
                                }
                            },
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(15)
                } else if let place = viewModel.quickCardPlace {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        QuickCardView(
                            place: place,
                            snapshot: viewModel.eventSnapshot(for: place, now: context.date),
                            progress: viewModel.quickProgress(for: place, now: context.date),
                            metaText: viewModel.quickMetaText(for: place, now: context.date),
                            hintText: viewModel.quickHintText(for: place),
                            placeState: viewModel.placeState(for: place.id),
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
                            activeGradient: viewModel.activePillGradient,
                            activeGlowColor: viewModel.activeMapGlowColor,
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.18, green: 0.38, blue: 0.47))
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
                        Text("(ᵔ◡ᵔ)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.29, green: 0.40, blue: 0.44))
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
}

struct MapMarkerEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let heType: HeType
    let isSelected: Bool
    let isMenuVisible: Bool
    let menuPlaceState: PlaceState?

    static func == (lhs: MapMarkerEntry, rhs: MapMarkerEntry) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.heType == rhs.heType &&
        lhs.isSelected == rhs.isSelected &&
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
    let onFavoriteTap: () -> Void
    let onCheckedInTap: () -> Void
    let onTap: () -> Void

    static func == (lhs: MapMarkerAnnotationView, rhs: MapMarkerAnnotationView) -> Bool {
        lhs.entry == rhs.entry &&
        lhs.themeSignature == rhs.themeSignature
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MarkerActionBubbleView(
                isVisible: entry.isMenuVisible,
                placeState: entry.menuPlaceState ?? PlaceState(),
                activeGradient: markerActionStyle.gradient,
                activeGlowColor: markerActionStyle.glowColor,
                onFavoriteTap: onFavoriteTap,
                onCheckedInTap: onCheckedInTap
            )
            .offset(y: -14)
            .allowsHitTesting(entry.isMenuVisible)

            MarkerBubbleView(
                placeName: entry.name,
                heType: entry.heType,
                isSelected: entry.isSelected,
                activeGradient: activeGradient,
                activeGlowColor: activeGlowColor,
                onTap: onTap
            )
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
