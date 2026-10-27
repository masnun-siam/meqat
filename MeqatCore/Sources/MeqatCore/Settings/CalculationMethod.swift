/// Aladhan calculation methods (`/v1/methods`); 6 is unused and 99 (custom) is excluded.
public struct CalculationMethod: Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String

    public static let all: [CalculationMethod] = [
        .init(id: 0, name: "Shia Ithna-Ashari, Leva Institute, Qum"),
        .init(id: 1, name: "University of Islamic Sciences, Karachi"),
        .init(id: 2, name: "Islamic Society of North America (ISNA)"),
        .init(id: 3, name: "Muslim World League"),
        .init(id: 4, name: "Umm Al-Qura University, Makkah"),
        .init(id: 5, name: "Egyptian General Authority of Survey"),
        .init(id: 7, name: "Institute of Geophysics, University of Tehran"),
        .init(id: 8, name: "Gulf Region"),
        .init(id: 9, name: "Kuwait"),
        .init(id: 10, name: "Qatar"),
        .init(id: 11, name: "Majlis Ugama Islam Singapura, Singapore"),
        .init(id: 12, name: "Union Organization Islamic de France"),
        .init(id: 13, name: "Diyanet İşleri Başkanlığı, Turkey (experimental)"),
        .init(id: 14, name: "Spiritual Administration of Muslims of Russia"),
        .init(id: 15, name: "Moonsighting Committee Worldwide (Moonsighting.com)"),
        .init(id: 16, name: "Dubai (experimental)"),
        .init(id: 17, name: "Jabatan Kemajuan Islam Malaysia (JAKIM)"),
        .init(id: 18, name: "Tunisia"),
        .init(id: 19, name: "Algeria"),
        .init(id: 20, name: "Kementerian Agama Republik Indonesia"),
        .init(id: 21, name: "Morocco"),
        .init(id: 22, name: "Comunidade Islamica de Lisboa"),
        .init(id: 23, name: "Ministry of Awqaf, Islamic Affairs and Holy Places, Jordan"),
    ]
}
