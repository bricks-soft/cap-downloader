import Capacitor
import UserNotifications
import XCTest
@testable import BricksSoftCapDownloader

final class DownloadNotificationRoutingTests: XCTestCase {
    func testInstallForwardsToThePreviousLocalNotificationHandler() {
        let router = NotificationRouter()
        let previous = NotificationHandlerSpy()
        router.localNotificationHandler = previous
        let handler = DownloadNotificationHandler(viewController: { nil })

        handler.install(on: router)
        XCTAssertTrue(router.localNotificationHandler === handler)
        XCTAssertTrue(handler.forwardingHandler === previous)

        handler.install(on: router)
        XCTAssertTrue(handler.forwardingHandler === previous)
    }

    func testUnownedNotificationsReachTheForwardedHandler() throws {
        let router = NotificationRouter()
        let previous = NotificationHandlerSpy()
        previous.presentationOptions = [.badge]
        router.localNotificationHandler = previous
        let handler = DownloadNotificationHandler(viewController: { nil })
        handler.install(on: router)

        let other = try makeNotification(identifier: "123")
        XCTAssertEqual(handler.willPresent(notification: other), [.badge])
        handler.didReceive(response: try makeResponse(to: other))
        XCTAssertEqual(previous.presentedIdentifiers, ["123"])
        XCTAssertEqual(previous.receivedIdentifiers, ["123"])

        let owned = try makeNotification(identifier: "cap-downloader-7-complete")
        XCTAssertEqual(handler.willPresent(notification: owned), [.banner, .list, .sound])
        handler.didReceive(response: try makeResponse(to: owned))
        XCTAssertEqual(previous.presentedIdentifiers, ["123"])
        XCTAssertEqual(previous.receivedIdentifiers, ["123"])
    }
}

private final class NotificationHandlerSpy: NSObject, NotificationHandlerProtocol {
    var presentationOptions: UNNotificationPresentationOptions = []
    private(set) var presentedIdentifiers: [String] = []
    private(set) var receivedIdentifiers: [String] = []

    func willPresent(notification: UNNotification) -> UNNotificationPresentationOptions {
        presentedIdentifiers.append(notification.request.identifier)
        return presentationOptions
    }

    func didReceive(response: UNNotificationResponse) {
        receivedIdentifiers.append(response.notification.request.identifier)
    }
}

// UserNotifications has no public initializers for delivered notifications or responses.
private func makeNotification(identifier: String) throws -> UNNotification {
    let request = UNNotificationRequest(identifier: identifier, content: UNNotificationContent(), trigger: nil)
    let selector = NSSelectorFromString("notificationWithRequest:date:")
    let notification = (UNNotification.self as AnyObject).perform(selector, with: request, with: Date())
    return try XCTUnwrap(notification?.takeUnretainedValue() as? UNNotification)
}

private func makeResponse(to notification: UNNotification) throws -> UNNotificationResponse {
    let selector = NSSelectorFromString("responseWithNotification:actionIdentifier:")
    let response = (UNNotificationResponse.self as AnyObject).perform(
        selector,
        with: notification,
        with: UNNotificationDefaultActionIdentifier
    )
    return try XCTUnwrap(response?.takeUnretainedValue() as? UNNotificationResponse)
}
