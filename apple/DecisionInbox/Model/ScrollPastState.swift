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
