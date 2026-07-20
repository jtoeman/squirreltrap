import Foundation

struct IntentEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var completed: Bool
    var completedAt: Date?
    var favorite: Bool
    var reminderDate: Date?
    /// The linked EKReminder.calendarItemIdentifier, if this entry has ever
    /// been synced to Apple Reminders. Nil means never synced.
    var reminderSyncID: String?
    /// Bumped on completion toggle, or when a Reminders-side edit is pulled
    /// in — compared against EKReminder.lastModifiedDate to resolve
    /// bidirectional sync conflicts ("most recent change wins"). Also reused
    /// for iCloud sync conflict resolution against CKRecord.modificationDate.
    var lastModifiedAt: Date
    /// Cross-device display order for iCloud sync — array position alone
    /// isn't something CloudKit can represent, so this fractional rank
    /// (assign a value between two neighbors when reordering) is the actual
    /// source of truth for order once synced. IntentStore keeps the local
    /// array sorted to match after every pull.
    var sortRank: Double

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        completed: Bool = false,
        completedAt: Date? = nil,
        favorite: Bool = false,
        reminderDate: Date? = nil,
        reminderSyncID: String? = nil,
        lastModifiedAt: Date? = nil,
        sortRank: Double = 0
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.completed = completed
        self.completedAt = completedAt
        self.favorite = favorite
        self.reminderDate = reminderDate
        self.reminderSyncID = reminderSyncID
        self.lastModifiedAt = lastModifiedAt ?? createdAt
        self.sortRank = sortRank
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, completed, completedAt, favorite, reminderDate
        case reminderSyncID, lastModifiedAt, sortRank
    }

    // Custom decoder so entries.json files saved before `favorite`/`reminderDate`
    // (or reminderSyncID/lastModifiedAt/sortRank) existed still load instead of
    // the whole history silently disappearing. sortRank defaults to 0 here —
    // IntentStore.load() normalizes it from array position right after decoding,
    // since pre-existing files don't have a meaningful rank yet.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completed = try container.decode(Bool.self, forKey: .completed)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        reminderDate = try container.decodeIfPresent(Date.self, forKey: .reminderDate)
        reminderSyncID = try container.decodeIfPresent(String.self, forKey: .reminderSyncID)
        lastModifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastModifiedAt) ?? createdAt
        sortRank = try container.decodeIfPresent(Double.self, forKey: .sortRank) ?? 0
    }
}
