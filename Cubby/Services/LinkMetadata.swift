import Foundation
import LinkPresentation

/// Fetches a page title for a saved link. This is the only network request the app makes itself.
@MainActor
enum LinkMetadata {
    static func title(for url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 12
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? nil : title
        } catch {
            return nil
        }
    }
}
