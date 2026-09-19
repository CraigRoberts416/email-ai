import Foundation

/// Layout changes alone never count as reading. A post must cross from the
/// viewport to above it during a forward gesture. Proven passes can be drained
/// while the gesture/deceleration continues without ending its measurement.
struct ScrollPastState {
    enum Region: Equatable { case above, visible, below }
    private(set) var userScrolling = false
    private var passed: Set<String> = []
    private var startingOffset: Double?

    mutating func begin(at offset: Double? = nil) { userScrolling = true; startingOffset = offset }
    mutating func moved(_ id: String, from old: Region, to new: Region, at offset: Double? = nil) {
        let movedForward = startingOffset.map { start in offset.map { $0 > start } ?? false } ?? true
        if userScrolling && movedForward && old == .visible && new == .above { passed.insert(id) }
        if new == .visible { passed.remove(id) } // Reversing the gesture keeps the post.
    }
    mutating func finish() -> Set<String> {
        userScrolling = false
        return takePassed()
    }
    mutating func takePassed() -> Set<String> {
        defer { passed.removeAll() }
        return passed
    }
    mutating func cancel() { userScrolling = false; passed.removeAll() }
}

/// The visible countdown can acknowledge a proven pass immediately, while
/// provider writes run one at a time. Leaving cancels only work not yet sent.
struct ScrollReadQueue {
    struct Entry: Equatable {
        let key: String
        let generation: Int
    }
    private(set) var pending: [Entry] = []
    private(set) var inFlight: Entry?
    var keys: Set<String> { Set(pending.map(\.key) + [inFlight?.key].compactMap { $0 }) }

    mutating func enqueue(_ keys: [String], generation: Int) {
        var known = self.keys
        for key in keys where known.insert(key).inserted {
            pending.append(Entry(key: key, generation: generation))
        }
    }

    mutating func takeNext(generation: Int) -> Entry? {
        guard inFlight == nil else { return nil }
        pending.removeAll { $0.generation != generation }
        guard !pending.isEmpty else { return nil }
        let entry = pending.removeFirst()
        inFlight = entry
        return entry
    }

    mutating func finish(_ entry: Entry) {
        if inFlight == entry { inFlight = nil }
    }

    mutating func cancelPending() { pending.removeAll() }

    func remaining(confirmed: Int?, unreadKeys: Set<String>) -> Int? {
        // A provider/SSE confirmation may arrive before the HTTP response.
        // Only still-unread queued keys remain an optimistic subtraction.
        confirmed.map { max(0, $0 - keys.intersection(unreadKeys).count) }
    }
}
