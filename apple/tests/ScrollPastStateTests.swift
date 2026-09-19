import Foundation

@main struct ScrollPastStateTests {
    static func main() {
        var state = ScrollPastState()
        state.moved("a", from: .visible, to: .above)
        precondition(state.finish().isEmpty, "Layout alone cannot consume a post")
        state.begin()
        state.moved("a", from: .below, to: .visible)
        precondition(state.finish().isEmpty, "Entering the screen does not consume a post")
        state.begin()
        state.moved("a", from: .visible, to: .above)
        state.moved("a", from: .above, to: .visible)
        precondition(state.finish().isEmpty, "Reversing back to a post keeps it")
        state.begin()
        state.moved("a", from: .visible, to: .above)
        state.moved("b", from: .visible, to: .above)
        precondition(state.finish() == ["a", "b"], "Every passed post commits once at rest")
        precondition(state.finish().isEmpty, "A resting feed cannot replay a commit")
        state.begin()
        state.moved("a", from: .visible, to: .above)
        state.cancel()
        precondition(state.finish().isEmpty, "Leaving the screen cancels uncommitted passes")
        state.begin(at: 200)
        state.moved("layout", from: .visible, to: .above, at: 200)
        precondition(state.finish().isEmpty, "A layout change without forward displacement does not consume")
        state.begin(at: 200)
        state.moved("scroll", from: .visible, to: .above, at: 300)
        precondition(state.finish() == ["scroll"], "A forward gesture can consume")
        print("8 scroll-past behavior checks passed")
    }
}
