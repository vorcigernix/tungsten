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
        if let question = turns.first(where: { $0.kind == .userQuestion }),
           question.text.isEmpty == false {
            return question.text
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
        guard let activePageTurnID else {
            return nil
        }

        return turns.first { $0.id == activePageTurnID && $0.kind == .page }
    }

    @discardableResult
    mutating func appendQuestion(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn {
        append(BrowserTurn.question(text, id: id, createdAt: createdAt))
    }

    @discardableResult
    mutating func appendAssistantResponse(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn {
        append(BrowserTurn.assistant(text, id: id, createdAt: createdAt))
    }

    @discardableResult
    mutating func appendSystemMessage(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn {
        append(BrowserTurn.system(text, id: id, createdAt: createdAt))
    }

    @discardableResult
    mutating func appendPage(
        urlString: String,
        title: String? = nil,
        faviconURLString: String? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> BrowserTurn {
        let turn = BrowserTurn.page(
            urlString: urlString,
            title: title,
            faviconURLString: faviconURLString,
            id: id,
            createdAt: createdAt
        )
        return append(turn)
    }

    mutating func activatePageTurn(_ id: UUID) {
        guard turns.contains(where: { $0.id == id && $0.kind == .page }) else {
            return
        }

        activePageTurnID = id
    }

    mutating func updatePageMetadata(
        turnID: UUID,
        title: String? = nil,
        faviconURLString: String? = nil,
        updatedAt: Date = Date()
    ) {
        guard let index = turns.firstIndex(where: { $0.id == turnID && $0.kind == .page }) else {
            return
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

    @discardableResult
    private mutating func append(_ turn: BrowserTurn) -> BrowserTurn {
        turns.append(turn)
        updatedAt = turn.createdAt

        if turn.kind == .page {
            activePageTurnID = turn.id
        }

        return turn
    }
}
