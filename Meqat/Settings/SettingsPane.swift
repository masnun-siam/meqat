import MeqatCore

enum SettingsPane: Hashable {
    case general, location, about
    case event(EventID)
}
