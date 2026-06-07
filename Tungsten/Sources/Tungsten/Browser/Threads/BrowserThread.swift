import Foundation

struct BrowserThread: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var turns: [BrowserTurn]
    var activePageTurnID: UUID?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        turns: [BrowserTurn] = [],
        activePageTurnID: UUID? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.turns = turns
        self.activePageTurnID = activePageTurnID
        self.isPinned = isPinned
    }

    var displayTitle: String {
        if let question = turns.first(where: { $0.kind == .userQuestion }) {
            let title = question.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty == false {
                return String(title.prefix(64))
            }
        }

        if let page = turns.first(where: { $0.kind == .page }) {
            if let urlString = page.urlString,
               let host = URL(string: urlString)?.host,
               host.isEmpty == false {
                return host
            }

            return page.displayTitle
        }

        return "New Thread"
    }

    var activePageTurn: BrowserTurn? {
        if let activePageTurnID,
           let turn = turns.first(where: { $0.id == activePageTurnID && $0.kind == .page }) {
            return turn
        }

        return turns.last { $0.kind == .page }
    }

    var sanitizedForPersistence: BrowserThread {
        var thread = self
        thread.turns = turns.map(\.sanitizedForPersistence)
        return thread
    }

    @discardableResult
    mutating func appendQuestion(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn.ID {
        append(BrowserTurn.question(text, id: id, createdAt: createdAt))
    }

    @discardableResult
    mutating func appendAssistantResponse(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn.ID {
        append(BrowserTurn.assistant(text, id: id, createdAt: createdAt))
    }

    @discardableResult
    mutating func appendSystemMessage(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn.ID {
        append(BrowserTurn.system(text, id: id, createdAt: createdAt))
    }

    @discardableResult
    mutating func appendPage(
        urlString: String,
        title: String? = nil,
        faviconURLString: String? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn.ID {
        let turn = BrowserTurn.page(
            urlString: urlString,
            title: title,
            faviconURLString: faviconURLString,
            id: id,
            createdAt: createdAt
        )
        return append(turn)
    }

    mutating func activatePageTurn(_ id: UUID, updatedAt: Date = Date()) {
        guard turns.contains(where: { $0.id == id && $0.kind == .page }) else {
            return
        }

        activePageTurnID = id
        self.updatedAt = updatedAt
    }

    mutating func updatePageMetadata(
        turnID: UUID,
        urlString: String? = nil,
        title: String? = nil,
        faviconURLString: String? = nil,
        updatedAt: Date = Date()
    ) {
        guard let index = turns.firstIndex(where: { $0.id == turnID && $0.kind == .page }) else {
            return
        }

        if let urlString {
            turns[index].urlString = urlString
            if turns[index].title == nil {
                turns[index].text = urlString
            }
        }

        if let title {
            turns[index].title = title
            turns[index].text = title
        }

        if let faviconURLString {
            turns[index].faviconURLString = faviconURLString
        }

        self.updatedAt = updatedAt
    }

    mutating func updateTurnText(
        turnID: UUID,
        text: String,
        updatedAt: Date = Date()
    ) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else {
            return
        }

        turns[index].text = text
        self.updatedAt = updatedAt
    }

    @discardableResult
    private mutating func append(_ turn: BrowserTurn) -> BrowserTurn.ID {
        turns.append(turn)
        updatedAt = turn.createdAt

        if turn.kind == .page {
            activePageTurnID = turn.id
        }

        return turn.id
    }
}
