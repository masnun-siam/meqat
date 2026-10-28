import Foundation
import ServiceManagement
import os

public protocol LoginItemService: AnyObject {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

public final class MainAppLoginItem: LoginItemService {
    public init() {}

    // `.requiresApproval` counts as not enabled.
    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
}

public enum LoginItemSync {
    private static let logger = Logger(subsystem: MeqatCore.bundleIdentifier, category: "login-item")

    /// Brings the login item in line with `wanted`. Returns the error if the service call failed.
    @discardableResult
    public static func apply(_ wanted: Bool, to service: LoginItemService) -> Error? {
        guard service.isEnabled != wanted else { return nil }
        do {
            if wanted { try service.register() } else { try service.unregister() }
            return nil
        } catch {
            logger.error(
                "login item \(wanted ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            return error
        }
    }
}
