import Foundation

/// Arrival art compares message identities, never unread totals. Reading an
/// old card or receiving one replacement card must not invent or hide arrivals.
struct RefreshArrivalSnapshot {
    private let alreadyPresented: Set<String>

    init(known: Set<String>, waiting: Set<String>) {
        // Waiting mail is known to the cache, but still new to this feed visit.
        alreadyPresented = known.subtracting(waiting)
    }

    func hasArrivals(available: Set<String>) -> Bool {
        !available.subtracting(alreadyPresented).isEmpty
    }
}
