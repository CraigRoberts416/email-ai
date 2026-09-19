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
        queuedCountdown()
        print("Scroll-past and serial read-countdown behavior checks passed")
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

    static func queuedCountdown() {
        var queue = ScrollReadQueue()
        queue.enqueue(["a", "b", "a"], generation: 1)
        precondition(queue.pending.map(\.key) == ["a", "b"], "Duplicate callbacks enqueue once in display order")
        let first = queue.takeNext(generation: 1)!
        precondition(first.key == "a" && queue.takeNext(generation: 1) == nil,
                     "Only one provider request may be in flight")
        queue.enqueue(["a", "b", "c"], generation: 1)
        precondition(queue.pending.map(\.key) == ["b", "c"], "A new pass/touch adds work without replacing earlier saves")
        precondition(queue.remaining(confirmed: 8, unreadKeys: ["a", "b", "c"]) == 5,
                     "Queued and in-flight unread cards tick down immediately")
        precondition(queue.remaining(confirmed: 7, unreadKeys: ["b", "c"]) == 5,
                     "An SSE confirmation before HTTP completion does not double-subtract")
        queue.finish(first)
        precondition(queue.remaining(confirmed: 7, unreadKeys: ["b", "c"]) == 5,
                     "Finishing a confirmed read leaves the displayed total unchanged")
        let failed = queue.takeNext(generation: 1)!
        queue.finish(failed)
        precondition(queue.remaining(confirmed: 7, unreadKeys: ["b", "c"]) == 6,
                     "A failed request restores exactly its optimistic count")
        let third = queue.takeNext(generation: 1)!
        queue.enqueue(["d", "e"], generation: 1)
        queue.cancelPending()
        precondition(queue.pending.isEmpty && queue.inFlight == third && queue.keys == ["c"],
                     "Navigation cancels unstarted reads but lets an already-sent write finish")
        queue.enqueue(["f"], generation: 2)
        queue.finish(third)
        precondition(queue.takeNext(generation: 2)?.key == "f", "A returned session can continue after the older write finishes")
        queue.finish(ScrollReadQueue.Entry(key: "f", generation: 2))
        queue.enqueue(["stale"], generation: 2)
        queue.enqueue(["fresh"], generation: 3)
        precondition(queue.takeNext(generation: 3)?.key == "fresh", "Unstarted work from an old session is discarded")
        precondition(queue.remaining(confirmed: nil, unreadKeys: ["fresh"]) == nil,
                     "An unknown provider total stays unknown")
        precondition(queue.remaining(confirmed: 0, unreadKeys: ["fresh"]) == 0,
                     "A temporarily stale total never produces negative remaining mail")
    }
}
