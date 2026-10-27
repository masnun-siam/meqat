import Foundation

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext.isEmpty ? nil : ext, subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Fixtures/\(name)"])
        }
        return try Data(contentsOf: url)
    }
}
