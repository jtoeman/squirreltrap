import Foundation

struct IntentEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var completed: Bool
    var completedAt: Date?
    var favorite: Bool

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        completed: Bool = false,
        completedAt: Date? = nil,
        favorite: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.completed = completed
        self.completedAt = completedAt
        self.favorite = favorite
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, completed, completedAt, favorite
    }

    // Custom decoder so entries.json files saved before `favorite` existed
    // still load instead of the whole history silently disappearing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completed = try container.decode(Bool.self, forKey: .completed)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    }
}
