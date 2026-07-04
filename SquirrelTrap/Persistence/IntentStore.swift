import Foundation

@MainActor
final class IntentStore: ObservableObject {
    @Published private(set) var entries: [IntentEntry] = []

    private let visibleLimit = 20
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let supportDir = appSupport.appendingPathComponent("SquirrelTrap", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        fileURL = supportDir.appendingPathComponent("entries.json")

        // One-time migration from the app's previous name (SwitchLog) so history
        // logged before the rename isn't silently orphaned. Copy, not move — leaves
        // the old file in place rather than risking loss on a failed copy.
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let oldFileURL = appSupport
                .appendingPathComponent("SwitchLog", isDirectory: true)
                .appendingPathComponent("entries.json")
            try? FileManager.default.copyItem(at: oldFileURL, to: fileURL)
        }

        load()
    }

    /// Last N entries, newest first. Everything else stays on disk indefinitely.
    var visibleEntries: [IntentEntry] {
        Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(visibleLimit))
    }

    /// All favorited entries, newest first — a curated list the user maintains
    /// explicitly, so it isn't subject to the rolling display window.
    var favoriteEntries: [IntentEntry] {
        entries.filter { $0.favorite }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func add(text: String) -> IntentEntry {
        let entry = IntentEntry(text: text)
        entries.append(entry)
        save()
        return entry
    }

    func toggleCompleted(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].completed.toggle()
        entries[index].completedAt = entries[index].completed ? Date() : nil
        save()
    }

    func toggleFavorite(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].favorite.toggle()
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([IntentEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
