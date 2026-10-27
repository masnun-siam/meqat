import UserNotifications

public protocol NotificationCentering: AnyObject, Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func isAuthorized() async -> Bool
}

extension UNUserNotificationCenter: NotificationCentering {
    public func isAuthorized() async -> Bool {
        let status = await notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
}
