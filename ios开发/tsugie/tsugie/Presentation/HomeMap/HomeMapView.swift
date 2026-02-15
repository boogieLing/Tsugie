import MapKit
import SwiftUI

struct HomeMapView: View {
    @ObservedObject var viewModel: HomeMapViewModel
    let onOpenCalendar: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
                Map(position: $viewModel.mapPosition) {
                    ForEach(viewModel.mapPlaces()) { place in
                        Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                            let isMenuVisible = viewModel.markerActionPlaceID == place.id && !viewModel.isDetailVisible

                            ZStack(alignment: .bottom) {
                                MarkerActionBubbleView(
                                    isVisible: isMenuVisible,
                                    placeState: viewModel.placeState(for: place.id),
                                    activeGradient: TsugieVisuals.markerGradient(for: place.heType),
                                    activeGlowColor: TsugieVisuals.markerGlowColor(for: place.heType),
                                    onFavoriteTap: {
                                        viewModel.markAnnotationTapCooldown()
                                        viewModel.toggleFavorite(for: place.id)
                                    },
                                    onCheckedInTap: {
                                        viewModel.markAnnotationTapCooldown()
                                        viewModel.toggleCheckedIn(for: place.id)
                                    }
                                )
                                .offset(y: -24)
                                .allowsHitTesting(isMenuVisible)

                                MarkerBubbleView(
                                    placeName: place.name,
                                    heType: place.heType,
                                    isSelected: viewModel.selectedPlaceID == place.id,
                                    activeGradient: viewModel.activePillGradient,
                                    activeGlowColor: viewModel.activeMapGlowColor,
                                    onTap: {
                                        viewModel.tapMarker(placeID: place.id)
                                    }
                                )
                            }
                            .frame(width: 220, height: 170, alignment: .bottom)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.handleMapBackgroundTap()
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        viewModel.handleMapBackgroundTap()
                    }
                )

                mapAmbientGlowLayer

                if let detailPlace = viewModel.detailPlace {
                    DetailPanelView(
                        place: detailPlace,
                        snapshot: viewModel.eventSnapshot(for: detailPlace),
                        placeState: viewModel.placeState(for: detailPlace.id),
                        distanceText: viewModel.distanceText(for: detailPlace),
                        openHoursText: viewModel.detailOpenHoursText(for: detailPlace),
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(15)
                } else if let place = viewModel.quickCardPlace {
                    QuickCardView(
                        place: place,
                        snapshot: viewModel.eventSnapshot(for: place),
                        progress: viewModel.quickProgress(for: place),
                        metaText: viewModel.quickMetaText(for: place),
                        hintText: viewModel.quickHintText(for: place),
                        placeState: viewModel.placeState(for: place.id),
                        activeGradient: viewModel.activePillGradient,
                        activeGlowColor: viewModel.activeMapGlowColor,
                        onClose: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                viewModel.closeQuickCard()
                            }
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !viewModel.isSideDrawerOpen {
                    NearbyCarouselView(
                        viewModel: viewModel,
                        onSelectPlace: { placeID in
                            if let place = viewModel.place(for: placeID) {
                                viewModel.focusForBottomCard(on: place)
                            }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                viewModel.openQuickCard(placeID: placeID, keepMarkerActions: true)
                            }
                        }
                    )
                    .padding(.horizontal, -14)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                SideDrawerLayerView(viewModel: viewModel)
                    .zIndex(20)
        }
        .overlay(alignment: .topTrailing) {
            if !viewModel.isDetailVisible && !viewModel.isSideDrawerOpen {
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
}
