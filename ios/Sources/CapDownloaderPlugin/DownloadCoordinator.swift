import Foundation
import UserNotifications

protocol DownloadNotificationScheduling: AnyObject {
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    )
}

extension UNUserNotificationCenter: DownloadNotificationScheduling {}

enum CapDownloaderError: LocalizedError {
    case invalidURL
    case documentsDirectoryUnavailable
    case invalidHTTPResponse(Int)
    case notificationPermissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "A valid HTTP or HTTPS download URL is required."
        case .documentsDirectoryUnavailable:
            return "The app Documents directory is unavailable."
        case let .invalidHTTPResponse(statusCode):
            return "The download failed with HTTP status \(statusCode)."
        case .notificationPermissionDenied:
            return "Notification permission is required to report and open completed downloads."
        }
    }
}

public final class DownloadCoordinator: NSObject, @unchecked Sendable {
    public static let shared = DownloadCoordinator()
    public static let notificationPathKey = "capDownloaderFilePath"

    public static var backgroundSessionIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "app").cap-downloader.background"
    }

    private let fileManager: FileManager
    private let metadataStore: DownloadMetadataStore
    private let notificationCenter: DownloadNotificationScheduling
    private let sessionConfiguration: () -> URLSessionConfiguration
    private let delegateQueue: OperationQueue
    private let sessionLock = NSLock()
    private let completionLock = NSLock()
    private var storedSession: URLSession?
    private var backgroundCompletionHandler: (() -> Void)?
    private var backgroundEventsFinished = false
    private var pendingNotificationSubmissions = 0

    // URLSession may call its delegate from a Sendable context. Session creation and
    // completion state are lock-protected; download finalization is serialized by
    // delegateQueue; DownloadMetadataStore protects its own persisted state.
    private func backgroundSession() -> URLSession {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let storedSession {
            return storedSession
        }
        let configuration = sessionConfiguration()
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        storedSession = session
        return session
    }

    init(
        fileManager: FileManager = .default,
        metadataStore: DownloadMetadataStore = DownloadMetadataStore(),
        notificationCenter: DownloadNotificationScheduling = UNUserNotificationCenter.current(),
        sessionConfiguration: @escaping () -> URLSessionConfiguration = {
            URLSessionConfiguration.background(withIdentifier: DownloadCoordinator.backgroundSessionIdentifier)
        }
    ) {
        self.fileManager = fileManager
        self.metadataStore = metadataStore
        self.notificationCenter = notificationCenter
        self.sessionConfiguration = sessionConfiguration
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    func restorePendingDownloads(completion: (@Sendable () -> Void)? = nil) {
        backgroundSession().getAllTasks { _ in
            completion?()
        }
    }

    func enqueue(
        title: String,
        url: URL,
        filename: String,
        mimetype: String?
    ) throws -> Int {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw CapDownloaderError.invalidURL
        }
        _ = try downloadsDirectory()

        let task = backgroundSession().downloadTask(with: url)
        let metadata = DownloadMetadata(
            title: title,
            filename: Self.safeFilename(filename),
            mimetype: mimetype
        )
        do {
            try metadataStore.save(metadata, for: task.taskIdentifier)
        } catch {
            task.cancel()
            throw error
        }
        task.resume()
        return task.taskIdentifier
    }

    public func handleEvents(
        forBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) -> Bool {
        guard identifier == Self.backgroundSessionIdentifier else {
            return false
        }
        completionLock.lock()
        backgroundCompletionHandler = completionHandler
        backgroundEventsFinished = false
        completionLock.unlock()
        restorePendingDownloads()
        return true
    }

    static func safeFilename(_ filename: String) -> String {
        let normalized = filename.replacingOccurrences(of: "\\", with: "/")
        let lastComponent = normalized.components(separatedBy: "/").last ?? ""
        let invalidCharacters = CharacterSet(charactersIn: ":\0")
        let cleaned = lastComponent.components(separatedBy: invalidCharacters).joined(separator: "_")
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "download" : cleaned
    }

    func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let safeName = Self.safeFilename(filename)
        let base = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(safeName, isDirectory: false)
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base) (\(suffix))" : "\(base) (\(suffix)).\(ext)"
            candidate = directory.appendingPathComponent(nextName, isDirectory: false)
            suffix += 1
        }
        return candidate
    }

    private func downloadsDirectory() throws -> URL {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CapDownloaderError.documentsDirectoryUnavailable
        }
        var downloads = documents.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try downloads.setResourceValues(resourceValues)
        return downloads
    }

    private func finishDownload(task: URLSessionDownloadTask, temporaryURL: URL) throws -> URL {
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw CapDownloaderError.invalidHTTPResponse(statusCode)
        }
        guard let metadata = metadataStore.metadata(for: task.taskIdentifier) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let destination = uniqueDestination(for: metadata.filename, in: try downloadsDirectory())
        try fileManager.moveItem(at: temporaryURL, to: destination)
        var completedFile = destination
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try completedFile.setResourceValues(resourceValues)
        return destination
    }

    func scheduleNotification(
        for taskIdentifier: Int,
        metadata: DownloadMetadata?,
        fileURL: URL? = nil,
        error: Error? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = metadata?.title.isEmpty == false ? metadata!.title : metadata?.filename ?? "Download"
        if let fileURL {
            content.body = localized("Tap to open the downloaded file.", arabic: "اضغط لفتح الملف الذي تم تنزيله.")
            content.userInfo[Self.notificationPathKey] = fileURL.path
        } else {
            content.body = error?.localizedDescription ?? localized("Download failed.", arabic: "تعذر تنزيل الملف.")
        }
        content.sound = .default
        let suffix = fileURL == nil ? "failed" : "complete"
        let request = UNNotificationRequest(
            identifier: "cap-downloader-\(taskIdentifier)-\(suffix)",
            content: content,
            trigger: nil
        )
        completionLock.lock()
        pendingNotificationSubmissions += 1
        completionLock.unlock()
        notificationCenter.add(request) { [weak self] error in
            if let error {
                NSLog("CapDownloader notification scheduling failed: %@", error.localizedDescription)
            }
            self?.notificationSubmissionDidFinish()
        }
    }

    private func notificationSubmissionDidFinish() {
        completionLock.lock()
        pendingNotificationSubmissions -= 1
        let completionHandler = takeBackgroundCompletionHandlerIfReady()
        completionLock.unlock()
        runOnMain(completionHandler)
    }

    private func takeBackgroundCompletionHandlerIfReady() -> (() -> Void)? {
        guard backgroundEventsFinished, pendingNotificationSubmissions == 0 else {
            return nil
        }
        let completionHandler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        return completionHandler
    }

    private func runOnMain(_ completionHandler: (() -> Void)?) {
        guard let completionHandler else { return }
        DispatchQueue.main.async(execute: completionHandler)
    }

    private func localized(_ english: String, arabic: String) -> String {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("ar") == true ? arabic : english
    }
}

extension DownloadCoordinator: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let metadata = metadataStore.metadata(for: downloadTask.taskIdentifier)
        do {
            let fileURL = try finishDownload(task: downloadTask, temporaryURL: location)
            scheduleNotification(
                for: downloadTask.taskIdentifier,
                metadata: metadata,
                fileURL: fileURL
            )
            metadataStore.remove(taskIdentifier: downloadTask.taskIdentifier)
        } catch {
            scheduleNotification(
                for: downloadTask.taskIdentifier,
                metadata: metadata,
                error: error
            )
            metadataStore.remove(taskIdentifier: downloadTask.taskIdentifier)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let metadata = metadataStore.metadata(for: task.taskIdentifier)
        scheduleNotification(for: task.taskIdentifier, metadata: metadata, error: error)
        metadataStore.remove(taskIdentifier: task.taskIdentifier)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        completionLock.lock()
        backgroundEventsFinished = true
        let completionHandler = takeBackgroundCompletionHandlerIfReady()
        completionLock.unlock()
        runOnMain(completionHandler)
    }
}
