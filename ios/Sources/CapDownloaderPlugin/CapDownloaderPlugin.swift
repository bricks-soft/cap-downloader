import Capacitor
import Foundation
import UserNotifications

enum DownloadNotificationAuthorizationDecision: Equatable {
    case allow
    case request
    case deny
}

@objc(CapDownloaderPlugin)
public class CapDownloaderPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CapDownloaderPlugin"
    public let jsName = "CapDownloader"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "download", returnType: CAPPluginReturnPromise)
    ]

    private lazy var notificationHandler = DownloadNotificationHandler { [weak self] in
        self?.bridge?.viewController
    }

    override public func load() {
        bridge?.notificationRouter.localNotificationHandler = notificationHandler
        DownloadCoordinator.shared.restorePendingDownloads()
    }

    @objc func download(_ call: CAPPluginCall) {
        guard
            let title = call.getString("title"),
            let urlValue = call.getString("url"),
            let url = URL(string: urlValue),
            let filename = call.getString("filename")
        else {
            call.reject("title, url, and filename are required")
            return
        }

        ensureNotificationAuthorization { result in
            switch result {
            case .success:
                do {
                    let taskIdentifier = try DownloadCoordinator.shared.enqueue(
                        title: title,
                        url: url,
                        filename: filename,
                        mimetype: call.getString("mimetype")
                    )
                    call.resolve(["id": taskIdentifier])
                } catch {
                    call.reject(error.localizedDescription, nil, error)
                }
            case let .failure(error):
                call.reject(error.localizedDescription, nil, error)
            }
        }
    }

    private func ensureNotificationAuthorization(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch Self.authorizationDecision(for: settings.authorizationStatus) {
            case .allow:
                completion(.success(()))
            case .request:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        completion(.failure(error))
                    } else if granted {
                        completion(.success(()))
                    } else {
                        completion(.failure(CapDownloaderError.notificationPermissionDenied))
                    }
                }
            case .deny:
                completion(.failure(CapDownloaderError.notificationPermissionDenied))
            }
        }
    }

    static func authorizationDecision(
        for status: UNAuthorizationStatus
    ) -> DownloadNotificationAuthorizationDecision {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .allow
        case .notDetermined:
            return .request
        case .denied:
            return .deny
        @unknown default:
            return .deny
        }
    }

    public static func handleEventsForBackgroundURLSession(
        _ identifier: String,
        completionHandler: @escaping () -> Void
    ) -> Bool {
        DownloadCoordinator.shared.handleEvents(
            forBackgroundURLSession: identifier,
            completionHandler: completionHandler
        )
    }
}
