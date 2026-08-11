import Foundation

/// One place holding every store, so the panel and the menu talk to the same
/// objects.
final class AppModel: ObservableObject {
    let panel = PanelState()
    let shelf = ShelfStore()
    let clipboard = ClipboardStore()
    let calendar = CalendarStore()
    let spotify = SpotifyStore()
    let timer = TimerStore()
    let system = SystemStore()
    let weather = WeatherStore()
    let math = MathStore()
    let network = NetworkStore()
    let colors = ColorStore()
    let downloads = DownloadsStore()

    // Added 8 August 2026.
    let convert = ConvertStore()
    let translate = TranslateStore()
    let pins = PinStore()
    let images = ImageToolStore()
    let passwords = PasswordStore()
    let privacy = PrivacyStore()
    let awake = AwakeStore()
    let vpn = VPNStore()

    // Added 11 August 2026.
    let settings = SettingsStore()

    /// Lazy for one reason: each of these needs a sibling, and a stored property
    /// cannot reach one before the object exists.
    private(set) lazy var recorder = RecordStore(shelf: shelf)
    /// Both read somebody's own folder, and which folder that is belongs to
    /// `settings` rather than to a constant in the source.
    private(set) lazy var plans = PlansStore(settings: settings)
    private(set) lazy var theorem = TheoremStore(settings: settings)
}
