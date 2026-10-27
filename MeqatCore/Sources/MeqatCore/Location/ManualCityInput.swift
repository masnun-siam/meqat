import Foundation

public enum ManualCityInput {
    public static let maxLength = 100

    /// Trimmed, length-limited values; nil while city or country is empty. An empty state becomes nil.
    public static func normalized(city: String, country: String, state: String) -> (city: String, country: String, state: String?)? {
        let city = clean(city), country = clean(country), state = clean(state)
        guard !city.isEmpty, !country.isEmpty else { return nil }
        return (city, country, state.isEmpty ? nil : state)
    }

    private static func clean(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }
}
