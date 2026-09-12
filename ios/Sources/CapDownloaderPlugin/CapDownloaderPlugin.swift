import Capacitor
import Foundation
import UserNotifications

enum DownloadNotificationAuthorizationDecision: Equatable {
    case allow
    case request
    case deny
}

final class DownloadNotificationAuthorizationCoordinator {
    typealias StatusProvider = (@escaping (UNAuthorizationStatus) -> Void) -> Void
    typealias AuthorizationRequester = (@escaping (Bool, Error?) -> Void) -> Void

    private let lock = NSLock()
    private let statusProvider: StatusProvider
    private let authorizationRequester: AuthorizationRequester
    private var isCheckingAuthorization = false
    private var completions: [(Result<Void, Error>) -> Void] = []

    convenience init(center: UNUserNotificationCenter = .current()) {
        self.init(
            statusProvider: { completion in
                center.getNotificationSettings { settings in
                    completion(settings.authorizationStatus)
                }
            },
            authorizationRequester: { completion in
                center.requestAuthorization(
                    options: [.alert, .sound],
                    completionHandler: completion
                )
            }
        )
    }

    init(
        statusProvider: @escaping StatusProvider,
        authorizationRequester: @escaping AuthorizationRequester
    ) {
        self.statusProvider = statusProvider
        self.authorizationRequester = authorizationRequester
    }

    func ensureAuthorization(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        lock.lock()
        completions.append(completion)
        guard !isCheckingAuthorization else {
            lock.unlock()
            return
        }
        isCheckingAuthorization = true
        lock.unlock()

        statusProvider { status in
            switch CapDownloaderPlugin.authorizationDecision(for: status) {
            case .allow:
                self.finish(with: .success(()))
            case .request:
                self.authorizationRequester { granted, error in
                    if let error {
                        self.finish(with: .failure(error))
                    } else if granted {
                        self.finish(with: .success(()))
                    } else {
                        self.finish(
                            with: .failure(CapDownloaderError.notificationPermissionDenied)
                        )
                    }
                }
            case .deny:
                self.finish(with: .failure(CapDownloaderError.notificationPermissionDenied))
            }
        }
    }

    private func finish(with result: Result<Void, Error>) {
        lock.lock()
        let pendingCompletions = completions
        completions.removeAll()
        isCheckingAuthorization = false
        lock.unlock()

        pendingCompletions.forEach { $0(result) }
    }
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
    private let notificationAuthorization = DownloadNotificationAuthorizationCoordinator()

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

        notificationAuthorization.ensureAuthorization { result in
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
