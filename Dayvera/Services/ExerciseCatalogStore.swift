import Combine
import Foundation

@MainActor
final class ExerciseCatalogStore: ObservableObject {
    static let shared = ExerciseCatalogStore()

    @Published private(set) var exercises: [ExerciseDefinition] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadedAt: Date?

    private let session: URLSession
    private let fileManager: FileManager
    private let cacheURL: URL

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheURL = support
            .appendingPathComponent("Dayvera", isDirectory: true)
            .appendingPathComponent("exercise-catalog-v3.json")
        let legacyURL = support.appendingPathComponent(LegacyCompatibility.catalogDirectory)
            .appendingPathComponent("exercise-catalog-v3.json")
        if !fileManager.fileExists(atPath: cacheURL.path),
           let data = try? Data(contentsOf: legacyURL),
           let catalog = try? ExerciseCatalogDecoder.decode(data), catalog.count >= 100 {
            do {
                try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cacheURL, options: .atomic)
                // Keep the old cache until a later cleanup; interrupted copies are harmless.
            } catch { /* The normal catalog fetch remains available. */ }
        }
        URLCache.shared.memoryCapacity = max(URLCache.shared.memoryCapacity, 32 * 1_024 * 1_024)
        URLCache.shared.diskCapacity = max(URLCache.shared.diskCapacity, 160 * 1_024 * 1_024)
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        if !forceRefresh, !exercises.isEmpty { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if !forceRefresh,
           let cached = try? Data(contentsOf: cacheURL),
           let decoded = try? ExerciseCatalogDecoder.decode(cached),
           decoded.count >= 100 {
            exercises = decoded
            loadedAt = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            return
        }

        do {
            var request = URLRequest(url: ExerciseCatalogSource.catalogURL)
            request.timeoutInterval = 25
            request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                throw ExerciseCatalogError.invalidResponse
            }
            let decoded = try await Task.detached(priority: .userInitiated) {
                try ExerciseCatalogDecoder.decode(data)
            }.value
            guard decoded.count >= 100 else { throw ExerciseCatalogError.incomplete(decoded.count) }
            try persist(data)
            exercises = decoded
            loadedAt = .now
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist(_ data: Data) throws {
        let directory = cacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
    }
}
