import MapKit
import SwiftUI

struct HomeMapView: View {
    @ObservedObject var viewModel: HomeMapViewModel
    let onOpenCalendar: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
                Map(position: $viewModel.mapPosition) {
                    ForEach(viewModel.places) { place in
                        Annotation(place.name, coordinate: place.coordinate) {
                            VStack(spacing: 6) {
                                if viewModel.markerActionPlaceID == place.id, !viewModel.isDetailVisible {
                                    MarkerActionBubbleView(
                                        placeName: place.name,
                                        placeState: viewModel.placeState(for: place.id),
                                        activeGradient: viewModel.activePillGradient,
                                        activeGlowColor: viewModel.activeMapGlowColor,
                                        onFavoriteTap: {
                                            viewModel.toggleFavorite(for: place.id)
                                        },
                                        onQuickTap: {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                                viewModel.openQuickCard(placeID: place.id)
                                            }
                                        },
                                        onCheckedInTap: {
                                            viewModel.toggleCheckedIn(for: place.id)
                                        }
                                    )
                                }

                                MarkerBubbleView(
                                    placeName: place.name,
                                    heType: place.heType,
                                    isSelected: viewModel.selectedPlaceID == place.id,
                                    placeState: viewModel.placeState(for: place.id),
                                    activeGradient: viewModel.activePillGradient,
                                    activeGlowColor: viewModel.activeMapGlowColor,
                                    onTap: {
                                        viewModel.tapMarker(placeID: place.id)
                                    }
                                )
                            }
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .ignoresSafeArea()
                .onTapGesture {
                    if viewModel.isSideDrawerOpen {
                        viewModel.closeSideDrawerPanel()
                    }
                    viewModel.closeMarkerActionBubble()
                }

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
                                viewModel.openQuickCard(placeID: placeID)
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
                        Text(L10n.Home.calendarButton)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.24, green: 0.40, blue: 0.46))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.58), in: Capsule())
                            .overlay(Capsule().stroke(Color(red: 0.84, green: 0.92, blue: 0.94, opacity: 0.9), lineWidth: 1))
                            .tsugieActiveGlow(
                                isActive: true,
                                glowGradient: viewModel.activePillGradient,
                                glowColor: viewModel.activeMapGlowColor,
                                cornerRadius: 999,
                                blurRadius: 8,
                                glowOpacity: 0.78,
                                scale: 1.02,
                                primaryOpacity: 0.66,
                                primaryRadius: 12,
                                primaryYOffset: 4,
                                secondaryOpacity: 0.34,
                                secondaryRadius: 20,
                                secondaryYOffset: 8
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Home.openCalendarA11y)

                    Button {
                        viewModel.resetToCurrentLocation()
                    } label: {
                        Text("⌖")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.18, green: 0.38, blue: 0.47))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.52), in: Circle())
                            .overlay(Circle().stroke(Color(red: 0.84, green: 0.92, blue: 0.94, opacity: 0.95), lineWidth: 1))
                            .background(
                                Circle()
                                    .fill(viewModel.activePillGradient)
                                    .blur(radius: 11)
                                    .opacity(0.44)
                                    .scaleEffect(1.03)
                            )
                            .shadow(color: viewModel.activeMapGlowColor.opacity(0.36), radius: 14, x: 0, y: 4)
                            .shadow(color: viewModel.activeMapGlowColor.opacity(0.19), radius: 24, x: 0, y: 9)
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
                            .background(Color.white.opacity(0.52), in: Capsule())
                            .overlay(Capsule().stroke(Color(red: 0.84, green: 0.92, blue: 0.94, opacity: 0.9), lineWidth: 1))
                            .tsugieActiveGlow(
                                isActive: true,
                                glowGradient: viewModel.activePillGradient,
                                glowColor: viewModel.activeMapGlowColor,
                                cornerRadius: 999,
                                blurRadius: 8,
                                glowOpacity: 0.78,
                                scale: 1.02,
                                primaryOpacity: 0.66,
                                primaryRadius: 12,
                                primaryYOffset: 4,
                                secondaryOpacity: 0.34,
                                secondaryRadius: 20,
                                secondaryYOffset: 8
                            )
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
            let mainSize = min(max(width * (0.84 + glowRatio * 0.10), 300), 560)
            let haloSize = min(max(width * (0.60 + glowRatio * 0.10), 230), 450)
            let echoSize = min(max(width * (0.36 + glowRatio * 0.06), 150), 300)
            let mainOpacity = min(0.56, 0.26 + glowRatio * 0.16)
            let haloOpacity = min(0.66, 0.30 + glowRatio * 0.20)
            let echoOpacity = min(0.42, 0.16 + glowRatio * 0.14)

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
