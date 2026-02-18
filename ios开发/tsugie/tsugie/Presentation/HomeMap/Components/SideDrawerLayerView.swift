import SwiftUI
import UIKit

struct SideDrawerLayerView: View {
    @ObservedObject var viewModel: HomeMapViewModel
    @State private var favoriteSubtitle = L10n.SideDrawer.favoritesSubtitle
    private let drawerItemFillColor = Color.white
    private let drawerItemBorderColor = Color(red: 0.84, green: 0.92, blue: 0.95)
    private let languageOptions: [(code: String, label: String)] = [
        ("ja", "日"),
        ("zh-Hans", "中"),
        ("en", "EN")
    ]

    var body: some View {
        GeometryReader { proxy in
            let sideWidth = min(proxy.size.width * 0.70, 266)
            let favoriteWidth = min(proxy.size.width * 0.80, 302)
            let isLayerOpen = viewModel.isSideDrawerOpen || viewModel.isFavoriteDrawerOpen
            let topSafeInset = max(proxy.safeAreaInsets.top, 0)

            ZStack {
                Button(action: viewModel.closeSideDrawerBackdrop) {
                    ZStack {
                        Color(
                            red: 0.10,
                            green: 0.20,
                            blue: 0.27,
                            opacity: viewModel.isFavoriteDrawerOpen ? 0.16 : 0.10
                        )
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.54)
                    }
                    .opacity(isLayerOpen ? 1 : 0)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.24), value: isLayerOpen)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isLayerOpen)
                .zIndex(viewModel.isFavoriteDrawerOpen ? 5 : 3)

                favoriteDrawer(width: favoriteWidth)
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .zIndex(viewModel.isFavoriteDrawerOpen ? 6 : 4)

                sideDrawer(width: sideWidth)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .zIndex(viewModel.isFavoriteDrawerOpen ? 4 : 5)

                if viewModel.isSideDrawerOpen {
                    homeCategoryFilterRail(sideWidth: sideWidth, topSafeInset: topSafeInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.96, anchor: .trailing)),
                                removal: .opacity
                            )
                        )
                        .zIndex(5)
                }
            }
            .allowsHitTesting(isLayerOpen)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viewModel.isSideDrawerOpen)
            .onAppear {
                refreshFavoriteSubtitle()
            }
            .onChange(of: viewModel.isFavoriteDrawerOpen) { _, isOpen in
                if isOpen {
                    refreshFavoriteSubtitle()
                }
            }
            .onChange(of: viewModel.selectedLanguageCode) { _, _ in
                refreshFavoriteSubtitle()
            }
        }
    }

    private func refreshFavoriteSubtitle() {
        switch viewModel.selectedLanguageCode {
        case "zh-Hans", "ja":
            favoriteSubtitle = Bool.random()
                ? L10n.SideDrawer.favoritesSubtitleVariantA
                : L10n.SideDrawer.favoritesSubtitleVariantB
        default:
            favoriteSubtitle = L10n.SideDrawer.favoritesSubtitle
        }
    }

    private func sideDrawer(width: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()

                HStack(spacing: 7) {
                    languageSwitcher

                    Button(action: viewModel.toggleThemePalette) {
                        RoundedRectangle(cornerRadius: 999)
                            .fill(viewModel.activePillGradient)
                            .frame(width: 36, height: 26)
                    }
                    .buttonStyle(.plain)

                    TsugieClosePillButton(action: viewModel.closeSideDrawerPanel)
                }
            }

            if viewModel.isThemePaletteOpen {
                themePalette
            }

            VStack(spacing: 8) {
                menuButton(L10n.SideDrawer.menuFavorites, menu: .favorites)
                menuButton(L10n.SideDrawer.menuNotifications, menu: .notifications)
                menuButton(L10n.SideDrawer.menuContact, menu: .contact)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sideContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TsugieVisuals.drawerThemeBackground(scheme: viewModel.selectedThemeScheme))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.88)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.89, green: 0.96, blue: 0.98, opacity: 0.92), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.11, green: 0.30, blue: 0.38, opacity: 0.16), radius: 16, x: 0, y: 10)
        .offset(x: viewModel.isSideDrawerOpen ? 0 : width + 16)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: viewModel.isSideDrawerOpen)
    }

    private func favoriteDrawer(width: CGFloat) -> some View {
        let favorites = viewModel.filteredFavoritePlaces()

        return VStack(spacing: 12) {
            HStack {
                Text(L10n.SideDrawer.menuFavorites)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(red: 0.25, green: 0.41, blue: 0.47))
                Spacer()
                TsugieClosePillButton(action: viewModel.closeFavoriteDrawer)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(favoriteSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))

                favoriteStatusFilters
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 8) {
                    if favorites.isEmpty {
                        Text(L10n.SideDrawer.favoritesEmpty)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(favorites) { place in
                            favoriteCard(place)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TsugieVisuals.drawerThemeBackground(scheme: viewModel.selectedThemeScheme))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.88)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.89, green: 0.96, blue: 0.98, opacity: 0.92), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.11, green: 0.30, blue: 0.38, opacity: 0.16), radius: 16, x: 0, y: 10)
        .offset(x: viewModel.isFavoriteDrawerOpen ? 0 : -(width + 16))
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: viewModel.isFavoriteDrawerOpen)
    }

    private var languageSwitcher: some View {
        Button(action: viewModel.cycleLanguage) {
            HStack(spacing: 3) {
                ForEach(Array(languageOptions.enumerated()), id: \.element.code) { index, option in
                    Text(option.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(
                            viewModel.selectedLanguageCode == option.code
                            ? AnyShapeStyle(viewModel.activePillGradient)
                            : AnyShapeStyle(Color(red: 0.31, green: 0.46, blue: 0.52))
                        )
                        .frame(width: option.code == "en" ? 24 : 18, height: 20)
                    if index < languageOptions.count - 1 {
                        Text("/")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.68, green: 0.77, blue: 0.82))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.SideDrawer.languageSwitchA11y(viewModel.currentLanguageDisplayName))
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(Color.white.opacity(0.86), in: Capsule())
    }

    private func menuButton(_ title: String, menu: SideDrawerMenu) -> some View {
        let isActive = viewModel.sideDrawerMenu == menu
        return Button {
            viewModel.setSideDrawerMenu(menu)
        } label: {
            HStack {
                RoundedRectangle(cornerRadius: 999)
                    .fill(
                        isActive
                        ? AnyShapeStyle(viewModel.activePillGradient)
                        : AnyShapeStyle(Color.clear)
                    )
                    .frame(width: 7, height: 28)
                    .opacity(isActive ? 1 : 0)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(drawerItemFillColor)
            )
        }
        .buttonStyle(.plain)
        .shadow(
            color: Color(red: 0.20, green: 0.38, blue: 0.45, opacity: 0.16),
            radius: 8,
            x: 0,
            y: 4
        )
        .tsugieActiveGlow(
            isActive: isActive,
            glowGradient: viewModel.activePillGradient,
            glowColor: viewModel.activeMapGlowColor,
            cornerRadius: 18,
            blurRadius: 15,
            glowOpacity: 0.48,
            scale: 1.02,
            primaryOpacity: 0.44,
            primaryRadius: 16,
            primaryYOffset: 4,
            secondaryOpacity: 0.24,
            secondaryRadius: 30,
            secondaryYOffset: 8
        )
    }

    private var sideContent: some View {
        Group {
            switch viewModel.sideDrawerMenu {
            case .favorites:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.SideDrawer.menuFavorites)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color(red: 0.19, green: 0.36, blue: 0.43))
                        Spacer()
                        openFavoriteDrawerCapsuleButton
                    }

                    fastestFavoriteQuickBrowse
                }
            case .notifications:
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.SideDrawer.notificationsTitle)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(red: 0.19, green: 0.36, blue: 0.43))
                    notificationRow(
                        L10n.SideDrawer.startReminderTitle,
                        L10n.SideDrawer.startReminderHint,
                        isOn: viewModel.startNotificationEnabled
                    ) {
                        viewModel.toggleStartNotification()
                    }
                    notificationRow(
                        L10n.SideDrawer.nearbyNoticeTitle,
                        L10n.SideDrawer.nearbyNoticeHint,
                        isOn: viewModel.nearbyNotificationEnabled
                    ) {
                        viewModel.toggleNearbyNotification()
                    }
                }
            case .contact:
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.SideDrawer.contactTitle)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(red: 0.19, green: 0.36, blue: 0.43))
                    Link(L10n.SideDrawer.contactMailAction, destination: L10n.SideDrawer.contactMailURL)
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .drawerRoundedSurface(
                            cornerRadius: 12,
                            fillColor: drawerItemFillColor,
                            borderColor: drawerItemBorderColor,
                            borderOpacity: 0.88
                        )
                        .foregroundStyle(Color(red: 0.19, green: 0.36, blue: 0.43))
                    Button(L10n.SideDrawer.contactCopyMail) {
                        UIPasteboard.general.string = "contact@tsugie.app"
                    }
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .drawerRoundedSurface(
                        cornerRadius: 12,
                        fillColor: drawerItemFillColor,
                        borderColor: drawerItemBorderColor,
                        borderOpacity: 0.88
                    )
                    .foregroundStyle(Color(red: 0.30, green: 0.42, blue: 0.46))
                    Text("contact@tsugie.app")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))
                }
            case .none:
                EmptyView()
            }
        }
    }

    private var openFavoriteDrawerCapsuleButton: some View {
        Button(action: viewModel.openFavoriteDrawer) {
            HStack(spacing: 6) {
                FavoriteStateIconView(isFavorite: true, size: 17)
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.45, green: 0.55, blue: 0.60))
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .drawerRoundedSurface(
                cornerRadius: 999,
                fillColor: drawerItemFillColor,
                borderColor: drawerItemBorderColor,
                borderOpacity: 0.88
            )
            .shadow(color: Color(red: 0.24, green: 0.42, blue: 0.48, opacity: 0.12), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.SideDrawer.favoritesOpen)
    }

    private var fastestFavoriteQuickBrowse: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fastestPlaces = viewModel.fastestFavoritePlaces(now: context.date, limit: 2)
            let introText = viewModel.fastestFavoriteIntroText(now: context.date)
            VStack(alignment: .leading, spacing: 8) {
                Text(introText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.35, green: 0.48, blue: 0.54))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if fastestPlaces.isEmpty {
                    Text(L10n.SideDrawer.favoritesFastestEmpty)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        ForEach(fastestPlaces) { place in
                            favoriteCard(place, now: context.date, forceProgress: true)
                        }
                    }
                }
            }
        }
    }

    private func favoriteCard(
        _ place: HePlace,
        now: Date = Date(),
        forceProgress: Bool = false
    ) -> some View {
        let snapshot = viewModel.eventSnapshot(for: place, now: now)
        let range = L10n.Common.timeRange(snapshot.startLabel, snapshot.endLabel)
        let startDateText = snapshot.startDate?.formatted(
            Date.FormatStyle()
                .month(.twoDigits)
                .day(.twoDigits)
                .locale(viewModel.selectedLanguageLocale)
        ) ?? L10n.Common.dateUnknown
        let placeState = viewModel.placeState(for: place.id)
        let stamp = viewModel.stampPresentation(for: place)
        let cardBody = favoriteCardBody(
            place: place,
            snapshot: snapshot,
            startDateText: startDateText,
            range: range,
            placeState: placeState,
            stamp: stamp,
            forceProgress: forceProgress
        )

        return Button {
            viewModel.openQuickFromDrawer(placeID: place.id)
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
    }

    private func favoriteCardBody(
        place: HePlace,
        snapshot: EventStatusSnapshot,
        startDateText: String,
        range: String,
        placeState: PlaceState,
        stamp: PlaceStampPresentation?,
        forceProgress: Bool
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(place.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                    .lineLimit(1)
                Spacer()
                Text(viewModel.distanceText(for: place))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.36, green: 0.47, blue: 0.51))
            }
            HStack {
                Text("\(startDateText) \(range)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.36, green: 0.47, blue: 0.51))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                HStack(spacing: 6) {
                    FavoriteStateIconView(isFavorite: placeState.isFavorite, size: 17)
                    StampIconView(
                        stamp: stamp,
                        isColorized: placeState.isCheckedIn,
                        size: 18
                    )
                }
            }
            if snapshot.status == .ongoing || (forceProgress && snapshot.status == .upcoming) {
                TsugieMiniProgressView(
                    snapshot: snapshot,
                    glowBoost: 1.7,
                    endpointIconName: TsugieSmallIcon.assetName(for: place.heType),
                    endpointIconIsColorized: placeState.isFavorite
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .drawerRoundedSurface(
            cornerRadius: 14,
            fillColor: drawerItemFillColor,
            borderColor: drawerItemBorderColor,
            borderOpacity: 0
        )
        .overlay(alignment: .bottomTrailing) {
            PlaceStampBackgroundView(
                stamp: stamp,
                size: 82,
                isCompact: true,
                rotationDegrees: stamp?.rotationDegrees ?? 0
            )
                .offset(x: 8, y: 10)
        }
    }

    private var favoriteStatusFilters: some View {
        HStack(spacing: 6) {
            favoriteFilterPill(.all, L10n.SideDrawer.filterAll)
            favoriteFilterPill(.planned, L10n.SideDrawer.filterPlanned)
            favoriteFilterPill(.checked, L10n.SideDrawer.filterChecked)
        }
        .padding(.horizontal, 4)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: viewModel.favoriteFilter)
    }

    private func homeCategoryFilterRail(sideWidth: CGFloat, topSafeInset: CGFloat) -> some View {
        let filters = viewModel.mapCategoryFiltersForSidebar()
        return VStack(spacing: 8) {
            ForEach(filters, id: \.rawValue) { filter in
                mapCategoryFilterPill(
                    filter,
                    viewModel.mapCategoryFilterTitle(filter),
                    fixedWidth: 82
                )
            }
        }
        .padding(.top, topSafeInset + 20)
        .padding(.trailing, 12 + sideWidth + 12)
    }

    private func favoriteFilterPill(_ filter: FavoriteDrawerFilter, _ title: String) -> some View {
        let isActive = viewModel.favoriteFilter == filter
        return TsugieFilterPill(
            leadingText: title,
            trailingText: "\(viewModel.favoriteFilterCount(filter))",
            isActive: isActive,
            activeGradient: viewModel.activePillGradient,
            activeGlowColor: viewModel.activeMapGlowColor,
            fixedHeight: 32,
            onTap: {
                viewModel.setFavoriteFilter(filter)
            }
        )
    }

    private func mapCategoryFilterPill(_ filter: MapPlaceCategoryFilter, _ title: String, fixedWidth: CGFloat? = nil) -> some View {
        let isActive = viewModel.mapCategoryFilter == filter
        return TsugieFilterPill(
            leadingText: title,
            leadingIconName: TsugieSmallIcon.assetName(for: filter),
            trailingText: "\(viewModel.mapCategoryFilterCount(filter))",
            isActive: isActive,
            activeGradient: viewModel.activePillGradient,
            activeGlowColor: viewModel.activeMapGlowColor,
            fixedWidth: fixedWidth,
            fixedHeight: 32,
            onTap: {
                viewModel.setMapCategoryFilter(filter)
            }
        )
        .accessibilityLabel(title)
    }

    private var themePalette: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(["fresh", "ocean", "sunset", "sakura", "night"], id: \.self) { scheme in
                    let isSelected = viewModel.selectedThemeScheme == scheme
                    Button {
                        viewModel.setThemeScheme(scheme)
                    } label: {
                        RoundedRectangle(cornerRadius: 999)
                            .fill(themeChipGradient(scheme))
                            .frame(width: 30, height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(isSelected ? Color.white : .clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .tsugieActiveGlow(
                        isActive: isSelected,
                        glowGradient: themeChipGradient(scheme),
                        glowColor: viewModel.activeMapGlowColor,
                        cornerRadius: 999,
                        blurRadius: 11,
                        glowOpacity: 0.42,
                        scale: 1.02,
                        primaryOpacity: 0.34,
                        primaryRadius: 12,
                        primaryYOffset: 3,
                        secondaryOpacity: 0.18,
                        secondaryRadius: 20,
                        secondaryYOffset: 6
                    )
                }
            }

            sliderRow(title: L10n.SideDrawer.alpha, value: $viewModel.themeAlphaRatio)
            sliderRow(title: L10n.SideDrawer.saturation, value: $viewModel.themeSaturationRatio)
            sliderRow(title: L10n.SideDrawer.glow, value: $viewModel.themeGlowRatio, range: 0.6...1.8)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0.7...1.5,
        valueText: ((Double) -> String)? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.34, green: 0.46, blue: 0.52))
                .frame(width: 64, alignment: .leading)

            ThemeAdjusterSlider(value: value, range: range)

            Text(valueText?(value.wrappedValue) ?? "\(Int((value.wrappedValue * 100).rounded()))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.35, green: 0.47, blue: 0.52))
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func notificationRow(_ title: String, _ hint: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.21, green: 0.36, blue: 0.43))
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.43, green: 0.53, blue: 0.57))
            }
            Spacer()
            Button(action: action) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(
                            isOn
                            ? AnyShapeStyle(viewModel.activePillGradient)
                            : AnyShapeStyle(Color(red: 0.77, green: 0.84, blue: 0.87, opacity: 0.55))
                        )
                        .frame(width: 44, height: 26)
                        .overlay(Capsule().stroke(Color(red: 0.74, green: 0.83, blue: 0.87, opacity: 0.95), lineWidth: isOn ? 0 : 1))
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .padding(3)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .drawerRoundedSurface(
            cornerRadius: 14,
            fillColor: drawerItemFillColor,
            borderColor: drawerItemBorderColor,
            borderOpacity: 0.9
        )
    }

    private func themeChipGradient(_ scheme: String) -> LinearGradient {
        TsugieVisuals.pillGradient(scheme: scheme, alphaRatio: 1, saturationRatio: 1)
    }
}

private extension View {
    func drawerRoundedSurface(
        cornerRadius: CGFloat,
        fillColor: Color,
        borderColor: Color,
        borderOpacity: Double = 0.9,
        lineWidth: CGFloat = 1
    ) -> some View {
        self
            .background(fillColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor.opacity(borderOpacity), lineWidth: lineWidth)
            )
    }
}

private struct ThemeAdjusterSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let sliderGradient = LinearGradient(
        colors: [
            Color(red: 0.80, green: 0.73, blue: 0.80),
            Color(red: 0.15, green: 0.50, blue: 0.70)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        GeometryReader { proxy in
            let thumbSize: CGFloat = 13
            let trackHeight: CGFloat = 6
            let usableWidth = max(proxy.size.width - thumbSize, 1)
            let normalized = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            let x = usableWidth * normalized

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(sliderGradient.opacity(0.34))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(sliderGradient)
                    .frame(width: max(trackHeight, x + thumbSize / 2), height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.72, green: 0.79, blue: 0.84, opacity: 0.85), lineWidth: 1)
                    )
                    .offset(x: x)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedX = min(max(gesture.location.x - thumbSize / 2, 0), usableWidth)
                        let pct = clampedX / usableWidth
                        value = range.lowerBound + pct * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: 14)
    }
}
