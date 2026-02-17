import Foundation

enum L10n {
    private static let tableName = "Localizable"
    private static let languageStorageKey = "tsugie.app.language.v1"
    private static let supportedLanguageCodes = ["zh-Hans", "en", "ja"]

    private static var activeLanguageCode: String = {
        if let stored = UserDefaults.standard.string(forKey: languageStorageKey) {
            return normalizedLanguageCode(stored)
        }
        if let preferred = Locale.preferredLanguages.first {
            return normalizedLanguageCode(preferred)
        }
        return "ja"
    }()

    static var languageCode: String {
        activeLanguageCode
    }

    static var locale: Locale {
        Locale(identifier: activeLanguageCode)
    }

    static func setLanguageCode(_ code: String) {
        let normalized = normalizedLanguageCode(code)
        guard normalized != activeLanguageCode else { return }
        activeLanguageCode = normalized
        UserDefaults.standard.set(normalized, forKey: languageStorageKey)
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: tableName, bundle: activeBundle, value: key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: args)
    }

    private static var activeBundle: Bundle {
        guard let path = Bundle.main.path(forResource: activeLanguageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static func normalizedLanguageCode(_ code: String) -> String {
        let lowered = code.lowercased()
        if lowered.hasPrefix("zh") {
            return "zh-Hans"
        }
        if lowered.hasPrefix("ja") {
            return "ja"
        }
        if lowered.hasPrefix("en") {
            return "en"
        }
        if supportedLanguageCodes.contains(code) {
            return code
        }
        return "ja"
    }

    enum Common {
        static var close: String { text("common.close") }
        static var unknownTime: String { text("common.unknown_time") }
        static var startUnknown: String { text("common.start_unknown") }
        static var dateUnknown: String { text("common.date_unknown") }
        static var now: String { text("common.now") }

        static func timeRange(_ start: String, _ end: String) -> String {
            format("common.time_range", start, end)
        }

        static func openHours(_ range: String) -> String {
            format("common.open_hours", range)
        }
    }

    enum EventStatus {
        static var ended: String { text("event.ended") }
        static var endOnly: String { text("event.end_only") }

        static func leftRemaining(_ eta: String) -> String {
            format("event.left.remaining", eta)
        }

        static func rightEndAt(_ time: String) -> String {
            format("event.right.end_at", time)
        }

        static func leftStartsIn(_ eta: String) -> String {
            format("event.left.starts_in", eta)
        }

        static func rightStartAt(_ time: String) -> String {
            format("event.right.start_at", time)
        }

        static func countdownDaysHours(days: Int, hours: Int) -> String {
            format("event.countdown.days_hours", days, hours)
        }

        static func countdownHoursMinutesSeconds(hours: Int, minutes: Int, seconds: Int) -> String {
            format("event.countdown.hours_minutes_seconds", hours, minutes, seconds)
        }

        static func countdownMinutesSeconds(minutes: Int, seconds: Int) -> String {
            format("event.countdown.minutes_seconds", minutes, seconds)
        }

        static func countdownSeconds(_ seconds: Int) -> String {
            format("event.countdown.seconds", seconds)
        }
    }

    enum Home {
        static var calendarButton: String { text("home.calendar.button") }
        static var openCalendarA11y: String { text("home.calendar.open_a11y") }
        static var resetLocationA11y: String { text("home.location.reset_a11y") }
        static var openMenuA11y: String { text("home.menu.open_a11y") }
        static var quickDateTodaySoon: String { text("home.quick.date_today_soon") }
    }

    enum QuickCard {
        static var fastPlanTitle: String { text("quickcard.fast_plan") }
        static var closeA11y: String { text("quickcard.close_a11y") }
        static var viewDetails: String { text("quickcard.view_details") }
        static var startRoute: String { text("quickcard.start_route") }
    }

    enum Nearby {
        static var preparing: String { text("nearby.preparing") }

        static func remaining(_ eta: String) -> String {
            format("nearby.remaining", eta)
        }

        static func startsIn(_ eta: String) -> String {
            format("nearby.starts_in", eta)
        }

        static func startsAt(_ time: String) -> String {
            format("nearby.starts_at", time)
        }

        static func endedAt(_ time: String) -> String {
            format("nearby.ended_at", time)
        }
    }

    enum Marker {
        static var favoriteA11y: String { text("marker.favorite_a11y") }
        static var quickA11y: String { text("marker.quick_a11y") }
        static var checkedInA11y: String { text("marker.checked_in_a11y") }
        static var placeActionA11y: String { text("marker.place_action_a11y") }
    }

    enum PlaceState {
        static var favoriteA11y: String { text("place_state.favorite_a11y") }
        static var checkedInA11y: String { text("place_state.checked_in_a11y") }
    }

    enum Detail {
        static var title: String { text("detail.title") }
        static var closeA11y: String { text("detail.close_a11y") }
        static var mapLocation: String { text("detail.map_location") }
        static var focus: String { text("detail.focus") }
        static var intro: String { text("detail.intro") }
        static var atmosphere: String { text("detail.atmosphere") }
        static var heat: String { text("detail.heat") }
        static var surprise: String { text("detail.surprise") }
        static var progressTitleOngoing: String { text("detail.progress_title.ongoing") }
        static var progressTitleUpcoming: String { text("detail.progress_title.upcoming") }
        static var progressTitleEnded: String { text("detail.progress_title.ended") }
        static var progressTitleUnknown: String { text("detail.progress_title.unknown") }
        static var upcomingPending: String { text("detail.upcoming_pending") }

        static func progressMetaOngoing(percent: Int, eta: String) -> String {
            format("detail.progress_meta.ongoing", percent, eta)
        }

        static func progressMetaUpcoming(_ eta: String) -> String {
            format("detail.progress_meta.upcoming", eta)
        }

        static func startAt(_ time: String) -> String {
            format("detail.start_at", time)
        }

        static func endAt(_ time: String) -> String {
            format("detail.end_at", time)
        }
    }

    enum SideDrawer {
        static var title: String { text("drawer.title") }
        static var menuFavorites: String { text("drawer.menu.favorites") }
        static var menuNotifications: String { text("drawer.menu.notifications") }
        static var menuContact: String { text("drawer.menu.contact") }
        static var favoritesSubtitle: String { text("drawer.favorites.subtitle") }
        static var favoritesEmpty: String { text("drawer.favorites.empty") }
        static var favoritesOpen: String { text("drawer.favorites.open") }
        static var notificationsTitle: String { text("drawer.notifications.title") }
        static var startReminderTitle: String { text("drawer.notifications.start_reminder.title") }
        static var startReminderHint: String { text("drawer.notifications.start_reminder.hint") }
        static var nearbyNoticeTitle: String { text("drawer.notifications.nearby.title") }
        static var nearbyNoticeHint: String { text("drawer.notifications.nearby.hint") }
        static var contactTitle: String { text("drawer.contact.title") }
        static var contactMailAction: String { text("drawer.contact.mail_action") }
        static var contactCopyMail: String { text("drawer.contact.copy_mail") }
        static var noneHint: String { text("drawer.none_hint") }
        static var filterAll: String { text("drawer.filter.all") }
        static var filterPlanned: String { text("drawer.filter.planned") }
        static var filterChecked: String { text("drawer.filter.checked") }
        static var alpha: String { text("drawer.slider.alpha") }
        static var saturation: String { text("drawer.slider.saturation") }
        static var glow: String { text("drawer.slider.glow") }
        static var languageNameZhHans: String { text("drawer.language.zh_hans") }
        static var languageNameEn: String { text("drawer.language.en") }
        static var languageNameJa: String { text("drawer.language.ja") }

        static func languageSwitchA11y(_ currentLanguage: String) -> String {
            format("drawer.language.switch_a11y", currentLanguage)
        }

        static var contactMailURL: URL {
            let subject = text("drawer.contact.mail_subject")
            let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
            return URL(string: "mailto:contact@tsugie.app?subject=\(encoded)")!
        }
    }

    enum Calendar {
        static var title: String { text("calendar.title") }
        static var subtitle: String { text("calendar.subtitle") }
        static var closeA11y: String { text("calendar.close_a11y") }
        static var empty: String { text("calendar.empty") }
        static var dayTitleFallback: String { text("calendar.day_title.fallback") }
        static var drawerSummary: String { text("calendar.drawer.summary") }
        static var drawerNoMatch: String { text("calendar.drawer.no_match") }
        static var selectedDayEmpty: String { text("calendar.selected_day.empty") }
        static var categoryAll: String { text("calendar.category.all") }
        static var categoryHanabi: String { text("calendar.category.hanabi") }
        static var categoryMatsuri: String { text("calendar.category.matsuri") }
        static var categorySakura: String { text("calendar.category.sakura") }
        static var categoryMomiji: String { text("calendar.category.momiji") }
        static var categoryNature: String { text("calendar.category.nature") }
        static var categoryOther: String { text("calendar.category.other") }

        static func dayTitle(_ day: String) -> String {
            format("calendar.day_title", day)
        }
    }

    enum Placeholder {
        static var title: String { text("placeholder.title") }
        static var desc1: String { text("placeholder.desc1") }
        static var desc2: String { text("placeholder.desc2") }
    }

    enum MockPlace {
        static var sumidaHint: String { text("mock.sumida.hint") }
        static var sumidaMapSpot: String { text("mock.sumida.map_spot") }
        static var sumidaDesc: String { text("mock.sumida.desc") }
        static var sumidaImageTag: String { text("mock.sumida.image_tag") }
        static var sumidaImageHint: String { text("mock.sumida.image_hint") }

        static var asakusaHint: String { text("mock.asakusa.hint") }
        static var asakusaMapSpot: String { text("mock.asakusa.map_spot") }
        static var asakusaDesc: String { text("mock.asakusa.desc") }
        static var asakusaImageTag: String { text("mock.asakusa.image_tag") }
        static var asakusaImageHint: String { text("mock.asakusa.image_hint") }

        static var oshiageHint: String { text("mock.oshiage.hint") }
        static var oshiageMapSpot: String { text("mock.oshiage.map_spot") }
        static var oshiageDesc: String { text("mock.oshiage.desc") }
        static var oshiageImageTag: String { text("mock.oshiage.image_tag") }
        static var oshiageImageHint: String { text("mock.oshiage.image_hint") }
    }
}
