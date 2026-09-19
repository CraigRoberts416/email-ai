import Foundation

/// Each async operation may release only the busy state it acquired. A new
/// visit can start immediately even while old network work is winding down.
struct FeedPaginationLifecycle {
    struct Ticket: Equatable {
        let id = UUID()
        let generation: Int
    }

    private var run: Ticket?
    private var pages: [String: Ticket] = [:]

    func isLoading(generation: Int) -> Bool { run?.generation == generation }

    mutating func beginRun(generation: Int) -> Ticket? {
        guard !isLoading(generation: generation) else { return nil }
        let ticket = Ticket(generation: generation)
        run = ticket
        return ticket
    }

    mutating func finishRun(_ ticket: Ticket) {
        if run == ticket { run = nil }
    }

    mutating func beginPage(account: String, generation: Int, expectedGeneration: Int?) -> Ticket? {
        guard expectedGeneration == nil || expectedGeneration == generation,
              pages[account]?.generation != generation else { return nil }
        let ticket = Ticket(generation: generation)
        pages[account] = ticket
        return ticket
    }

    mutating func finishPage(account: String, ticket: Ticket) {
        if pages[account] == ticket { pages.removeValue(forKey: account) }
    }

    mutating func reset() {
        run = nil
        pages.removeAll()
    }
}
