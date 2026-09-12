import Foundation

struct DownloadMetadata: Codable {
    let title: String
    let filename: String
    let mimetype: String?
}

final class DownloadMetadataStore {
    private let defaults: UserDefaults
    private let key = "CapDownloader.pendingDownloads"
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func metadata(for taskIdentifier: Int) -> DownloadMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return all()[String(taskIdentifier)]
    }

    func save(_ metadata: DownloadMetadata, for taskIdentifier: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        var downloads = all()
        downloads[String(taskIdentifier)] = metadata
        let data = try JSONEncoder().encode(downloads)
        defaults.set(data, forKey: key)
    }

    func remove(taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        var downloads = all()
        downloads.removeValue(forKey: String(taskIdentifier))
        if let data = try? JSONEncoder().encode(downloads) {
            defaults.set(data, forKey: key)
        }
    }

    private func all() -> [String: DownloadMetadata] {
        guard
            let data = defaults.data(forKey: key),
            let downloads = try? JSONDecoder().decode([String: DownloadMetadata].self, from: data)
        else {
            return [:]
        }
        return downloads
    }
}
