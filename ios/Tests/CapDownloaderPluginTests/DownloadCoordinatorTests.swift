import XCTest
import UIKit
import UserNotifications
@testable import BricksSoftCapDownloader

final class DownloadCoordinatorTests: XCTestCase {
    func testSafeFilenameRemovesPathTraversalAndSeparators() {
        XCTAssertEqual(DownloadCoordinator.safeFilename("../report.xlsx"), "report.xlsx")
        XCTAssertEqual(DownloadCoordinator.safeFilename("folder\\report.xlsx"), "report.xlsx")
        XCTAssertEqual(DownloadCoordinator.safeFilename(".."), "download")
        XCTAssertEqual(DownloadCoordinator.safeFilename("."), "download")
        XCTAssertEqual(DownloadCoordinator.safeFilename(""), "download")
        XCTAssertEqual(DownloadCoordinator.safeFilename("/"), "download")
        XCTAssertEqual(DownloadCoordinator.safeFilename("folder/"), "download")
        XCTAssertEqual(DownloadCoordinator.safeFilename("folder/../"), "download")
        XCTAssertEqual(DownloadCoordinator.safeFilename("folder\\//report.xlsx"), "report.xlsx")
        XCTAssertEqual(DownloadCoordinator.safeFilename("report:final.xlsx"), "report_final.xlsx")
        XCTAssertEqual(DownloadCoordinator.safeFilename("report\0final.xlsx"), "report_final.xlsx")
        XCTAssertEqual(DownloadCoordinator.safeFilename("تقرير نهائي.xlsx"), "تقرير نهائي.xlsx")

        let sanitized = DownloadCoordinator.safeFilename("../report:final.xlsx")
        XCTAssertEqual(DownloadCoordinator.safeFilename(sanitized), sanitized)
    }

    func testUniqueDestinationPreservesExtension() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("report.xlsx")
        XCTAssertTrue(FileManager.default.createFile(atPath: existing.path, contents: Data()))

        let coordinator = DownloadCoordinator(notificationCenter: NotificationSchedulerSpy())
        XCTAssertEqual(
            coordinator.uniqueDestination(for: "report.xlsx", in: directory).lastPathComponent,
            "report (1).xlsx"
        )
    }

    func testMetadataPersistsAcrossStoreInstances() throws {
        let suiteName = "CapDownloaderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = DownloadMetadata(
            title: "Report",
            filename: "report.xlsx",
            mimetype: "application/octet-stream"
        )

        try DownloadMetadataStore(defaults: defaults).save(metadata, for: 42)

        let restored = DownloadMetadataStore(defaults: defaults).metadata(for: 42)
        XCTAssertEqual(restored?.title, metadata.title)
        XCTAssertEqual(restored?.filename, metadata.filename)
        XCTAssertEqual(restored?.mimetype, metadata.mimetype)
    }

    func testNotificationAuthorizationDecisions() {
        XCTAssertEqual(CapDownloaderPlugin.authorizationDecision(for: .authorized), .allow)
        XCTAssertEqual(CapDownloaderPlugin.authorizationDecision(for: .provisional), .allow)
        XCTAssertEqual(CapDownloaderPlugin.authorizationDecision(for: .ephemeral), .allow)
        XCTAssertEqual(CapDownloaderPlugin.authorizationDecision(for: .notDetermined), .request)
        XCTAssertEqual(CapDownloaderPlugin.authorizationDecision(for: .denied), .deny)
    }

    func testForegroundDownloadNotificationsRemainAvailableInNotificationCenter() {
        let options = DownloadNotificationHandler.presentationOptions(
            for: "cap-downloader-42-complete"
        )
        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.list))
        XCTAssertTrue(options.contains(.sound))
        XCTAssertTrue(
            DownloadNotificationHandler.presentationOptions(for: "unrelated").isEmpty
        )
    }

    func testBackgroundCompletionWaitsForAllNotificationSubmissions() {
        let notificationCenter = NotificationSchedulerSpy()
        let coordinator = DownloadCoordinator(
            notificationCenter: notificationCenter,
            sessionConfiguration: { .ephemeral }
        )
        let completion = expectation(description: "background completion")
        var completionCount = 0
        XCTAssertTrue(
            coordinator.handleEvents(
                forBackgroundURLSession: DownloadCoordinator.backgroundSessionIdentifier
            ) {
                XCTAssertTrue(Thread.isMainThread)
                completionCount += 1
                completion.fulfill()
            }
        )

        coordinator.scheduleNotification(for: 1, metadata: nil, error: TestError.expected)
        coordinator.scheduleNotification(for: 2, metadata: nil, error: TestError.expected)
        coordinator.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
        XCTAssertEqual(completionCount, 0)

        notificationCenter.completeRequest(at: 0)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(completionCount, 0)

        notificationCenter.completeRequest(at: 1, error: TestError.expected)
        wait(for: [completion], timeout: 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testConcurrentSessionRestorationCompletesEveryRequest() {
        let coordinator = DownloadCoordinator(
            notificationCenter: NotificationSchedulerSpy(),
            sessionConfiguration: { .ephemeral }
        )
        let completion = expectation(description: "session restoration")
        completion.expectedFulfillmentCount = 20

        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            coordinator.restorePendingDownloads {
                completion.fulfill()
            }
        }

        wait(for: [completion], timeout: 2)
    }

    func testNotificationFileOpeningWaitsForPresenterReadiness() throws {
        let fileURL = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let presenter = DocumentPresenterSpy(results: [true])
        var viewController: UIViewController?
        var retry: (() -> Void)?
        let handler = DownloadNotificationHandler(
            viewController: { viewController },
            documentPresenter: presenter,
            isReady: { _ in true },
            retryScheduler: { retry = $0 }
        )

        handler.queueFileForOpening(at: fileURL)
        XCTAssertEqual(handler.pendingFileURL, fileURL)
        XCTAssertEqual(presenter.presentedURLs, [])

        viewController = UIViewController()
        retry?()
        XCTAssertNil(handler.pendingFileURL)
        XCTAssertEqual(presenter.presentedURLs, [fileURL])
    }

    func testNotificationFileOpeningRetriesFailedPresentationAndDropsMissingFile() throws {
        let fileURL = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let presenter = DocumentPresenterSpy(results: [false, true])
        var retries: [() -> Void] = []
        let handler = DownloadNotificationHandler(
            viewController: { UIViewController() },
            documentPresenter: presenter,
            isReady: { _ in true },
            retryScheduler: { retries.append($0) }
        )

        handler.queueFileForOpening(at: fileURL)
        XCTAssertEqual(handler.pendingFileURL, fileURL)
        XCTAssertEqual(presenter.presentedURLs, [fileURL])
        XCTAssertEqual(retries.count, 1)

        retries.removeFirst()()
        XCTAssertNil(handler.pendingFileURL)
        XCTAssertEqual(presenter.presentedURLs, [fileURL, fileURL])

        handler.queueFileForOpening(at: fileURL.appendingPathExtension("missing"))
        XCTAssertNil(handler.pendingFileURL)
        XCTAssertEqual(retries.count, 0)
    }

    func testDocumentPresenterClearsMenuOnlyPresentation() throws {
        let firstURL = try temporaryFile()
        let secondURL = try temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let presenter = UIKitDownloadDocumentPresenter()
        let firstController = UIDocumentInteractionController(url: firstURL)
        let secondController = UIDocumentInteractionController(url: secondURL)
        let viewController = UIViewController()
        var presentationEndCount = 0
        presenter.presentationDidEnd = { presentationEndCount += 1 }

        XCTAssertTrue(presenter.trackPresentation(firstController, from: viewController))
        XCTAssertFalse(presenter.trackPresentation(secondController, from: viewController))
        presenter.documentInteractionControllerDidDismissOptionsMenu(firstController)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNil(presenter.documentController)
        XCTAssertEqual(presentationEndCount, 1)
        XCTAssertTrue(presenter.trackPresentation(secondController, from: viewController))
    }

    func testSecondNotificationWaitsUntilActivePresentationEnds() throws {
        let firstURL = try temporaryFile()
        let secondURL = try temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let presenter = BusyDocumentPresenterSpy()
        let handler = DownloadNotificationHandler(
            viewController: { UIViewController() },
            documentPresenter: presenter,
            isReady: { _ in true },
            retryScheduler: { _ in }
        )

        handler.queueFileForOpening(at: firstURL)
        handler.queueFileForOpening(at: secondURL)
        XCTAssertEqual(handler.pendingFileURL, secondURL)
        XCTAssertEqual(presenter.presentedURLs, [firstURL, secondURL])

        presenter.finishPresentation()
        XCTAssertNil(handler.pendingFileURL)
        XCTAssertEqual(presenter.presentedURLs, [firstURL, secondURL, secondURL])
    }

    func testDocumentPresenterIgnoresStaleDismissalAndPreservesApplicationHandoff() throws {
        let firstURL = try temporaryFile()
        let secondURL = try temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let presenter = UIKitDownloadDocumentPresenter()
        let firstController = UIDocumentInteractionController(url: firstURL)
        let secondController = UIDocumentInteractionController(url: secondURL)
        let viewController = UIViewController()

        XCTAssertTrue(presenter.trackPresentation(firstController, from: viewController))
        presenter.documentInteractionController(
            firstController,
            willBeginSendingToApplication: "test.application"
        )
        presenter.documentInteractionControllerDidDismissOptionsMenu(firstController)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertTrue(presenter.documentController === firstController)

        presenter.documentInteractionController(
            firstController,
            didEndSendingToApplication: "test.application"
        )
        XCTAssertTrue(presenter.trackPresentation(secondController, from: viewController))
        presenter.documentInteractionControllerDidEndPreview(firstController)
        XCTAssertTrue(presenter.documentController === secondController)
    }

    private func temporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8)))
        return url
    }
}

private enum TestError: Error {
    case expected
}

private final class NotificationSchedulerSpy: DownloadNotificationScheduling {
    private(set) var requests: [UNNotificationRequest] = []
    private var completions: [(@Sendable (Error?) -> Void)?] = []

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    ) {
        requests.append(request)
        completions.append(completionHandler)
    }

    func completeRequest(at index: Int, error: Error? = nil) {
        completions[index]?(error)
    }
}

private final class DocumentPresenterSpy: DownloadDocumentPresenting {
    var presentationDidEnd: (() -> Void)?
    private var results: [Bool]
    private(set) var presentedURLs: [URL] = []

    init(results: [Bool]) {
        self.results = results
    }

    func present(url: URL, from viewController: UIViewController) -> Bool {
        presentedURLs.append(url)
        return results.removeFirst()
    }
}

private final class BusyDocumentPresenterSpy: DownloadDocumentPresenting {
    var presentationDidEnd: (() -> Void)?
    private(set) var presentedURLs: [URL] = []
    private var isPresenting = false

    func present(url: URL, from viewController: UIViewController) -> Bool {
        presentedURLs.append(url)
        guard !isPresenting else { return false }
        isPresenting = true
        return true
    }

    func finishPresentation() {
        isPresenting = false
        presentationDidEnd?()
    }
}
