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

    /// Last N entries. `entries` is maintained in display order directly (new
    /// ones inserted at the front, pending ones manually reorderable via
    /// movePendingEntry) rather than re-sorted here, so drag-to-reorder in the
    /// UI actually sticks. Everything else stays on disk indefinitely.
    var visibleEntries: [IntentEntry] {
        Array(entries.prefix(visibleLimit))
    }

    /// All favorited entries, newest first — a curated list the user maintains
    /// explicitly, so it isn't subject to the rolling display window.
    var favoriteEntries: [IntentEntry] {
        entries.filter { $0.favorite }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func add(text: String) -> IntentEntry {
        let entry = IntentEntry(text: text)
        entries.insert(entry, at: 0)
        save()
        return entry
    }

    /// Moves a pending entry to sit immediately before another one — the only
    /// mutation drag-to-reorder needs. Leaves every other entry's relative
    /// order (completed items, anything outside the visible window) untouched.
    func movePendingEntry(id draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID,
              let draggedIndex = entries.firstIndex(where: { $0.id == draggedID }),
              !entries[draggedIndex].completed else { return }
        let draggedEntry = entries.remove(at: draggedIndex)
        guard let targetIndex = entries.firstIndex(where: { $0.id == targetID }) else {
            entries.insert(draggedEntry, at: draggedIndex)
            return
        }
        entries.insert(draggedEntry, at: targetIndex)
        save()
    }

    /// Moves a pending entry to sit after every other pending entry — every row
    /// only offers "drop before me", so without this there's no way to drop
    /// something at the very bottom of the pending list.
    func movePendingEntryToEnd(id draggedID: UUID) {
        guard let draggedIndex = entries.firstIndex(where: { $0.id == draggedID }),
              !entries[draggedIndex].completed else { return }
        let draggedEntry = entries.remove(at: draggedIndex)
        if let lastPendingIndex = entries.lastIndex(where: { !$0.completed }) {
            entries.insert(draggedEntry, at: lastPendingIndex + 1)
        } else {
            entries.insert(draggedEntry, at: 0)
        }
        save()
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

    /// Returns the IDs actually removed, so the caller can cancel any live
    /// reminder Timers for them — IntentStore only owns the persisted data,
    /// not the scheduler, so it can't cancel those itself.
    @discardableResult
    func clearCompleted() -> [UUID] {
        let removedIDs = entries.filter { $0.completed }.map(\.id)
        entries.removeAll { $0.completed }
        save()
        return removedIDs
    }

    @discardableResult
    func clearAll() -> [UUID] {
        let removedIDs = entries.map(\.id)
        entries.removeAll()
        save()
        return removedIDs
    }

    func setReminder(id: UUID, date: Date?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].reminderDate = date
        save()
    }

    /// Every entry with a pending reminder, regardless of the rolling display
    /// window — used both to restore timers on launch and to list them in the
    /// menu bar.
    var entriesWithActiveReminders: [IntentEntry] {
        entries.filter { $0.reminderDate != nil }
    }

    /// Open (not-yet-completed) items only, full history rather than just the
    /// last-20 rolling window. "completed"/"completedAt" columns are dropped
    /// since every exported row is open by definition — they'd just be constant.
    func csvExport() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["text,favorite,createdAt"]
        for entry in entries.filter({ !$0.completed }).sorted(by: { $0.createdAt < $1.createdAt }) {
            let fields = [
                csvField(entry.text),
                csvField(entry.favorite ? "true" : "false"),
                csvField(formatter.string(from: entry.createdAt))
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
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
