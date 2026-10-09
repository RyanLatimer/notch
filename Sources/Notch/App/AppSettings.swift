import Foundation

enum MediaSourcePreference: String, CaseIterable, Identifiable {
    case automatic
    case mediaRemote
    case appleScript

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .mediaRemote: return "All apps (MediaRemote)"
        case .appleScript: return "Spotify & Music only (AppleScript)"
        }
    }
}

/// User preferences, persisted in UserDefaults. Mutate on the main thread.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) } }
    @Published var showOnNonNotchDisplays: Bool { didSet { defaults.set(showOnNonNotchDisplays, forKey: Keys.showOnNonNotchDisplays) } }
    @Published var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: Keys.expandOnHover) } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Keys.hoverDelay) } }
    @Published var hapticFeedback: Bool { didSet { defaults.set(hapticFeedback, forKey: Keys.hapticFeedback) } }
    @Published var showMusicActivity: Bool { didSet { defaults.set(showMusicActivity, forKey: Keys.showMusicActivity) } }
    @Published var showChargingActivity: Bool { didSet { defaults.set(showChargingActivity, forKey: Keys.showChargingActivity) } }
    @Published var showVolumeHUD: Bool { didSet { defaults.set(showVolumeHUD, forKey: Keys.showVolumeHUD) } }
    @Published var showBrightnessHUD: Bool { didSet { defaults.set(showBrightnessHUD, forKey: Keys.showBrightnessHUD) } }
    @Published var replaceSystemHUD: Bool { didSet { defaults.set(replaceSystemHUD, forKey: Keys.replaceSystemHUD) } }
    @Published var showCalendar: Bool { didSet { defaults.set(showCalendar, forKey: Keys.showCalendar) } }
    @Published var enableShelf: Bool { didSet { defaults.set(enableShelf, forKey: Keys.enableShelf) } }
    @Published var artworkTintedVisualizer: Bool { didSet { defaults.set(artworkTintedVisualizer, forKey: Keys.artworkTintedVisualizer) } }
    @Published var mediaSource: MediaSourcePreference { didSet { defaults.set(mediaSource.rawValue, forKey: Keys.mediaSource) } }

    private enum Keys {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showOnNonNotchDisplays = "showOnNonNotchDisplays"
        static let expandOnHover = "expandOnHover"
        static let hoverDelay = "hoverDelay"
        static let hapticFeedback = "hapticFeedback"
        static let showMusicActivity = "showMusicActivity"
        static let showChargingActivity = "showChargingActivity"
        static let showVolumeHUD = "showVolumeHUD"
        static let showBrightnessHUD = "showBrightnessHUD"
        static let replaceSystemHUD = "replaceSystemHUD"
        static let showCalendar = "showCalendar"
        static let enableShelf = "enableShelf"
        static let artworkTintedVisualizer = "artworkTintedVisualizer"
        static let mediaSource = "mediaSource"
    }

    private init() {
        defaults.register(defaults: [
            Keys.showMenuBarIcon: true,
            Keys.showOnNonNotchDisplays: false,
            Keys.expandOnHover: true,
            Keys.hoverDelay: 0.15,
            Keys.hapticFeedback: true,
            Keys.showMusicActivity: true,
            Keys.showChargingActivity: true,
            Keys.showVolumeHUD: true,
            Keys.showBrightnessHUD: true,
            Keys.replaceSystemHUD: false,
            Keys.showCalendar: true,
            Keys.enableShelf: true,
            Keys.artworkTintedVisualizer: true,
            Keys.mediaSource: MediaSourcePreference.automatic.rawValue,
        ])

        showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        showOnNonNotchDisplays = defaults.bool(forKey: Keys.showOnNonNotchDisplays)
        expandOnHover = defaults.bool(forKey: Keys.expandOnHover)
        hoverDelay = defaults.double(forKey: Keys.hoverDelay)
        hapticFeedback = defaults.bool(forKey: Keys.hapticFeedback)
        showMusicActivity = defaults.bool(forKey: Keys.showMusicActivity)
        showChargingActivity = defaults.bool(forKey: Keys.showChargingActivity)
        showVolumeHUD = defaults.bool(forKey: Keys.showVolumeHUD)
        showBrightnessHUD = defaults.bool(forKey: Keys.showBrightnessHUD)
        replaceSystemHUD = defaults.bool(forKey: Keys.replaceSystemHUD)
        showCalendar = defaults.bool(forKey: Keys.showCalendar)
        enableShelf = defaults.bool(forKey: Keys.enableShelf)
        artworkTintedVisualizer = defaults.bool(forKey: Keys.artworkTintedVisualizer)
        mediaSource = MediaSourcePreference(rawValue: defaults.string(forKey: Keys.mediaSource) ?? "") ?? .automatic
    }
}
