import Capacitor
import UIKit
import UserNotifications

protocol DownloadDocumentPresenting: AnyObject {
    var presentationDidEnd: (() -> Void)? { get set }
    func present(url: URL, from viewController: UIViewController) -> Bool
}

final class UIKitDownloadDocumentPresenter: NSObject, DownloadDocumentPresenting {
    var presentationDidEnd: (() -> Void)?
    private(set) var documentController: UIDocumentInteractionController?
    private var presentingViewController: UIViewController?
    private var isPreviewing = false
    private var isSendingToApplication = false

    func present(url: URL, from viewController: UIViewController) -> Bool {
        guard documentController == nil else { return false }
        let controller = UIDocumentInteractionController(url: url)
        controller.delegate = self
        guard trackPresentation(controller, from: viewController) else { return false }
        if controller.presentPreview(animated: true) {
            return true
        }
        if controller.presentOptionsMenu(from: viewController.view.bounds, in: viewController.view, animated: true) {
            return true
        }
        finishPresentation(for: controller, notify: false)
        return false
    }

    @discardableResult
    func trackPresentation(
        _ controller: UIDocumentInteractionController,
        from viewController: UIViewController
    ) -> Bool {
        guard documentController == nil else { return false }
        documentController = controller
        presentingViewController = viewController
        isPreviewing = false
        isSendingToApplication = false
        return true
    }

    private func finishPresentation(
        for controller: UIDocumentInteractionController,
        notify: Bool = true
    ) {
        guard documentController === controller else { return }
        documentController = nil
        presentingViewController = nil
        isPreviewing = false
        isSendingToApplication = false
        if notify {
            presentationDidEnd?()
        }
    }
}

extension UIKitDownloadDocumentPresenter: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(
        _ controller: UIDocumentInteractionController
    ) -> UIViewController {
        guard let presentingViewController else {
            preconditionFailure("The document presenter must retain its presenting view controller.")
        }
        return presentingViewController
    }

    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        finishPresentation(for: controller)
    }

    func documentInteractionControllerWillBeginPreview(_ controller: UIDocumentInteractionController) {
        guard documentController === controller else { return }
        isPreviewing = true
    }

    func documentInteractionController(
        _ controller: UIDocumentInteractionController,
        willBeginSendingToApplication application: String?
    ) {
        guard documentController === controller else { return }
        isSendingToApplication = true
    }

    func documentInteractionController(
        _ controller: UIDocumentInteractionController,
        didEndSendingToApplication application: String?
    ) {
        finishPresentation(for: controller)
    }

    func documentInteractionControllerDidDismissOptionsMenu(_ controller: UIDocumentInteractionController) {
        // UIKit may dismiss the menu immediately before beginning a preview or handoff.
        // Defer cleanup one run-loop turn so those callbacks can claim the controller.
        DispatchQueue.main.async { [weak self, weak controller] in
            guard
                let self,
                let controller,
                self.documentController === controller,
                !self.isPreviewing,
                !self.isSendingToApplication
            else {
                return
            }
            self.finishPresentation(for: controller)
        }
    }
}

final class DownloadNotificationHandler: NSObject, NotificationHandlerProtocol {
    private static let maximumReadinessRetries = 20

    private let viewController: () -> UIViewController?
    private let documentPresenter: DownloadDocumentPresenting
    private let isReady: (UIViewController) -> Bool
    private let retryScheduler: (@escaping () -> Void) -> Void
    private var activeObserver: NSObjectProtocol?
    private(set) var pendingFileURL: URL?
    private var readinessRetryCount = 0
    private var retryScheduled = false

    init(
        viewController: @escaping () -> UIViewController?,
        documentPresenter: DownloadDocumentPresenting = UIKitDownloadDocumentPresenter(),
        isReady: @escaping (UIViewController) -> Bool = {
            $0.viewIfLoaded?.window != nil && UIApplication.shared.applicationState == .active
        },
        retryScheduler: @escaping (@escaping () -> Void) -> Void = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: $0)
        }
    ) {
        self.viewController = viewController
        self.documentPresenter = documentPresenter
        self.isReady = isReady
        self.retryScheduler = retryScheduler
        super.init()
        documentPresenter.presentationDidEnd = { [weak self] in
            self?.attemptPendingFileOpen()
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.readinessRetryCount = 0
            self?.attemptPendingFileOpen()
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    func willPresent(notification: UNNotification) -> UNNotificationPresentationOptions {
        Self.presentationOptions(for: notification.request.identifier)
    }

    static func presentationOptions(for identifier: String) -> UNNotificationPresentationOptions {
        guard identifier.hasPrefix("cap-downloader-") else { return [] }
        return [.banner, .list, .sound]
    }

    func didReceive(response: UNNotificationResponse) {
        guard
            response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            response.notification.request.identifier.hasPrefix("cap-downloader-"),
            let path = response.notification.request.content.userInfo[
                DownloadCoordinator.notificationPathKey
            ] as? String
        else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.queueFileForOpening(at: URL(fileURLWithPath: path))
        }
    }

    func queueFileForOpening(at url: URL) {
        pendingFileURL = url
        readinessRetryCount = 0
        attemptPendingFileOpen()
    }

    func attemptPendingFileOpen() {
        guard let pendingFileURL else { return }
        guard FileManager.default.fileExists(atPath: pendingFileURL.path) else {
            self.pendingFileURL = nil
            retryScheduled = false
            return
        }
        guard let viewController = viewController(), isReady(viewController) else {
            scheduleReadinessRetry()
            return
        }
        if documentPresenter.present(url: pendingFileURL, from: viewController) {
            self.pendingFileURL = nil
            readinessRetryCount = 0
            retryScheduled = false
        } else {
            scheduleReadinessRetry()
        }
    }

    private func scheduleReadinessRetry() {
        guard
            !retryScheduled,
            readinessRetryCount < Self.maximumReadinessRetries
        else {
            return
        }
        readinessRetryCount += 1
        retryScheduled = true
        retryScheduler { [weak self] in
            self?.retryScheduled = false
            self?.attemptPendingFileOpen()
        }
    }
}
