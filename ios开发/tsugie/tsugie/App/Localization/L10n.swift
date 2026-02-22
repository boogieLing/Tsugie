import Foundation

enum L10n {
    private static let tableName = "Localizable"
    private static let languageStorageKey = "tsugie.app.language.v1"
    private static let languageAutoInitializedKey = "tsugie.app.language.auto_initialized.v1"
    private static let languageUserSelectedKey = "tsugie.app.language.user_selected.v1"
    private static let supportedLanguageCodes = ["zh-Hans", "en", "ja"]
    private static let zhHansTimeZoneIdentifiers: Set<String> = [
        "Asia/Shanghai",
        "Asia/Chongqing",
        "Asia/Harbin",
        "Asia/Urumqi",
        "Asia/Hong_Kong",
        "Asia/Macau",
        "Asia/Taipei"
    ]

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

    static func markLanguageSelectedByUser() {
        UserDefaults.standard.set(true, forKey: languageUserSelectedKey)
        UserDefaults.standard.set(true, forKey: languageAutoInitializedKey)
    }

    static func applyTimeZoneLanguageIfNeeded() -> String {
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: languageUserSelectedKey) {
            defaults.set(true, forKey: languageAutoInitializedKey)
            return activeLanguageCode
        }

        if defaults.bool(forKey: languageAutoInitializedKey) {
            return activeLanguageCode
        }

        // Legacy compatibility: if a language was already persisted, treat it as user-selected.
        if defaults.string(forKey: languageStorageKey) != nil {
            defaults.set(true, forKey: languageUserSelectedKey)
            defaults.set(true, forKey: languageAutoInitializedKey)
            return activeLanguageCode
        }

        let suggested = suggestedLanguageCodeForCurrentTimeZone()
        setLanguageCode(suggested)
        defaults.set(true, forKey: languageAutoInitializedKey)
        return activeLanguageCode
    }

    static func suggestedLanguageCodeForCurrentTimeZone() -> String {
        suggestedLanguageCode(for: .current)
    }

    static func suggestedLanguageCode(for timeZone: TimeZone) -> String {
        let identifier = timeZone.identifier
        if identifier == "Asia/Tokyo" {
            return "ja"
        }
        if zhHansTimeZoneIdentifiers.contains(identifier) {
            return "zh-Hans"
        }
        return "en"
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
        static var quickDateOngoingNow: String { text("home.quick.date_ongoing_now") }
        static var checkInBlockedUpcoming: String { text("home.check_in_blocked_upcoming") }
        static var locationFallbackTitle: String { text("home.location_fallback.title") }
        static var locationFallbackOutsideJapanMessage: String {
            text("home.location_fallback.outside_japan")
        }
        static var locationFallbackPermissionDeniedMessage: String {
            text("home.location_fallback.permission_denied")
        }
    }

    enum QuickCard {
        static var fastPlanTitle: String { text("quickcard.fast_plan") }
        static var expiredTitle: String { text("quickcard.expired_title") }
        static var closeA11y: String { text("quickcard.close_a11y") }
        static var viewDetails: String { text("quickcard.view_details") }
        static var startRoute: String { text("quickcard.start_route") }
        static var navigationChooserTitle: String { text("quickcard.navigation_chooser_title") }
        static var navigationOptionAppleMaps: String { text("quickcard.navigation_option.apple_maps") }
        static var navigationOptionGoogleMaps: String { text("quickcard.navigation_option.google_maps") }

        static func navigationChooserMessage(_ placeName: String) -> String {
            format("quickcard.navigation_chooser_message", placeName)
        }
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
        static var sourceTitle: String { text("detail.source_title") }
        static var extraInfo: String { text("detail.extra_info") }
        static var launchCount: String { text("detail.field.launch_count") }
        static var launchScale: String { text("detail.field.launch_scale") }
        static var paidSeat: String { text("detail.field.paid_seat") }
        static var accessText: String { text("detail.field.access_text") }
        static var parkingText: String { text("detail.field.parking_text") }
        static var trafficControlText: String { text("detail.field.traffic_control_text") }
        static var organizer: String { text("detail.field.organizer") }
        static var festivalType: String { text("detail.field.festival_type") }
        static var admissionFee: String { text("detail.field.admission_fee") }
        static var expectedVisitors: String { text("detail.field.expected_visitors") }
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
        static var favoritesSubtitleVariantA: String { text("drawer.favorites.subtitle.variant_a") }
        static var favoritesSubtitleVariantB: String { text("drawer.favorites.subtitle.variant_b") }
        static var favoritesEmpty: String { text("drawer.favorites.empty") }
        static var favoritesOpen: String { text("drawer.favorites.open") }
        static var favoritesCancelAction: String { text("drawer.favorites.cancel_action") }
        static var favoritesFastestTitle: String { text("drawer.favorites.fastest_title") }
        static var favoritesFastestEmpty: String { text("drawer.favorites.fastest.empty") }
        static var favoritesFastestHintToday: String { text("drawer.favorites.fastest.hint.today") }
        static var favoritesFastestHintTodayLater: String { text("drawer.favorites.fastest.hint.today_later") }
        static var favoritesFastestHintTodayEnded: String { text("drawer.favorites.fastest.hint.today_ended") }
        static var favoritesFastestHintOther: String { text("drawer.favorites.fastest.hint.other") }
        static var notificationsTitle: String { text("drawer.notifications.title") }
        static var startReminderTitle: String { text("drawer.notifications.start_reminder.title") }
        static var startReminderHint: String { text("drawer.notifications.start_reminder.hint") }
        static var nearbyNoticeTitle: String { text("drawer.notifications.nearby.title") }
        static var nearbyNoticeHint: String { text("drawer.notifications.nearby.hint") }
        static var contactTitle: String { text("drawer.contact.title") }
        static var contactMailAction: String { text("drawer.contact.mail_action") }
        static var contactCopyMail: String { text("drawer.contact.copy_mail") }
        static var contactPrivacyPolicyAction: String { text("drawer.contact.privacy_policy_action") }
        static var contactPrivacyPolicyHint: String { text("drawer.contact.privacy_policy_hint") }
        static var clearLocalDataHint: String { text("drawer.local_data.clear_hint") }
        static var clearLocalDataAction: String { text("drawer.local_data.clear_action") }
        static var clearLocalDataConfirmTitle: String { text("drawer.local_data.clear_confirm_title") }
        static var clearLocalDataConfirmMessage: String { text("drawer.local_data.clear_confirm_message") }
        static var clearLocalDataConfirmAction: String { text("drawer.local_data.clear_confirm_action") }
        static var clearLocalDataCancelAction: String { text("drawer.local_data.clear_cancel_action") }
        static var localDataClearedNotice: String { text("drawer.local_data.cleared_notice") }
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
        static var contactMailAddress: String { "ushouldknowr0@gmail.com" }

        static func languageSwitchA11y(_ currentLanguage: String) -> String {
            format("drawer.language.switch_a11y", currentLanguage)
        }

        static var contactMailURL: URL {
            let subject = text("drawer.contact.mail_subject")
            let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
            return URL(string: "mailto:\(contactMailAddress)?subject=\(encoded)")!
        }

        static var privacyPolicyURL: URL {
            let fallback = URL(string: "https://www.shyr0.com/idea/tsugie/privacy")!
            let raw = text("drawer.contact.privacy_policy_url")
            guard let url = URL(string: raw),
                  url.scheme?.lowercased() == "https",
                  url.host != nil else {
                return fallback
            }
            return url
        }

        static func favoritesFastestHintWithinWeek(days: Int) -> String {
            format("drawer.favorites.fastest.hint.within_week", days)
        }

        static func favoritesFastestHintWithinMonth(weeks: Int) -> String {
            format("drawer.favorites.fastest.hint.within_month", weeks)
        }
    }

    enum Notification {
        static var startingSoonTitle: String { text("notification.starting_soon_title") }
    }

    enum Privacy {
        static var firstLaunchTitle: String { text("privacy.first_launch.title") }
        static var firstLaunchMessage: String { text("privacy.first_launch.message") }
        static var firstLaunchOpenPolicy: String { text("privacy.first_launch.open_policy") }
        static var firstLaunchAccept: String { text("privacy.first_launch.accept") }
        static var firstLaunchRequiredHint: String { text("privacy.first_launch.required_hint") }
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
