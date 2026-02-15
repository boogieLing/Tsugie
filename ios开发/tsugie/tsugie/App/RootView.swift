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
                placeStateProvider: { viewModel.placeState(for: $0) },
                onClose: {
                    viewModel.setCalendarPresented(false)
                    isCalendarPresented = false
                },
                onSelectPlace: { placeID in
                    viewModel.setCalendarPresented(false)
                    isCalendarPresented = false
                    viewModel.openQuickCard(placeID: placeID)
                },
                now: viewModel.now
            )
            .environment(\.locale, viewModel.selectedLanguageLocale)
        }
    }
}
