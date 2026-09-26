import Foundation

@main
enum RefreshArrivalTests {
    static func main() {
        let baseline = RefreshArrivalSnapshot(known: ["a:1", "a:2"], waiting: [])
        precondition(!baseline.hasArrivals(available: ["a:1", "a:2"]), "Unchanged mail must produce no envelopes")
        precondition(!baseline.hasArrivals(available: ["a:2"]), "Reading/removing mail is not an arrival")
        precondition(!baseline.hasArrivals(available: []), "An empty result is not an arrival")
        precondition(baseline.hasArrivals(available: ["a:2", "a:3"]), "Same total, different identity is new mail")
        precondition(baseline.hasArrivals(available: ["a:1", "a:2", "b:1"]), "IDs must retain their mailbox prefix")
        let queued = RefreshArrivalSnapshot(known: ["a:1", "a:2"], waiting: ["a:2"])
        precondition(queued.hasArrivals(available: ["a:1", "a:2"]), "Admitted waiting mail is new to this feed visit")
        precondition(!queued.hasArrivals(available: ["a:1"]), "Removed or deselected waiting mail is not an arrival")
        print("PASS: 7 refresh arrival identity checks")
    }
}
