import Foundation

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var urlString: String
    var title: String
    var visitedAt: Date

    init(id: UUID = UUID(), urlString: String, title: String, visitedAt: Date) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.visitedAt = visitedAt
    }
}
