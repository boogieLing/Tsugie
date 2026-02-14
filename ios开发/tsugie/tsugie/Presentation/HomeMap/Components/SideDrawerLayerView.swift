import SwiftUI
import UIKit

struct SideDrawerLayerView: View {
    @ObservedObject var viewModel: HomeMapViewModel
    private let drawerItemFillColor = Color.white
    private let drawerItemBorderColor = Color(red: 0.84, green: 0.92, blue: 0.95)

    var body: some View {
        GeometryReader { proxy in
            let sideWidth = min(proxy.size.width * 0.70, 266)
            let favoriteWidth = min(proxy.size.width * 0.80, 302)
            let isLayerOpen = viewModel.isSideDrawerOpen || viewModel.isFavoriteDrawerOpen

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
            }
            .allowsHitTesting(isLayerOpen)
        }
    }

    private func sideDrawer(width: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("つぎへ ナビ")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color(red: 0.29, green: 0.45, blue: 0.52))

                Spacer()

                HStack(spacing: 7) {
                    Button(action: viewModel.toggleThemePalette) {
                        RoundedRectangle(cornerRadius: 999)
                            .fill(viewModel.activePillGradient)
                            .frame(width: 36, height: 26)
                    }
                    .buttonStyle(.plain)

                    Button(action: viewModel.closeSideDrawerPanel) {
                        Text("×")
                            .font(.system(size: 18))
                            .frame(width: 28, height: 28)
                            .drawerCircleSurface(
                                fillColor: drawerItemFillColor,
                                borderColor: Color(red: 0.83, green: 0.91, blue: 0.95),
                                borderOpacity: 0.9
                            )
                            .foregroundStyle(Color(red: 0.37, green: 0.50, blue: 0.54))
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.isThemePaletteOpen {
                themePalette
            }

            VStack(spacing: 8) {
                menuButton("行きたい栞", menu: .favorites)
                menuButton("知らせの灯", menu: .notifications)
                menuButton("ことづて", menu: .contact)
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
        VStack(spacing: 12) {
            HStack {
                Text("行きたい栞")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(red: 0.25, green: 0.41, blue: 0.47))
                Spacer()
                Button(action: viewModel.closeFavoriteDrawer) {
                    Text("×")
                        .font(.system(size: 18))
                        .frame(width: 28, height: 28)
                        .drawerCircleSurface(
                            fillColor: drawerItemFillColor,
                            borderColor: Color(red: 0.83, green: 0.91, blue: 0.95),
                            borderOpacity: 0.9
                        )
                        .foregroundStyle(Color(red: 0.37, green: 0.50, blue: 0.54))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("行きたい余韻と、歩いた足あとをここに。")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))

                    favoriteFilters

                    VStack(spacing: 8) {
                        if viewModel.filteredFavoritePlaces().isEmpty {
                            Text("まだ栞は白紙です。")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(viewModel.filteredFavoritePlaces()) { place in
                                favoriteCard(place)
                            }
                        }
                    }
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
        .offset(x: viewModel.isFavoriteDrawerOpen ? 0 : -(width + 16))
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: viewModel.isFavoriteDrawerOpen)
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
                    Text("行きたい栞")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(red: 0.19, green: 0.36, blue: 0.43))
                    Button("栞ドロワーをひらく") {
                        viewModel.openFavoriteDrawer()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .drawerRoundedSurface(
                        cornerRadius: 10,
                        fillColor: drawerItemFillColor,
                        borderColor: drawerItemBorderColor,
                        borderOpacity: 0.88
                    )
                    .foregroundStyle(Color(red: 0.30, green: 0.42, blue: 0.46))
                }
            case .notifications:
                VStack(alignment: .leading, spacing: 8) {
                    Text("通知設定")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(red: 0.19, green: 0.36, blue: 0.43))
                    notificationRow("開始前リマインド", "開催直前にお知らせ", isOn: viewModel.startNotificationEnabled) {
                        viewModel.toggleStartNotification()
                    }
                    notificationRow("周辺スポット通知", "少し遠めの候補も通知", isOn: viewModel.nearbyNotificationEnabled) {
                        viewModel.toggleNearbyNotification()
                    }
                }
            case .contact:
                VStack(alignment: .leading, spacing: 10) {
                    Text("お問い合わせ")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(red: 0.19, green: 0.36, blue: 0.43))
                    Link("メールで連絡する", destination: URL(string: "mailto:contact@tsugie.app?subject=Tsugie%20問い合わせ")!)
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
                    Button("メールアドレスをコピー") {
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
                Text("項目をひとつ選ぶと、ここに静かにひらきます。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))
            }
        }
    }

    private func favoriteCard(_ place: HePlace) -> some View {
        let snapshot = viewModel.eventSnapshot(for: place)
        let range = "\(snapshot.startLabel) - \(snapshot.endLabel)"

        return Button {
            viewModel.openQuickFromDrawer(placeID: place.id)
        } label: {
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
                    Text(range)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.36, green: 0.47, blue: 0.51))
                    Spacer()
                    PlaceStateIconsView(
                        placeState: viewModel.placeState(for: place.id),
                        size: 16,
                        activeGradient: viewModel.activePillGradient,
                        activeGlowColor: viewModel.activeMapGlowColor
                    )
                }
                if snapshot.status == .ongoing {
                    TsugieMiniProgressView(snapshot: snapshot)
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
        }
        .buttonStyle(.plain)
    }

    private var favoriteFilters: some View {
        HStack(spacing: 6) {
            filterButton(.all, "すべて")
            filterButton(.planned, "まだ訪れず")
            filterButton(.checked, "足あと済み")
        }
    }

    private func filterButton(_ filter: FavoriteDrawerFilter, _ title: String) -> some View {
        let isActive = viewModel.favoriteFilter == filter
        return Button {
            viewModel.setFavoriteFilter(filter)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Text("\(viewModel.favoriteFilterCount(filter))")
                    .foregroundStyle(Color(red: 0.33, green: 0.46, blue: 0.52))
            }
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                isActive
                ? AnyShapeStyle(drawerItemFillColor)
                : AnyShapeStyle(drawerItemFillColor)
            , in: Capsule())
            .overlay(Capsule().stroke(drawerItemBorderColor.opacity(0.9), lineWidth: isActive ? 0 : 1))
            .foregroundStyle(Color(red: 0.27, green: 0.41, blue: 0.47))
        }
        .buttonStyle(.plain)
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

            sliderRow(title: "透過比率", value: $viewModel.themeAlphaRatio)
            sliderRow(title: "彩度", value: $viewModel.themeSaturationRatio)
        }
    }

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.34, green: 0.46, blue: 0.52))
                .frame(width: 48, alignment: .leading)

            ThemeAdjusterSlider(value: value, range: 0.7...1.5)

            Text("\(Int((value.wrappedValue * 100).rounded()))%")
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
                        .frame(width: 50, height: 30)
                        .overlay(Capsule().stroke(Color(red: 0.74, green: 0.83, blue: 0.87, opacity: 0.95), lineWidth: isOn ? 0 : 1))
                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
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
        switch scheme {
        case "ocean":
            return LinearGradient(colors: [Color(red: 0.00, green: 0.66, blue: 1.00), Color(red: 0.36, green: 0.68, blue: 0.89), Color(red: 0.49, green: 0.89, blue: 0.99)], startPoint: .leading, endPoint: .trailing)
        case "sunset":
            return LinearGradient(colors: [Color(red: 1.00, green: 0.62, blue: 0.26), Color(red: 1.00, green: 0.42, blue: 0.42), Color(red: 1.00, green: 0.84, blue: 0.44)], startPoint: .leading, endPoint: .trailing)
        case "sakura":
            return LinearGradient(colors: [Color(red: 1.00, green: 0.49, blue: 0.70), Color(red: 0.65, green: 0.52, blue: 1.00), Color(red: 1.00, green: 0.82, blue: 0.92)], startPoint: .leading, endPoint: .trailing)
        case "night":
            return LinearGradient(colors: [Color(red: 0.35, green: 0.66, blue: 1.00), Color(red: 0.50, green: 0.55, blue: 1.00), Color(red: 0.48, green: 0.96, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [Color(red: 0.13, green: 0.85, blue: 0.80), Color(red: 0.48, green: 0.75, blue: 1.00), Color(red: 1.00, green: 0.61, blue: 0.87)], startPoint: .leading, endPoint: .trailing)
        }
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

    func drawerCircleSurface(
        fillColor: Color,
        borderColor: Color,
        borderOpacity: Double = 0.9,
        lineWidth: CGFloat = 1
    ) -> some View {
        self
            .background(fillColor, in: Circle())
            .overlay(
                Circle()
                    .stroke(borderColor.opacity(borderOpacity), lineWidth: lineWidth)
            )
    }
}

private struct ThemeAdjusterSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let sliderGradient = LinearGradient(
        colors: [
            Color(red: 61 / 255, green: 78 / 255, blue: 129 / 255),
            Color(red: 87 / 255, green: 83 / 255, blue: 201 / 255),
            Color(red: 110 / 255, green: 127 / 255, blue: 243 / 255)
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
                    .shadow(color: Color(red: 87 / 255, green: 83 / 255, blue: 201 / 255, opacity: 0.42), radius: 6, x: 0, y: 0)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Color(red: 87 / 255, green: 83 / 255, blue: 201 / 255, opacity: 0.52), radius: 5, x: 0, y: 2)
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
