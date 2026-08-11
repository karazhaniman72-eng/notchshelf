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
    let plans = PlansStore()
    let math = MathStore()
    let theorem = TheoremStore()
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
    /// Lazy for one reason: it needs the shelf, and a stored property cannot
    /// reach a sibling before the object exists.
    private(set) lazy var recorder = RecordStore(shelf: shelf)
}
