import Foundation

@main struct FeedPaginationLifecycleTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
        precondition(condition(), reason)
        checks += 1
    }

    static func main() {
        var state = FeedPaginationLifecycle()
        let oldRun = state.beginRun(generation: 1)!
        let oldPage = state.beginPage(account: "a", generation: 1, expectedGeneration: 1)!
        check(state.isLoading(generation: 1), "A run owns the current busy state")
        check(state.beginRun(generation: 1) == nil, "Duplicate pagination is blocked within one visit")
        check(state.beginPage(account: "a", generation: 1, expectedGeneration: 1) == nil,
              "Duplicate requests for an account are blocked")
        check(state.beginPage(account: "b", generation: 1, expectedGeneration: 1) != nil,
              "Different mailboxes may fetch in parallel")

        state.reset()
        check(!state.isLoading(generation: 2), "A reset immediately releases the old visit")
        let newRun = state.beginRun(generation: 2)!
        let newPage = state.beginPage(account: "a", generation: 2, expectedGeneration: 2)!
        state.finishRun(oldRun)
        state.finishPage(account: "a", ticket: oldPage)
        check(state.isLoading(generation: 2), "An old completion cannot release a new run")
        check(state.beginPage(account: "a", generation: 2, expectedGeneration: 2) == nil,
              "An old page completion cannot unlock the replacement request")
        check(state.beginPage(account: "b", generation: 2, expectedGeneration: 1) == nil,
              "A queued old child cannot start its old cursor in a new visit")

        state.finishPage(account: "a", ticket: newPage)
        check(state.beginPage(account: "a", generation: 2, expectedGeneration: 2) != nil,
              "The owning completion permits the next page")
        state.finishRun(newRun)
        check(!state.isLoading(generation: 2), "The owning run releases its busy state")

        let stale = state.beginRun(generation: 2)!
        check(!state.isLoading(generation: 3), "A generation change such as cache clear cannot stay busy")
        let replacement = state.beginRun(generation: 3)!
        state.finishRun(stale)
        check(state.isLoading(generation: 3), "Implicit generation changes also protect replacement work")
        check(state.beginPage(account: "a", generation: 3, expectedGeneration: 3) != nil,
              "New generations can replace stale page ownership without an explicit reset")
        state.finishRun(replacement)
        print("\(checks) production pagination lifecycle checks passed")
    }
}
