import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = HomeMapViewModel()
    @State private var isCalendarPresented = false

    var body: some View {
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
            }
        ) {
            CalendarPageView(
                places: viewModel.places,
                detailPlaces: viewModel.calendarDetailPlaces,
                placeStateProvider: { viewModel.placeState(for: $0) },
                stampProvider: { viewModel.stampPresentation(for: $0, heType: $1) },
                onClose: {
                    viewModel.setCalendarPresented(false)
                    isCalendarPresented = false
                },
                onSelectPlace: { placeID in
                    viewModel.setCalendarPresented(false)
                    isCalendarPresented = false
                    viewModel.openQuickFromCalendar(placeID: placeID)
                },
                now: viewModel.now,
                activeGradient: viewModel.activePillGradient,
                activeGlowColor: viewModel.activeMapGlowColor
            )
            .environment(\.locale, viewModel.selectedLanguageLocale)
        }
    }
}
