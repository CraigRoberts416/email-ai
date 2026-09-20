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
        state.begin(at: 100)
        state.moved("first", from: .visible, to: .above, at: 200)
        state.cancel() // A card or viewport changed size during this gesture.
        state.moved("after-resize", from: .visible, to: .above, at: 300)
        precondition(state.finish().isEmpty, "Unexpected layout invalidates the whole gesture, including later geometry callbacks")

        state.begin(at: 100)
        state.moved("read", from: .visible, to: .above, at: 200)
        precondition(state.finish() == ["read"], "Commit measured passes before releasing held content")
        state.moved("completed-content", from: .visible, to: .above, at: 350)
        precondition(state.finish().isEmpty, "Releasing deferred completion cannot generate extra reads even if content offset changes")

        state.begin(at: 100)
        state.moved("interrupted-fling", from: .visible, to: .above, at: 200)
        state.cancel() // A new touch interrupts deceleration before idle.
        state.begin(at: 200)
        state.moved("new-gesture", from: .visible, to: .above, at: 300)
        precondition(state.finish() == ["new-gesture"], "An interrupted gesture cannot leak candidates into the next touch")
        livePasses()
        print("Scroll-past gesture evidence checks passed")
    }

    static func livePasses() {
        var state = ScrollPastState()
        state.begin(at: 100)
        state.moved("a", from: .visible, to: .above, at: 200)
        precondition(state.takePassed() == ["a"] && state.userScrolling,
                     "A fully passed post is available before scrolling stops")
        precondition(state.takePassed().isEmpty, "Draining never replays a proven pass")
        state.moved("b", from: .visible, to: .above, at: 300)
        precondition(state.takePassed() == ["b"], "The same gesture can prove later posts")
        state.moved("c", from: .visible, to: .above, at: 400)
        precondition(state.finish() == ["c"] && !state.userScrolling,
                     "Finish still returns any final undrained evidence")
        precondition(state.takePassed().isEmpty, "Finishing drains the final pass exactly once")

        state.begin(at: 400)
        state.moved("resize", from: .visible, to: .above, at: 400)
        precondition(state.takePassed().isEmpty, "Live draining does not weaken the forward-motion guard")
        state.moved("cancelled", from: .visible, to: .above, at: 500)
        state.cancel()
        precondition(state.takePassed().isEmpty, "Cancellation clears unconsumed geometry evidence")
    }

}
