import MeqatCore

enum SettingsPane: Hashable {
    case general, location, event(EventID)
}
