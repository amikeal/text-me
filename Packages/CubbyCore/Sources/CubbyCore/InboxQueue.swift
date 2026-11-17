import Foundation

/// Something captured outside the app (share sheet), waiting to be imported.
public struct PendingCapture: Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var source: String
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, source: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.source = source
        self.createdAt = createdAt
    }
}

/// A folder of small JSON files, one per capture.
///
/// The share extension only ever appends a file; the app reads and deletes them. Keeping the
/// extension away from the database avoids two processes writing one synced store, and keeps
/// the extension far inside its memory limit.
public struct InboxQueue: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The queue in the shared App Group container, or nil when that container is unavailable.
    public static var shared: InboxQueue? {
        AppGroup.inboxDirectory.map(InboxQueue.init(directory:))
    }

    public func enqueue(_ capture: PendingCapture) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let milliseconds = Int64((capture.createdAt.timeIntervalSince1970 * 1000).rounded())
        // Zero-padded so that sorting by file name is sorting by time.
        let stamp = String(max(0, milliseconds))
        let padded = String(repeating: "0", count: max(0, 15 - stamp.count)) + stamp
        let name = "\(padded)-\(capture.id.uuidString).json"
        let data = try JSONEncoder().encode(capture)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    /// Reads every waiting capture, oldest first, and removes the ones it could read.
    public func drain() -> [PendingCapture] {
        var captures: [PendingCapture] = []
        for file in files() {
            guard let data = try? Data(contentsOf: file),
                  let capture = try? JSONDecoder().decode(PendingCapture.self, from: data) else {
                // Unreadable files are dropped so one bad file can't block the queue forever.
                try? FileManager.default.removeItem(at: file)
                continue
            }
            captures.append(capture)
            try? FileManager.default.removeItem(at: file)
        }
        return captures
    }

    public var count: Int {
        files().count
    }

    private func files() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
